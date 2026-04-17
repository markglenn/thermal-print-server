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
end
