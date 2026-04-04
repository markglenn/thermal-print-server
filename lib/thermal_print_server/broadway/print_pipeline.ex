defmodule ThermalPrintServer.Broadway.PrintPipeline do
  @moduledoc """
  Broadway pipeline that consumes print jobs from SQS
  and sends data to printers via IPP.
  """

  use Broadway

  require Logger

  alias ThermalPrintServer.Broadway.MessageParser
  alias ThermalPrintServer.Jobs.{Preview, S3Fetcher, Store}
  alias ThermalPrintServer.Printer.{Registry, Worker}

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwaySQS.Producer,
           queue_url: Application.fetch_env!(:thermal_print_server, :sqs_queue_url),
           receive_interval: 200,
           config: [region: Application.fetch_env!(:thermal_print_server, :aws_region)]},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 4]
      ]
    )
  end

  @impl true
  def handle_message(_processor, message, _context) do
    with {:ok, parsed} <- MessageParser.parse(message.data),
         {:ok, parsed} <- resolve_data(parsed),
         {:ok, printer} <- resolve_printer(parsed),
         :ok <- send_to_printer(printer, parsed) do
      preview = generate_preview(parsed)
      track_success(parsed, preview)
      message
    else
      {:error, reason} ->
        track_failure(message.data, reason)
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn message ->
      Logger.error("Print job failed: #{inspect(message.status)}")
    end)

    messages
  end

  # Fetch data from S3 if the message has an s3_key instead of inline data
  defp resolve_data(%{s3_key: nil} = parsed), do: {:ok, parsed}

  defp resolve_data(%{s3_key: s3_key} = parsed) when is_binary(s3_key) do
    case S3Fetcher.fetch(s3_key) do
      {:ok, data} -> {:ok, %{parsed | data: data, s3_key: nil}}
      {:error, reason} -> {:error, "S3 fetch failed: #{inspect(reason)}"}
    end
  end

  defp resolve_data(parsed), do: {:ok, parsed}

  @spec resolve_printer(MessageParser.parsed()) :: {:ok, map()} | {:error, String.t()}
  defp resolve_printer(parsed) do
    case Registry.lookup(parsed.printer) do
      {:ok, config} -> {:ok, config}
      {:error, :not_found} -> {:error, "unknown printer: #{parsed.printer}"}
    end
  end

  defp send_to_printer(printer, parsed) do
    Worker.print(printer, parsed.data, parsed.content_type, parsed.copies)
  end

  defp generate_preview(parsed) do
    opts = preview_opts(parsed.metadata)

    case Preview.generate(parsed.data, parsed.content_type, opts) do
      {:ok, preview} -> preview
      {:error, _reason} -> nil
    end
  end

  defp preview_opts(metadata) do
    []
    |> maybe_opt(:size, metadata.label_size)
    |> maybe_opt(:dpmm, metadata.dpmm)
  end

  defp maybe_opt(opts, _key, nil), do: opts
  defp maybe_opt(opts, key, val), do: Keyword.put(opts, key, val)

  @spec track_success(MessageParser.parsed(), map() | nil) :: :ok | {:error, term()}
  defp track_success(parsed, preview) do
    attrs =
      %{
        printer: parsed.printer,
        label_name: parsed.metadata.label_name,
        content_type: parsed.content_type,
        status: :completed,
        chunk_index: parsed.chunk_index,
        total_chunks: parsed.total_chunks
      }
      |> maybe_merge(preview)

    Store.record(parsed.job_id, attrs)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, parsed.job_id, attrs}
    )
  end

  defp maybe_merge(attrs, nil), do: attrs
  defp maybe_merge(attrs, preview), do: Map.merge(attrs, preview)

  @spec track_failure(String.t(), term()) :: :ok | {:error, term()}
  defp track_failure(raw_data, reason) do
    job_id =
      case Jason.decode(raw_data) do
        {:ok, %{"jobId" => id}} -> id
        _ -> "unknown-#{System.unique_integer([:positive])}"
      end

    attrs = %{status: :failed, error: inspect(reason)}
    Store.record(job_id, attrs)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, job_id, attrs}
    )
  end
end
