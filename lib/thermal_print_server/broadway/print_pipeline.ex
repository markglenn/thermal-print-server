defmodule ThermalPrintServer.Broadway.PrintPipeline do
  @moduledoc """
  Broadway pipeline that consumes print jobs from SQS
  and sends data to printers via IPP.
  """

  use Broadway

  require Logger

  alias ThermalPrintServer.Broadway.MessageParser
  alias ThermalPrintServer.Jobs.{Preview, S3Fetcher, Store}
  alias ThermalPrintServer.Printer.{JobWatcher, Registry, Worker}

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwaySQS.Producer,
           queue_url: Application.fetch_env!(:thermal_print_server, :sqs_queue_url),
           wait_time_seconds: 20,
           config: [region: Application.fetch_env!(:thermal_print_server, :aws_region)]},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 4]
      ],
      batchers: []
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    case run(message.data) do
      :ok ->
        message

      {:duplicate, job_id} ->
        Logger.info("Skipping duplicate job #{job_id}")
        message

      {:permanent, reason} ->
        Logger.error(
          "Print job failed (permanent): #{inspect(reason)}\n  Raw data: #{message.data}"
        )

        track_failure(message.data, reason)
        message

      {:transient, reason} ->
        Logger.warning("Print job failed (will retry via SQS redelivery): #{inspect(reason)}")
        Broadway.Message.failed(message, inspect(reason))
    end
  end

  @impl true
  def handle_failed(messages, _context), do: messages

  defp run(raw) do
    with {:ok, parsed} <- parse_message(raw),
         :ok <- check_duplicate(parsed),
         {:ok, parsed} <- resolve_data(parsed),
         {:ok, printer} <- resolve_printer(parsed),
         {:ok, print_result} <- send_to_printer(printer, parsed) do
      preview = generate_preview(parsed)
      track_success(parsed, printer, print_result, preview)
    end
  end

  defp parse_message(raw) do
    case MessageParser.parse(raw) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:permanent, "parse error: #{reason}"}
    end
  end

  # Any recorded status means we've already accepted this job into CUPS (or
  # recorded a permanent failure); transient errors aren't recorded so SQS
  # redelivery remains eligible.
  defp check_duplicate(%{job_id: job_id}) do
    case Store.get(job_id) do
      %{status: status}
      when status in [:completed, :failed, :printing, :blocked, :canceled] ->
        {:duplicate, job_id}

      _ ->
        :ok
    end
  end

  defp resolve_data(%{s3_key: nil} = parsed), do: {:ok, parsed}

  defp resolve_data(%{s3_key: s3_key} = parsed) when is_binary(s3_key) do
    case S3Fetcher.fetch(s3_key) do
      {:ok, data} -> {:ok, %{parsed | data: data, s3_key: nil}}
      {:error, reason} -> {:transient, "S3 fetch failed: #{inspect(reason)}"}
    end
  end

  defp resolve_printer(parsed) do
    case Registry.lookup(parsed.printer) do
      {:ok, config} -> {:ok, config}
      {:error, :not_found} -> {:permanent, "unknown printer: #{parsed.printer}"}
    end
  end

  defp send_to_printer(printer, parsed) do
    case Worker.print(printer, parsed.data, parsed.content_type, parsed.copies) do
      {:ok, result} ->
        {:ok, result}

      # IPP-level rejection (bad format, not authorized, …). Retrying won't
      # help — show it on the dashboard instead of burning SQS redeliveries.
      {:error, {:ipp_error, code}} ->
        {:permanent, "printer rejected job: #{code}"}

      # Network / timeout — these can resolve on their own.
      {:error, reason} ->
        {:transient, "print failed: #{inspect(reason)}"}
    end
  end

  defp generate_preview(parsed) do
    opts = preview_opts(parsed.metadata)

    case Preview.generate(parsed.data, parsed.content_type, opts) do
      {:ok, preview} ->
        preview

      {:error, reason} ->
        Logger.warning("Preview generation failed for #{parsed.job_id}: #{inspect(reason)}")
        nil
    end
  end

  defp preview_opts(metadata) do
    []
    |> maybe_opt(:size, metadata.label_size)
    |> maybe_opt(:dpmm, metadata.dpmm)
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, val), do: Keyword.put(opts, key, val)

  defp count_pages(%{content_type: "application/vnd.zebra.zpl", data: data, copies: copies})
       when is_binary(data) do
    labels = data |> String.upcase() |> String.split("^XA") |> length() |> Kernel.-(1) |> max(1)
    labels * copies
  end

  defp count_pages(%{content_type: "application/pdf", data: data, copies: copies})
       when is_binary(data) do
    # Count PDF page objects via /Type /Page (excluding /Type /Pages)
    pages =
      data
      |> String.split("/Type /Page")
      |> length()
      |> Kernel.-(1)
      |> max(1)

    pages * copies
  end

  defp count_pages(%{copies: copies}), do: copies

  @spec track_success(MessageParser.parsed(), map(), map(), map() | nil) ::
          :ok | {:error, term()}
  defp track_success(parsed, printer, print_result, preview) do
    cups_job_id = print_result[:cups_job_id]

    # CUPS normally returns a job-id we can poll to a terminal state. If it
    # doesn't, we have no way to verify what the printer actually did — so
    # mark `:blocked` to flag it on the dashboard rather than lying about
    # completion.
    attrs =
      cond do
        cups_job_id ->
          %{cups_job_id: cups_job_id, status: :printing}

        true ->
          Logger.warning(
            "CUPS returned no job-id for #{parsed.job_id}; marking :blocked (unverifiable)"
          )

          %{status: :blocked, cups_job_state_reasons: ["no-cups-job-id"]}
      end

    attrs =
      attrs
      |> Map.merge(%{
        printer: parsed.printer,
        label_name: parsed.metadata.label_name,
        content_type: parsed.content_type,
        copies: parsed.copies,
        page_count: count_pages(parsed),
        reply_to_queue_url: parsed.reply_to_queue_url
      })
      |> maybe_merge(preview)

    Store.record(parsed.job_id, attrs)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, parsed.job_id, attrs}
    )

    if cups_job_id, do: JobWatcher.start(printer, parsed.job_id, cups_job_id)

    :ok
  end

  defp maybe_merge(attrs, nil), do: attrs
  defp maybe_merge(attrs, preview), do: Map.merge(attrs, preview)

  @spec track_failure(String.t(), term()) :: :ok | {:error, term()}
  defp track_failure(raw_data, reason) do
    {job_id, reply_to_queue_url} =
      case Jason.decode(raw_data) do
        {:ok, %{"jobId" => id} = decoded} -> {id, decoded["replyToQueueUrl"]}
        _ -> {"unknown-#{System.unique_integer([:positive])}", nil}
      end

    attrs = %{status: :failed, error: inspect(reason), reply_to_queue_url: reply_to_queue_url}
    Store.record(job_id, attrs)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, job_id, attrs}
    )
  end
end
