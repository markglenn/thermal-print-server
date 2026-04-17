defmodule ThermalPrintServer.Events.PublisherTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Events.Publisher

  setup do
    original_site = Application.get_env(:thermal_print_server, :site_id)
    original_heartbeat = Application.get_env(:thermal_print_server, :heartbeat_interval)
    original_bucket = Application.get_env(:thermal_print_server, :print_bucket)

    # Stop the app-supervised Publisher (started from dev env) so each test
    # can bring up a fresh one with the test-specific config below.
    if pid = Process.whereis(Publisher) do
      ref = Process.monitor(pid)
      Supervisor.terminate_child(ThermalPrintServer.Supervisor, Publisher)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        500 -> :ok
      end
    end

    Application.put_env(:thermal_print_server, :site_id, "test-site")
    Application.put_env(:thermal_print_server, :heartbeat_interval, 3600)
    # Disable S3 writes in tests
    Application.delete_env(:thermal_print_server, :print_bucket)

    on_exit(fn ->
      if original_site,
        do: Application.put_env(:thermal_print_server, :site_id, original_site),
        else: Application.delete_env(:thermal_print_server, :site_id)

      if original_heartbeat,
        do: Application.put_env(:thermal_print_server, :heartbeat_interval, original_heartbeat),
        else: Application.delete_env(:thermal_print_server, :heartbeat_interval)

      if original_bucket,
        do: Application.put_env(:thermal_print_server, :print_bucket, original_bucket),
        else: Application.delete_env(:thermal_print_server, :print_bucket)

      # Bring the app-supervised Publisher back so later tests see it running.
      Supervisor.restart_child(ThermalPrintServer.Supervisor, Publisher)
    end)

    :ok
  end

  test "starts and subscribes to PubSub channels" do
    pid = start_supervised!({Publisher, []})
    assert Process.alive?(pid)
  end

  test "handles completed job with reply_to_queue_url" do
    start_supervised!({Publisher, []})

    # Job with a reply queue — Publisher will try to send via SQS,
    # which fails in test (no SQS endpoint), but the Publisher must stay alive.
    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, "test-job-123",
       %{
         status: :completed,
         printer: "TestPrinter",
         content_type: "application/vnd.zebra.zpl",
         reply_to_queue_url: "http://localhost:4100/000000000000/replies"
       }}
    )

    Process.sleep(50)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "skips completed job when reply_to_queue_url is nil" do
    start_supervised!({Publisher, []})

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, "test-job-no-reply",
       %{
         status: :completed,
         printer: "TestPrinter",
         content_type: "application/vnd.zebra.zpl",
         reply_to_queue_url: nil
       }}
    )

    Process.sleep(50)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "ignores non-terminal job statuses" do
    start_supervised!({Publisher, []})

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, "test-job-456", %{status: :printing, printer: "TestPrinter"}}
    )

    Process.sleep(50)
    assert Process.whereis(Publisher) |> Process.alive?()
  end

  test "handles printers_updated events (S3 snapshot only)" do
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

  test "handles heartbeat (S3 snapshot only)" do
    start_supervised!({Publisher, []})

    send(Process.whereis(Publisher), :heartbeat)
    Process.sleep(50)

    assert Process.whereis(Publisher) |> Process.alive?()
  end

  # The wire protocol promises clients only "completed" and "failed". Dashboard
  # sub-statuses (:canceled, :blocked) must collapse to "failed" so we don't
  # strand clients that don't know about the newer terminal states.
  describe "wire_status/1" do
    test ":completed is the only atom that stays \"completed\"" do
      assert Publisher.wire_status(:completed) == "completed"
    end

    test ":failed stays \"failed\"" do
      assert Publisher.wire_status(:failed) == "failed"
    end

    test ":canceled collapses to \"failed\" for client back-compat" do
      assert Publisher.wire_status(:canceled) == "failed"
    end

    test ":blocked collapses to \"failed\" for client back-compat" do
      assert Publisher.wire_status(:blocked) == "failed"
    end
  end
end
