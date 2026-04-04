defmodule ThermalPrintServer.Jobs.Preview do
  @moduledoc """
  Generates preview images for print jobs.
  ZPL is rendered to PNG via Labelary. PDF is used directly.
  """

  require Logger

  alias ThermalPrintServer.Printer.Labelary

  @spec generate(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def generate(data, content_type) do
    case content_type do
      "application/vnd.zebra.zpl" -> generate_zpl_preview(data)
      "application/pdf" -> generate_pdf_preview(data)
    end
  end

  defp generate_zpl_preview(zpl) do
    case Labelary.render(zpl) do
      {:ok, png_bytes} ->
        {:ok, %{preview_data: Base.encode64(png_bytes), preview_content_type: "image/png"}}

      {:error, reason} ->
        Logger.warning("Preview generation failed for ZPL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_pdf_preview(pdf_data) do
    {:ok, %{preview_data: Base.encode64(pdf_data), preview_content_type: "application/pdf"}}
  end
end
