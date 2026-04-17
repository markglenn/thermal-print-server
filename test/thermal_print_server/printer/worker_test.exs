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

  # job_attributes came back from CUPS as a list of attribute groups — i.e.
  # a list of lists — not a flat list of tuples. Getting this wrong silently
  # yields cups_job_id=nil, which disables the watcher. Worth a direct test.
  describe "extract_job_id/1" do
    test "pulls job-id from the nested attribute-group shape CUPS actually returns" do
      attrs = [
        [
          {:uri, "job-uri", "ipp://cups:631/jobs/42"},
          {:integer, "job-id", 42},
          {:enum, "job-state", :pending}
        ]
      ]

      assert Worker.extract_job_id(attrs) == 42
    end

    test "also works for a flat list of tuples" do
      attrs = [{:integer, "job-id", 7}, {:enum, "job-state", :pending}]
      assert Worker.extract_job_id(attrs) == 7
    end

    test "returns nil when no job-id is present" do
      assert Worker.extract_job_id([]) == nil
      assert Worker.extract_job_id([[{:enum, "job-state", :pending}]]) == nil
    end

    test "ignores non-integer job-id values defensively" do
      assert Worker.extract_job_id([{:integer, "job-id", "not-an-int"}]) == nil
    end
  end

  describe "ipp_successful?/1" do
    test "recognises the successful_* family" do
      assert Worker.ipp_successful?(:successful_ok)
      assert Worker.ipp_successful?(:successful_ok_ignored_or_substituted_attributes)
    end

    test "rejects client and server errors" do
      refute Worker.ipp_successful?(:client_error_bad_request)
      refute Worker.ipp_successful?(:client_error_document_format_not_supported)
      refute Worker.ipp_successful?(:server_error_busy)
    end

    test "rejects non-atoms defensively" do
      refute Worker.ipp_successful?(nil)
      refute Worker.ipp_successful?("successful_ok")
    end
  end
end
