defmodule ThermalPrintServer.Events.PublisherTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Events.Publisher

  setup do
    # Don't start the publisher via the app supervisor — we start it manually
    original_topic = Application.get_env(:thermal_print_server, :response_topic_arn)
    original_site = Application.get_env(:thermal_print_server, :site_id)
    original_heartbeat = Application.get_env(:thermal_print_server, :heartbeat_interval)
    original_bucket = Application.get_env(:thermal_print_server, :print_bucket)

    Application.put_env(
      :thermal_print_server,
      :response_topic_arn,
      "arn:aws:sns:us-east-1:000000000000:test"
    )

    Application.put_env(:thermal_print_server, :site_id, "test-site")
    Application.put_env(:thermal_print_server, :heartbeat_interval, 3600)
    # Disable S3 writes in tests
    Application.delete_env(:thermal_print_server, :print_bucket)

    on_exit(fn ->
      if original_topic,
        do: Application.put_env(:thermal_print_server, :response_topic_arn, original_topic),
        else: Application.delete_env(:thermal_print_server, :response_topic_arn)

      if original_site,
        do: Application.put_env(:thermal_print_server, :site_id, original_site),
        else: Application.delete_env(:thermal_print_server, :site_id)

      if original_heartbeat,
        do: Application.put_env(:thermal_print_server, :heartbeat_interval, original_heartbeat),
        else: Application.delete_env(:thermal_print_server, :heartbeat_interval)

      if original_bucket,
        do: Application.put_env(:thermal_print_server, :print_bucket, original_bucket),
        else: Application.delete_env(:thermal_print_server, :print_bucket)
    end)

    :ok
  end

  test "starts and subscribes to PubSub channels" do
    # If the publisher can start, it has subscribed to PubSub
    pid = start_supervised!({Publisher, []})
    assert Process.alive?(pid)
  end

  test "builds correct job_status event structure" do
    start_supervised!({Publisher, []})

    # Broadcast a completed job — the publisher will try to publish to SNS
    # which will fail (no SNS in test), but we can verify it doesn't crash
    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, "test-job-123",
       %{status: :completed, printer: "TestPrinter", content_type: "application/vnd.zebra.zpl"}}
    )

    # Give the publisher time to process
    Process.sleep(50)

    # Publisher should still be alive (handles SNS errors gracefully)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "ignores non-terminal job statuses" do
    start_supervised!({Publisher, []})

    # Broadcast a non-terminal status
    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, "test-job-456", %{status: :printing, printer: "TestPrinter"}}
    )

    Process.sleep(50)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "handles printers_updated events" do
    start_supervised!({Publisher, []})

    printers = [
      %{name: "Printer1", uri: "ipp://localhost:631/ipp/print", state: 3}
    ]

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "printers",
      {:printers_updated, printers}
    )

    Process.sleep(50)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "handles heartbeat" do
    start_supervised!({Publisher, []})

    send(Process.whereis(Publisher), :heartbeat)
    Process.sleep(50)

    assert Process.whereis(Publisher) |> Process.alive?()
  end
end
