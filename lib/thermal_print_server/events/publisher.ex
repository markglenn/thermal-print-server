defmodule ThermalPrintServer.Events.Publisher do
  @moduledoc """
  Publishes events to SNS for external consumers (ERP, label editor, etc.).
  Subscribes to internal PubSub channels and publishes job status, printer
  changes, and periodic heartbeats. Also writes printer state snapshots to S3.

  All external I/O (SNS publish, S3 write) runs in fire-and-forget tasks
  under ThermalPrintServer.TaskSupervisor so retries never block this
  GenServer's mailbox.
  """

  use GenServer

  require Logger

  alias ThermalPrintServer.Printer.Registry

  @max_retries 3
  @base_delay 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "print_jobs")
    Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "printers")

    topic_arn = Application.fetch_env!(:thermal_print_server, :response_topic_arn)
    site_id = Application.fetch_env!(:thermal_print_server, :site_id)
    heartbeat_s = Application.get_env(:thermal_print_server, :heartbeat_interval, 60)

    schedule_heartbeat(heartbeat_s)

    # Write initial printer snapshot in case printers were discovered before we started
    printers = Registry.list_all()
    async_write_snapshot(site_id, printers)

    state = %{
      topic_arn: topic_arn,
      site_id: site_id,
      heartbeat_interval: heartbeat_s,
      start_time: System.monotonic_time(:second),
      printer_count: length(printers)
    }

    Logger.info("EventPublisher started: site=#{site_id}, topic=#{topic_arn}")
    {:ok, state}
  end

  @impl true
  def handle_info({:job_updated, job_id, attrs}, state) do
    if attrs[:status] in [:completed, :failed] do
      event = %{
        siteId: state.site_id,
        eventType: "job_status",
        jobId: job_id,
        status: to_string(attrs[:status]),
        printer: attrs[:printer],
        contentType: attrs[:content_type],
        error: attrs[:error],
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      async_publish(state, event, "job_status")
    end

    {:noreply, state}
  end

  def handle_info({:printers_updated, printers}, state) do
    event = %{
      siteId: state.site_id,
      eventType: "printer_change",
      printers: Enum.map(printers, &sanitize_printer/1),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    async_publish(state, event, "printer_change")
    async_write_snapshot(state.site_id, printers)
    {:noreply, %{state | printer_count: length(printers)}}
  end

  def handle_info(:heartbeat, state) do
    uptime = System.monotonic_time(:second) - state.start_time

    event = %{
      siteId: state.site_id,
      eventType: "heartbeat",
      printerCount: state.printer_count,
      uptimeSeconds: uptime,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    async_publish(state, event, "heartbeat")
    async_write_snapshot(state.site_id, Registry.list_all())
    schedule_heartbeat(state.heartbeat_interval)
    {:noreply, state}
  end

  # -- Async wrappers --
  # All external I/O is dispatched to the TaskSupervisor.
  # If the task crashes, it's logged and discarded — the Publisher stays up.

  defp async_publish(state, event, event_type) do
    Task.Supervisor.start_child(ThermalPrintServer.TaskSupervisor, fn ->
      publish(state, event, event_type)
    end)
  end

  defp async_write_snapshot(site_id, printers) do
    Task.Supervisor.start_child(ThermalPrintServer.TaskSupervisor, fn ->
      write_printer_snapshot(site_id, printers)
    end)
  end

  # -- Synchronous implementations (run inside tasks) --

  defp publish(state, event, event_type) do
    message = Jason.encode!(event)

    attrs = [
      %{name: "site_id", data_type: :string, value: {:string, state.site_id}},
      %{name: "event_type", data_type: :string, value: {:string, event_type}}
    ]

    request = ExAws.SNS.publish(message, topic_arn: state.topic_arn, message_attributes: attrs)

    case retry(fn -> ExAws.request(request) end) do
      {:ok, _} ->
        Logger.debug("Published #{event_type} event for site #{state.site_id}")

      {:error, reason} ->
        Logger.error(
          "Failed to publish #{event_type} after #{@max_retries} attempts: #{inspect(reason)}"
        )
    end
  end

  defp write_printer_snapshot(site_id, printers) do
    bucket = Application.get_env(:thermal_print_server, :print_bucket)

    if bucket do
      key = "sites/#{site_id}/manifest.json"

      body =
        Jason.encode!(%{
          siteId: site_id,
          siteName: Application.get_env(:thermal_print_server, :site_name, site_id),
          queueUrl: Application.get_env(:thermal_print_server, :sqs_queue_url),
          printers: Enum.map(printers, &sanitize_printer/1),
          updatedAt: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      request = ExAws.S3.put_object(bucket, key, body, content_type: "application/json")

      case retry(fn -> ExAws.request(request) end) do
        {:ok, _} ->
          Logger.debug("Wrote printer snapshot to s3://#{bucket}/#{key}")

        {:error, reason} ->
          Logger.error(
            "Failed to write printer snapshot after #{@max_retries} attempts: #{inspect(reason)}"
          )
      end
    end
  end

  defp retry(fun, attempt \\ 1) do
    case fun.() do
      {:ok, _} = success ->
        success

      {:error, _} = error when attempt >= @max_retries ->
        error

      {:error, _} ->
        Process.sleep(@base_delay * attempt)
        retry(fun, attempt + 1)
    end
  end

  defp sanitize_printer(printer) do
    Map.take(printer, [
      :name,
      :state,
      :info,
      :location,
      :resolution,
      :resolution_default,
      :media_default,
      :media_ready,
      :media_supported
    ])
  end

  defp schedule_heartbeat(seconds) do
    Process.send_after(self(), :heartbeat, :timer.seconds(seconds))
  end
end
