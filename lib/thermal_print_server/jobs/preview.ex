defmodule ThermalPrintServer.Jobs.Preview do
  @moduledoc """
  Generates preview data for print jobs.
  ZPL is passed through for client-side rendering. PDF is used directly.
  """

  @spec generate(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate(data, content_type, opts \\ []) do
    case content_type do
      "application/vnd.zebra.zpl" -> generate_zpl_preview(data, opts)
      "application/pdf" -> generate_pdf_preview(data)
      other -> {:error, "unsupported content type for preview: #{other}"}
    end
  end

  defp generate_zpl_preview(zpl, opts) do
    {:ok,
     %{
       preview_data: zpl,
       preview_content_type: "application/vnd.zebra.zpl",
       preview_label_size: Keyword.get(opts, :size, "4x6"),
       preview_dpmm: Keyword.get(opts, :dpmm, "8dpmm")
     }}
  end

  defp generate_pdf_preview(pdf_data) do
    {:ok, %{preview_data: Base.encode64(pdf_data), preview_content_type: "application/pdf"}}
  end
end
