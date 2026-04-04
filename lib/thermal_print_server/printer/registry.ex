defmodule ThermalPrintServer.Printer.Registry do
  @moduledoc """
  GenServer that maps printer names to IPP URIs.
  Loaded from application config at startup, with optional
  CUPS discovery when `cups_uri` is configured.
  """

  use GenServer

  require Logger

  @refresh_interval :timer.minutes(5)

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

  @spec refresh() :: :ok
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @spec refresh_sync() :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh_sync do
    GenServer.call(__MODULE__, :refresh_sync)
  end

  @impl true
  def init(_opts) do
    printers = load_printers()
    schedule_refresh()
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

  def handle_call(:refresh_sync, _from, printers) do
    case discover_cups_printers() do
      {:ok, cups_printers} ->
        config_printers = Application.get_env(:thermal_print_server, :printers, %{})
        merged = Map.merge(cups_printers, config_printers)
        broadcast_update(merged)
        {:reply, {:ok, map_size(merged)}, merged}

      {:error, reason} ->
        {:reply, {:error, reason}, printers}
    end
  end

  @impl true
  def handle_cast(:refresh, _printers) do
    printers = load_printers()
    broadcast_update(printers)
    {:noreply, printers}
  end

  @impl true
  def handle_info(:scheduled_refresh, _printers) do
    printers = load_printers()
    schedule_refresh()
    {:noreply, printers}
  end

  defp schedule_refresh do
    Process.send_after(self(), :scheduled_refresh, @refresh_interval)
  end

  defp broadcast_update(printers) do
    list = Enum.map(printers, fn {name, config} -> Map.put(config, :name, name) end)

    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "printers",
      {:printers_updated, list}
    )
  end

  defp load_printers do
    config_printers = Application.get_env(:thermal_print_server, :printers, %{})

    cups_printers =
      case discover_cups_printers() do
        {:ok, printers} -> printers
        {:error, _reason} -> %{}
      end

    merged = Map.merge(cups_printers, config_printers)

    Logger.info(
      "Printer registry loaded: #{map_size(merged)} printer(s) " <>
        "(#{map_size(config_printers)} configured, #{map_size(cups_printers)} from CUPS)"
    )

    merged
  end

  defp discover_cups_printers do
    case Application.get_env(:thermal_print_server, :cups_uri) do
      nil ->
        {:ok, %{}}

      cups_uri ->
        ThermalPrintServer.Printer.CupsDiscovery.discover(cups_uri)
    end
  end
end
