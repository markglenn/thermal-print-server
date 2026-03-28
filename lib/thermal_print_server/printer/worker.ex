defmodule ThermalPrintServer.Printer.Worker do
  @moduledoc """
  Sends ZPL to printers. Supports both real IPP printers (via Hippy)
  and virtual printers (rendered via Labelary for testing).
  """

  require Logger

  alias ThermalPrintServer.Printer.Labelary

  @spec print(map(), String.t(), pos_integer()) :: :ok | {:ok, binary()} | {:error, term()}
  def print(%{uri: "virtual:" <> _} = printer, zpl, _copies) do
    Logger.info("Virtual printer '#{printer.name}' — rendering via Labelary")

    case Labelary.render(zpl) do
      {:ok, png_bytes} ->
        {:ok, png_bytes}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def print(%{uri: uri}, zpl, copies) do
    Logger.info("Sending print job to #{uri} (#{copies} copies)")

    Hippy.Operation.PrintJob.new(uri, zpl, job_name: "Thermal", copies: copies)
    |> Hippy.send_operation()
    |> case do
      {:ok, %Hippy.Response{request_id: request_id}} ->
        Logger.info("Print job #{request_id} sent successfully to #{uri}")
        :ok

      {:error, reason} ->
        Logger.error("Print failed to #{uri}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
