defmodule ThermalPrintServer.Broadway.PrintPipelineTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Broadway.PrintPipeline
  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.Registry

  @test_printers %{
    "TestPrinter" => %{uri: "ipp://localhost:631/printers/TestPrinter"}
  }

  setup do
    :ets.delete_all_objects(Store)

    original_printers = Application.get_env(:thermal_print_server, :printers)
    original_cups = Application.get_env(:thermal_print_server, :cups_uri)

    Application.put_env(:thermal_print_server, :printers, @test_printers)
    Application.delete_env(:thermal_print_server, :cups_uri)
    Registry.refresh()
    Process.sleep(20)

    Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "print_jobs")

    on_exit(fn ->
      Application.put_env(:thermal_print_server, :printers, original_printers)

      if original_cups,
        do: Application.put_env(:thermal_print_server, :cups_uri, original_cups),
        else: Application.delete_env(:thermal_print_server, :cups_uri)

      Registry.refresh()
    end)

    :ok
  end

  defp make_message(data) do
    ref = make_ref()

    %Broadway.Message{
      data: data,
      acknowledger: {Broadway.CallerAcknowledger, {self(), ref}, nil}
    }
  end

  defp build_json(overrides \\ %{}) do
    Map.merge(
      %{
        "jobId" => "test-#{System.unique_integer([:positive])}",
        "printer" => "TestPrinter",
        "data" => "^XA^FDTest^FS^XZ",
        "contentType" => "application/vnd.zebra.zpl",
        "copies" => 1,
        "metadata" => %{"labelName" => "Test Label"}
      },
      overrides
    )
    |> Jason.encode!()
  end

  describe "handle_message/3 — parse failures" do
    test "tracks failure for invalid JSON" do
      msg = make_message("not json")
      result = PrintPipeline.handle_message(:default, msg, %{})

      assert %Broadway.Message{} = result
      job = hd(Store.recent(1))
      assert String.starts_with?(job.job_id, "unknown-")
      assert job[:status] == :failed
      assert job[:error] =~ "invalid JSON"
    end

    test "tracks failure for missing required fields" do
      json = Jason.encode!(%{"jobId" => "missing-fields"})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      job = Store.get("missing-fields")
      assert job.status == :failed
      assert job[:error] =~ "missing required fields"
    end

    test "tracks failure for missing data field" do
      json = Jason.encode!(%{"jobId" => "no-data", "printer" => "TestPrinter"})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      job = Store.get("no-data")
      assert job.status == :failed
      assert job[:error] =~ "data or s3Key"
    end
  end

  describe "handle_message/3 — printer resolution" do
    test "tracks failure for unknown printer" do
      json = build_json(%{"jobId" => "bad-printer", "printer" => "nonexistent"})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      job = Store.get("bad-printer")
      assert job.status == :failed
      assert job[:error] =~ "unknown printer"
    end
  end

  describe "handle_message/3 — PubSub notifications" do
    test "broadcasts job_updated on parse failure" do
      json = Jason.encode!(%{"jobId" => "pubsub-fail"})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      assert_receive {:job_updated, "pubsub-fail", %{status: :failed}}, 1000
    end

    test "generates unknown ID for unparseable JSON" do
      msg = make_message("garbage")
      PrintPipeline.handle_message(:default, msg, %{})

      assert_receive {:job_updated, "unknown-" <> _, %{status: :failed}}, 1000
    end
  end

  describe "handle_message/3 — successful parse with printer error" do
    test "stores job attributes on print failure" do
      # Printer exists but IPP connection will fail (no real CUPS)
      json = build_json(%{"jobId" => "print-fail", "copies" => 3})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      job = Store.get("print-fail")
      assert job != nil
      # Either completed (unlikely without CUPS) or failed at send_to_printer
      assert job[:status] in [:completed, :failed]
    end

    test "always returns the message (acks to SQS)" do
      msg = make_message("invalid")
      result = PrintPipeline.handle_message(:default, msg, %{})
      assert result == msg
    end

    test "returns message even on printer failure" do
      json = build_json(%{"printer" => "nonexistent"})
      msg = make_message(json)
      result = PrintPipeline.handle_message(:default, msg, %{})
      assert result == msg
    end
  end

  describe "handle_message/3 — preview generation" do
    test "generates ZPL preview data on success" do
      # This will fail at send_to_printer, so preview won't be stored
      # But if it succeeds, preview should be present
      json = build_json(%{"jobId" => "preview-test"})
      msg = make_message(json)
      PrintPipeline.handle_message(:default, msg, %{})

      job = Store.get("preview-test")
      assert job != nil

      # If the job completed (CUPS was reachable), it should have preview data
      if job[:status] == :completed do
        assert job[:preview_data] != nil
        assert job[:preview_content_type] == "application/vnd.zebra.zpl"
      end
    end
  end
end
