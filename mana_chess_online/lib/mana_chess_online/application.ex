defmodule ManaChessOnline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ManaChessOnlineWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:mana_chess_online, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ManaChessOnline.PubSub},
      ManaChessOnline.GameSupervisor,
      ManaChessOnline.GameLobby,
      # Start a worker by calling: ManaChessOnline.Worker.start_link(arg)
      # {ManaChessOnline.Worker, arg},
      # Start to serve requests, typically the last entry
      ManaChessOnlineWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ManaChessOnline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ManaChessOnlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
