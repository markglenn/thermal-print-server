defmodule ThermalPrintServer.Printer.JobWatcher do
  @moduledoc """
  Polls CUPS via `Get-Job-Attributes` for a submitted job until it reaches
  a terminal IPP state (completed/canceled/aborted) or the deadline passes.

  Broadway used to mark a job `:completed` the moment Hippy's `Print-Job`
  returned — which only means "CUPS accepted the submission," not that the
  printer actually produced the label. This watcher closes that gap by
  polling the real job state; an unplugged printer surfaces as `:blocked`
  with CUPS's `job-state-reasons` visible on the dashboard.
  """

  require Logger

  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.Registry

  @default_poll_interval 5_000
  @default_max_duration :timer.minutes(2)
  @ipp_timeout 10_000

  @spec start(map(), String.t(), pos_integer()) :: DynamicSupervisor.on_start_child()
  def start(printer, job_id, cups_job_id) do
    Task.Supervisor.start_child(
      ThermalPrintServer.TaskSupervisor,
      fn -> watch(printer, job_id, cups_job_id) end
    )
  end

  @spec watch(map(), String.t(), pos_integer()) :: :ok
  def watch(%{uri: uri}, job_id, cups_job_id) do
    deadline = System.monotonic_time(:millisecond) + max_duration()
    poll(uri, job_id, cups_job_id, deadline, nil)
  end

  defp poll(uri, job_id, cups_job_id, deadline, last_observed) do
    if System.monotonic_time(:millisecond) >= deadline do
      Logger.warning(
        "JobWatcher timed out for job #{job_id} (cups_job_id=#{cups_job_id}); marking :blocked"
      )

      update_job(job_id, %{status: :blocked, cups_job_state_reasons: ["watch-timeout"]})
    else
      case fetch_state(uri, cups_job_id) do
        {:ok, observed} ->
          if observed != last_observed, do: update_job(job_id, to_attrs(observed))

          if terminal?(observed.state) do
            :ok
          else
            Process.sleep(poll_interval())
            poll(uri, job_id, cups_job_id, deadline, observed)
          end

        {:error, reason} ->
          Logger.debug(
            "JobWatcher poll failed for #{job_id} (cups_job_id=#{cups_job_id}): #{inspect(reason)}"
          )

          Process.sleep(poll_interval())
          poll(uri, job_id, cups_job_id, deadline, last_observed)
      end
    end
  end

  defp poll_interval do
    Application.get_env(:thermal_print_server, :job_watcher_poll_interval, @default_poll_interval)
  end

  defp max_duration do
    Application.get_env(:thermal_print_server, :job_watcher_max_duration, @default_max_duration)
  end

  defp fetch_state(uri, cups_job_id) do
    task =
      Task.async(fn ->
        Hippy.Operation.GetJobAttributes.new(uri, cups_job_id,
          requested_attributes: ["job-state", "job-state-reasons", "job-state-message"]
        )
        |> Hippy.send_operation()
      end)

    case Task.yield(task, @ipp_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Hippy.Response{job_attributes: attrs}}} ->
        flat = List.flatten(attrs)

        {:ok,
         %{
           state: find_attr(flat, "job-state"),
           reasons: normalize_reasons(find_attr(flat, "job-state-reasons")),
           message: normalize_message(find_attr(flat, "job-state-message"))
         }}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        {:error, :timeout}
    end
  end

  # `attrs` is already flattened by fetch_state/2.
  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {_type, ^name, value} -> value
      _ -> nil
    end)
  end

  @doc false
  def normalize_reasons(nil), do: []
  def normalize_reasons("none"), do: []
  def normalize_reasons(""), do: []
  def normalize_reasons(reason) when is_binary(reason), do: [reason]

  def normalize_reasons(reasons) when is_list(reasons) do
    Enum.reject(reasons, &(&1 in [nil, "", "none"]))
  end

  def normalize_reasons(_), do: []

  defp normalize_message(nil), do: nil
  defp normalize_message(""), do: nil
  defp normalize_message(msg) when is_binary(msg), do: msg
  defp normalize_message(_), do: nil

  defp to_attrs(%{state: state, reasons: reasons, message: message}) do
    %{
      status: map_status(state),
      cups_job_state: state,
      cups_job_state_reasons: reasons,
      cups_job_state_message: message
    }
  end

  @doc false
  def terminal?(state) when state in [:completed, :canceled, :aborted], do: true
  def terminal?(_), do: false

  # Map IPP job-state → dashboard status. `:blocked` is a new terminal-ish
  # bucket for jobs CUPS has parked (e.g. printer offline / out of media).
  # Cancellation is intentional, so it gets its own bucket distinct from
  # `:failed` (which is reserved for things actually going wrong, incl. aborts).
  @doc false
  def map_status(:completed), do: :completed
  def map_status(:canceled), do: :canceled
  def map_status(:aborted), do: :failed
  def map_status(:processing_stopped), do: :blocked
  def map_status(_), do: :printing

  # Broadcast the full merged record so subscribers that don't re-read from
  # the Store (e.g. Events.Publisher) still see the job's reply_to_queue_url
  # and other fields that were only set in the original track_success write.
  defp update_job(job_id, delta) do
    previous_status = Store.get(job_id)[:status]
    Store.record(job_id, delta)
    full = Store.get(job_id) || delta

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, job_id, full}
    )

    # When a job first transitions to :blocked, kick a printer-state refresh
    # so the dashboard's printer-state-reasons catch up without waiting for
    # the next scheduled poll. Cheap — it's an async cast.
    if delta[:status] == :blocked and previous_status != :blocked do
      Registry.refresh()
    end
  end
end
