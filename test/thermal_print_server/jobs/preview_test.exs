defmodule ThermalPrintServer.Jobs.PreviewTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Jobs.Preview

  describe "generate/3 — PDF" do
    test "returns base64-encoded PDF data" do
      pdf_data = "fake-pdf-bytes"
      assert {:ok, preview} = Preview.generate(pdf_data, "application/pdf")
      assert preview.preview_content_type == "application/pdf"
      assert preview.preview_data == Base.encode64(pdf_data)
    end

    test "round-trips through base64" do
      pdf_data = :crypto.strong_rand_bytes(256)
      assert {:ok, preview} = Preview.generate(pdf_data, "application/pdf")
      assert {:ok, ^pdf_data} = Base.decode64(preview.preview_data)
    end
  end

  describe "generate/3 — ZPL" do
    test "returns raw ZPL for client-side rendering" do
      zpl = "^XA^FO50,50^A0N,40,40^FDTest^FS^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl")
      assert preview.preview_content_type == "application/vnd.zebra.zpl"
      assert preview.preview_data == zpl
    end

    test "defaults label size to 4x6" do
      zpl = "^XA^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl")
      assert preview.preview_label_size == "4x6"
    end

    test "defaults dpmm to 8dpmm" do
      zpl = "^XA^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl")
      assert preview.preview_dpmm == "8dpmm"
    end

    test "passes through custom label size" do
      zpl = "^XA^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl", size: "2x1")
      assert preview.preview_label_size == "2x1"
    end

    test "passes through custom dpmm" do
      zpl = "^XA^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl", dpmm: "12dpmm")
      assert preview.preview_dpmm == "12dpmm"
    end

    test "preserves multi-label ZPL data" do
      zpl = "^XA^FDLabel1^FS^XZ^XA^FDLabel2^FS^XZ^XA^FDLabel3^FS^XZ"
      assert {:ok, preview} = Preview.generate(zpl, "application/vnd.zebra.zpl")
      assert preview.preview_data == zpl
    end
  end
end
