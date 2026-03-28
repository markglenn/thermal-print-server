defmodule ThermalPrintServer.Jobs.Store do
  @moduledoc """
  ETS-backed GenServer for tracking recent print jobs.
  Used by the LiveView dashboard for real-time monitoring.
  Not persistent — cleared on restart.
  """

  use GenServer

  @table __MODULE__
  @max_jobs 500

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec record(String.t(), map()) :: :ok
  def record(job_id, attrs) do
    GenServer.cast(__MODULE__, {:record, job_id, attrs})
  end

  @spec recent(pos_integer()) :: [map()]
  def recent(limit \\ 100) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_id, job} -> job.timestamp end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {_id, job} -> job end)
  end

  @spec get(String.t()) :: map() | nil
  def get(job_id) do
    case :ets.lookup(@table, job_id) do
      [{_id, job}] -> job
      [] -> nil
    end
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:record, job_id, attrs}, state) do
    existing =
      case :ets.lookup(@table, job_id) do
        [{_id, job}] -> job
        [] -> %{job_id: job_id, timestamp: DateTime.utc_now()}
      end

    updated = Map.merge(existing, attrs) |> Map.put(:job_id, job_id)
    :ets.insert(@table, {job_id, updated})

    maybe_prune()

    {:noreply, state}
  end

  @spec maybe_prune() :: :ok
  defp maybe_prune do
    size = :ets.info(@table, :size)

    if size > @max_jobs do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_id, job} -> job.timestamp end, {:asc, DateTime})
      |> Enum.take(size - @max_jobs)
      |> Enum.each(fn {id, _job} -> :ets.delete(@table, id) end)
    end
  end
end
