defmodule ThermalPrintServerWeb.HealthController do
  use ThermalPrintServerWeb, :controller

  alias ThermalPrintServer.Broadway.PrintPipeline
  alias ThermalPrintServer.Events.Publisher
  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.Registry

  def index(conn, _params) do
    checks =
      %{
        store: process_alive?(Store),
        registry: process_alive?(Registry)
      }
      |> maybe_check(:broadway, :sqs_queue_url, &broadway_running?/0)
      |> maybe_check(:publisher, :site_id, fn -> process_alive?(Publisher) end)

    healthy? = Enum.all?(checks, fn {_k, v} -> v end)

    conn
    |> put_status(if healthy?, do: 200, else: 503)
    |> json(%{status: if(healthy?, do: "ok", else: "degraded"), checks: checks})
  end

  defp maybe_check(checks, key, config_key, fun) do
    if Application.get_env(:thermal_print_server, config_key) do
      Map.put(checks, key, fun.())
    else
      checks
    end
  end

  defp broadway_running? do
    PrintPipeline in Broadway.all_running()
  end

  defp process_alive?(name) do
    case Process.whereis(name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
