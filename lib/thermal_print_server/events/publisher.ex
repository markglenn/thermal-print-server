defmodule ThermalPrintServer.Events.Publisher do
  @moduledoc """
  Sends job-status responses to the reply queue specified per request,
  and writes the printer-state snapshot to S3.

  `job_status` is a point-to-point response: each request message may carry
  a `replyToQueueUrl`; when the job completes or fails, the response is sent
  to that queue. If no reply URL was supplied, the response is dropped.

  Printer state and liveness are published passively via the S3 snapshot
  (`sites/{site_id}/manifest.json`), refreshed on startup, printer changes,
  and each heartbeat. Consumers check the object's S3 `LastModified` for
  staleness — no active heartbeat event is emitted.

  All external I/O (SQS send, S3 write) runs in fire-and-forget tasks
  under ThermalPrintServer.TaskSupervisor so retries never block this
  GenServer's mailbox.
  """

  use GenServer

  require Logger

  alias ThermalPrintServer.Printer.Registry

  # ex_aws_sqs's sqs_message_attribute typespec declares `custom_type` required,
  # but its implementation treats it optional. Suppress the false positive.
  @dialyzer {:nowarn_function, [send_response: 3, async_send_response: 3]}

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

    site_id = Application.fetch_env!(:thermal_print_server, :site_id)
    heartbeat_s = Application.get_env(:thermal_print_server, :heartbeat_interval, 60)

    schedule_heartbeat(heartbeat_s)

    # Write initial printer snapshot in case printers were discovered before we started
    printers = Registry.list_all()
    async_write_snapshot(site_id, printers)

    state = %{
      site_id: site_id,
      heartbeat_interval: heartbeat_s
    }

    Logger.info("EventPublisher started: site=#{site_id}")
    {:ok, state}
  end

  @impl true
  def handle_info({:job_updated, job_id, attrs}, state) do
    with true <- attrs[:status] in [:completed, :failed],
         queue_url when is_binary(queue_url) <- attrs[:reply_to_queue_url] do
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

      async_send_response(state, queue_url, event)
    end

    {:noreply, state}
  end

  def handle_info({:printers_updated, printers}, state) do
    async_write_snapshot(state.site_id, printers)
    {:noreply, state}
  end

  def handle_info(:heartbeat, state) do
    async_write_snapshot(state.site_id, Registry.list_all())
    schedule_heartbeat(state.heartbeat_interval)
    {:noreply, state}
  end

  # -- Async wrappers --
  # All external I/O is dispatched to the TaskSupervisor.
  # If the task crashes, it's logged and discarded — the Publisher stays up.

  defp async_send_response(state, queue_url, event) do
    Task.Supervisor.start_child(ThermalPrintServer.TaskSupervisor, fn ->
      send_response(state, queue_url, event)
    end)
  end

  defp async_write_snapshot(site_id, printers) do
    Task.Supervisor.start_child(ThermalPrintServer.TaskSupervisor, fn ->
      write_printer_snapshot(site_id, printers)
    end)
  end

  # -- Synchronous implementations (run inside tasks) --

  defp send_response(state, queue_url, event) do
    body = Jason.encode!(event)

    attrs = [
      %{name: "site_id", data_type: :string, value: state.site_id},
      %{name: "event_type", data_type: :string, value: event.eventType}
    ]

    request = ExAws.SQS.send_message(queue_url, body, message_attributes: attrs)

    case retry(fn -> ExAws.request(request) end) do
      {:ok, _} ->
        Logger.debug("Sent job_status for #{event.jobId} to #{queue_url}")

      {:error, reason} ->
        Logger.error(
          "Failed to send job_status for #{event.jobId} after #{@max_retries} attempts: #{inspect(reason)}"
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
      :media_ready
    ])
  end

  defp schedule_heartbeat(seconds) do
    Process.send_after(self(), :heartbeat, :timer.seconds(seconds))
  end
end
