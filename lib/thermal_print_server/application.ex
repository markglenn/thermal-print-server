defmodule ThermalPrintServer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        ThermalPrintServerWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:thermal_print_server, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ThermalPrintServer.PubSub},
        ThermalPrintServer.Jobs.Store,
        ThermalPrintServer.Printer.Registry,
        ThermalPrintServerWeb.Endpoint
      ] ++ broadway_children() ++ publisher_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ThermalPrintServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @spec broadway_children() :: [module()]
  defp broadway_children do
    if Application.get_env(:thermal_print_server, :sqs_queue_url) do
      [ThermalPrintServer.Broadway.PrintPipeline]
    else
      []
    end
  end

  defp publisher_children do
    if Application.get_env(:thermal_print_server, :response_topic_arn) do
      [ThermalPrintServer.Events.Publisher]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    ThermalPrintServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
