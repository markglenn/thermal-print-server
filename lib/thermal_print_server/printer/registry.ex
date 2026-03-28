defmodule ThermalPrintServer.Printer.Registry do
  @moduledoc """
  GenServer that maps printer names to IPP URIs.
  Loaded from application config at startup.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec lookup(String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup(printer_name) do
    GenServer.call(__MODULE__, {:lookup, printer_name})
  end

  @spec list_all() :: [map()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @impl true
  def init(_opts) do
    printers = Application.get_env(:thermal_print_server, :printers, %{})
    {:ok, printers}
  end

  @impl true
  def handle_call({:lookup, name}, _from, printers) do
    case Map.fetch(printers, name) do
      {:ok, config} -> {:reply, {:ok, Map.put(config, :name, name)}, printers}
      :error -> {:reply, {:error, :not_found}, printers}
    end
  end

  def handle_call(:list_all, _from, printers) do
    list =
      Enum.map(printers, fn {name, config} ->
        Map.put(config, :name, name)
      end)

    {:reply, list, printers}
  end
end
