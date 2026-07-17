defmodule ManaChessOnline.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    operations = Application.get_env(:mana_chess_online, :operations, [])

    children =
      [
        {ManaChessOnline.Operations.EventLog, operations},
        {Task.Supervisor, name: ManaChessOnline.Operations.AlertTaskSupervisor},
        {ManaChessOnline.Operations.AlertDispatcher, operations},
        {ManaChessOnline.Operations.Telemetry, operations},
        ManaChessOnlineWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:mana_chess_online, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: ManaChessOnline.PubSub}
      ] ++
        ManaChessOnline.Persistence.children() ++
        [
          ManaChessOnline.GameRegistry,
          ManaChessOnline.GameSupervisor,
          ManaChessOnline.GameLobby,
          ManaChessOnlineWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ManaChessOnline.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, _pid} = started ->
        ManaChessOnline.Operations.EventLog.report(:info, "application_started", %{
          component: "application"
        })

        started

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ManaChessOnlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
