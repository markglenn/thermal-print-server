defmodule ThermalPrintServer.Printer.WorkerTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Printer.Worker

  describe "print/4" do
    @tag :cups_integration
    test "sends ZPL to printer without document_format" do
      printer = %{uri: "ipp://cups:631/printers/TestZebra-Capture"}
      zpl = "^XA^FO50,50^A0N,40,40^FDWorker Test^FS^XZ"

      assert {:ok, %{cups_job_id: _}} = Worker.print(printer, zpl, "application/vnd.zebra.zpl", 1)
    end

    @tag :cups_integration
    test "sends PDF to printer with document_format" do
      printer = %{uri: "ipp://cups:631/printers/TestZebra-Capture"}
      # Minimal PDF-like data (printer will accept it for test purposes)
      pdf = "%PDF-1.4 test"

      assert {:ok, %{cups_job_id: _}} = Worker.print(printer, pdf, "application/pdf", 1)
    end

    @tag :cups_integration
    test "sends multiple copies" do
      printer = %{uri: "ipp://cups:631/printers/TestZebra-Capture"}
      zpl = "^XA^FO50,50^A0N,40,40^FDCopies Test^FS^XZ"

      assert {:ok, %{cups_job_id: _}} = Worker.print(printer, zpl, "application/vnd.zebra.zpl", 3)
    end

    test "returns error for unreachable printer" do
      printer = %{uri: "ipp://localhost:1/printers/fake"}
      zpl = "^XA^XZ"

      assert {:error, _reason} = Worker.print(printer, zpl, "application/vnd.zebra.zpl", 1)
    end
  end
end
