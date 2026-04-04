defmodule ThermalPrintServer.Jobs.PreviewTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Jobs.Preview

  describe "generate/2 — PDF" do
    test "returns base64-encoded PDF data as-is" do
      pdf_data = "fake-pdf-bytes"
      assert {:ok, preview} = Preview.generate(pdf_data, "application/pdf")
      assert preview.preview_content_type == "application/pdf"
      assert preview.preview_data == Base.encode64(pdf_data)
    end
  end

  describe "generate/2 — ZPL" do
    # ZPL preview requires Labelary API access, so we tag it
    @tag :external_api
    test "renders ZPL to PNG via Labelary" do
      zpl = "^XA^FO50,50^A0N,40,40^FDTest^FS^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl")
      assert preview.preview_content_type == "image/png"
      assert is_binary(preview.preview_data)

      # Should be valid base64
      assert {:ok, png_bytes} = Base.decode64(preview.preview_data)
      # PNG magic bytes
      assert <<0x89, 0x50, 0x4E, 0x47, _rest::binary>> = png_bytes
    end

    @tag :external_api
    test "returns error for invalid ZPL" do
      assert {:error, _reason} = Preview.generate("not zpl at all", "application/vnd.zebra.zpl")
    end
  end
end
