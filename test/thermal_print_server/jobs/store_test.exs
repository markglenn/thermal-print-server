defmodule ThermalPrintServer.Jobs.StoreTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Jobs.Store

  setup do
    :ets.delete_all_objects(Store)
    :ok
  end

  test "records and retrieves a job" do
    Store.record("job-1", %{status: :printing, printer: "test"})
    Process.sleep(20)

    job = Store.get("job-1")
    assert job.job_id == "job-1"
    assert job.status == :printing
    assert job.printer == "test"
    assert %DateTime{} = job.timestamp
  end

  test "merges attributes on subsequent records" do
    Store.record("job-1", %{status: :printing, printer: "test"})
    Process.sleep(20)

    Store.record("job-1", %{status: :completed, preview_data: "abc"})
    Process.sleep(20)

    job = Store.get("job-1")
    assert job.status == :completed
    assert job.printer == "test"
    assert job.preview_data == "abc"
  end

  test "returns nil for unknown job" do
    assert Store.get("nonexistent") == nil
  end

  test "recent returns jobs ordered by timestamp descending" do
    for i <- 1..5 do
      Store.record("job-#{i}", %{status: :completed})
      Process.sleep(10)
    end

    Process.sleep(20)
    jobs = Store.recent(3)
    assert length(jobs) == 3
    assert hd(jobs).job_id == "job-5"
  end

  test "recent respects limit" do
    for i <- 1..10 do
      Store.record("job-#{i}", %{status: :completed})
    end

    Process.sleep(20)
    assert length(Store.recent(5)) == 5
  end
end
