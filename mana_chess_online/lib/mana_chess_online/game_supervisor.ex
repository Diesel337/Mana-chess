defmodule ManaChessOnline.GameSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ManaChessOnline.{GameRegistry, GameServer}

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_game(game, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:game, game)
      |> Keyword.put_new(:id, {GameServer, game.id})
      |> Keyword.put_new(:name, GameRegistry.via(game.id))

    DynamicSupervisor.start_child(__MODULE__, {GameServer, opts})
  end

  def lookup_game(game_id), do: GameRegistry.lookup(game_id)
  def game_pid(game_id), do: GameRegistry.whereis(game_id)

  def child_count, do: DynamicSupervisor.count_children(__MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
