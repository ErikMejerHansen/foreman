defmodule Foreman.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ForemanWeb.Telemetry,
      Foreman.Repo,
      {DNSCluster, query: Application.get_env(:foreman, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Foreman.PubSub},
      {Registry, keys: :unique, name: Foreman.Agent.Registry},
      Foreman.Agent.Supervisor,
      # Start to serve requests, typically the last entry
      ForemanWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Foreman.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ForemanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
