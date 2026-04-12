defmodule ThermalPrintServer.Printer.Worker do
  @moduledoc """
  Sends print data to printers via IPP (Hippy).
  Supports both ZPL and PDF content types.
  """

  require Logger

  # 30-second timeout for IPP operations
  @print_timeout 30_000

  @spec print(map(), String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def print(%{uri: uri}, data, content_type, copies) do
    Logger.info("Sending #{content_type} print job to #{uri} (#{copies} copies)")

    job_opts = [job_name: "Thermal", copies: copies]

    job_opts =
      case content_type do
        "application/vnd.zebra.zpl" -> job_opts
        mime -> Keyword.put(job_opts, :document_format, mime)
      end

    task =
      Task.async(fn ->
        Hippy.Operation.PrintJob.new(uri, data, job_opts)
        |> Hippy.send_operation()
      end)

    case Task.yield(task, @print_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Hippy.Response{request_id: request_id}}} ->
        Logger.info("Print job #{request_id} sent successfully to #{uri}")
        :ok

      {:ok, {:error, reason}} ->
        Logger.error("Print failed to #{uri}: #{inspect(reason)}")
        {:error, reason}

      nil ->
        Logger.error("Print timed out after #{@print_timeout}ms to #{uri}")
        {:error, :timeout}
    end
  end
end
