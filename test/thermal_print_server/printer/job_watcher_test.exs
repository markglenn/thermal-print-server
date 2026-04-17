defmodule ThermalPrintServer.Printer.JobWatcherTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.JobWatcher

  setup do
    :ets.delete_all_objects(Store)
    Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "print_jobs")

    # Keep the watcher loop tight so the test isn't slow.
    Application.put_env(:thermal_print_server, :job_watcher_poll_interval, 50)
    Application.put_env(:thermal_print_server, :job_watcher_max_duration, 500)

    on_exit(fn ->
      Application.delete_env(:thermal_print_server, :job_watcher_poll_interval)
      Application.delete_env(:thermal_print_server, :job_watcher_max_duration)
    end)

    :ok
  end

  describe "watch/3 — unreachable printer" do
    test "marks the job :blocked after the deadline when polling fails" do
      printer = %{uri: "ipp://127.0.0.1:1/printers/fake"}
      job_id = "watcher-unreachable-#{System.unique_integer([:positive])}"

      Store.record(job_id, %{status: :printing, printer: "fake"})

      task = Task.async(fn -> JobWatcher.watch(printer, job_id, 99_999) end)

      assert_receive {:job_updated, ^job_id, %{status: :blocked} = attrs}, 5_000
      assert attrs[:cups_job_state_reasons] == ["watch-timeout"]

      Task.await(task, 2_000)
    end
  end

  describe "map_status/1" do
    test ":completed stays :completed" do
      assert JobWatcher.map_status(:completed) == :completed
    end

    test "intentional cancellation is its own bucket (not :failed)" do
      assert JobWatcher.map_status(:canceled) == :canceled
    end

    test ":aborted is treated as a real failure" do
      assert JobWatcher.map_status(:aborted) == :failed
    end

    test "CUPS' `processing-stopped` maps to :blocked (the stuck bucket)" do
      assert JobWatcher.map_status(:processing_stopped) == :blocked
    end

    test "non-terminal IPP states stay :printing" do
      assert JobWatcher.map_status(:pending) == :printing
      assert JobWatcher.map_status(:pending_held) == :printing
      assert JobWatcher.map_status(:processing) == :printing
    end

    test "unknown values fall back to :printing rather than crashing" do
      assert JobWatcher.map_status(:some_future_state) == :printing
    end
  end

  describe "terminal?/1" do
    test "only the three IPP terminal states are terminal" do
      assert JobWatcher.terminal?(:completed)
      assert JobWatcher.terminal?(:canceled)
      assert JobWatcher.terminal?(:aborted)
      refute JobWatcher.terminal?(:processing)
      refute JobWatcher.terminal?(:processing_stopped)
      refute JobWatcher.terminal?(:pending)
    end
  end

  describe "normalize_reasons/1" do
    test "empty-ish inputs become []" do
      assert JobWatcher.normalize_reasons(nil) == []
      assert JobWatcher.normalize_reasons("") == []
      assert JobWatcher.normalize_reasons("none") == []
    end

    test "single reason wraps into a list" do
      assert JobWatcher.normalize_reasons("job-canceled-by-user") == ["job-canceled-by-user"]
    end

    test "strips \"none\" / empty entries from a list of reasons" do
      assert JobWatcher.normalize_reasons(["none"]) == []
      assert JobWatcher.normalize_reasons(["media-empty", "none"]) == ["media-empty"]
    end
  end
end
