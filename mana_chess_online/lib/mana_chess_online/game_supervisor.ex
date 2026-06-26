defmodule ManaChessOnline.GameSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ManaChessOnline.GameServer

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_game(game, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:game, game)
      |> Keyword.put_new(:id, {GameServer, game.id})

    DynamicSupervisor.start_child(__MODULE__, {GameServer, opts})
  end

  def child_count, do: DynamicSupervisor.count_children(__MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
