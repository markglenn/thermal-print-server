defmodule ThermalPrintServer.Broadway.PrintPipeline do
  @moduledoc """
  Broadway pipeline that consumes print jobs from SQS,
  verifies signatures, and sends ZPL to printers via IPP.
  """

  use Broadway

  require Logger

  alias ThermalPrintServer.Broadway.MessageParser
  alias ThermalPrintServer.Jobs.{Store, Verifier}
  alias ThermalPrintServer.Printer.{Registry, Worker}

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module:
          {BroadwaySQS.Producer,
           queue_url: Application.fetch_env!(:thermal_print_server, :sqs_queue_url),
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
         :ok <- verify_signature(parsed),
         {:ok, printer} <- resolve_printer(parsed),
         {:ok, preview_png} <- send_to_printer(printer, parsed) do
      track_success(parsed, preview_png)
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

  @spec verify_signature(MessageParser.parsed()) :: :ok | {:error, String.t()}
  defp verify_signature(parsed) do
    if Verifier.verify(parsed.job_id, parsed.chunk_index, parsed.zpl, parsed.signature) do
      :ok
    else
      {:error, "invalid signature"}
    end
  end

  @spec resolve_printer(MessageParser.parsed()) :: {:ok, map()} | {:error, String.t()}
  defp resolve_printer(parsed) do
    case Registry.lookup(parsed.printer) do
      {:ok, config} -> {:ok, config}
      {:error, :not_found} -> {:error, "unknown printer: #{parsed.printer}"}
    end
  end

  @spec send_to_printer(map(), MessageParser.parsed()) :: {:ok, binary() | nil} | {:error, term()}
  defp send_to_printer(printer, parsed) do
    case Worker.print(printer, parsed.zpl, parsed.copies) do
      :ok -> {:ok, nil}
      {:ok, png_bytes} -> {:ok, png_bytes}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec track_success(MessageParser.parsed(), binary() | nil) :: :ok | {:error, term()}
  defp track_success(parsed, preview_png) do
    attrs = %{
      printer: parsed.printer,
      label_name: parsed.metadata.label_name,
      status: :completed,
      chunk_index: parsed.chunk_index,
      total_chunks: parsed.total_chunks,
      preview_png: preview_png
    }

    Store.record(parsed.job_id, attrs)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, parsed.job_id, attrs}
    )
  end

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
