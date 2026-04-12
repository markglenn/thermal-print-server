defmodule ThermalPrintServerWeb.HealthController do
  use ThermalPrintServerWeb, :controller

  def index(conn, _params) do
    checks = %{
      store: process_alive?(ThermalPrintServer.Jobs.Store),
      registry: process_alive?(ThermalPrintServer.Printer.Registry)
    }

    healthy? = Enum.all?(checks, fn {_k, v} -> v end)

    conn
    |> put_status(if healthy?, do: 200, else: 503)
    |> json(%{status: if(healthy?, do: "ok", else: "degraded"), checks: checks})
  end

  defp process_alive?(name) do
    case Process.whereis(name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end
end
