defmodule ManaChessOnline.GameSupervisorTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameRegistry, GameServer, GameState, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "starts a game server under the dynamic supervisor" do
    game_id = "supervised_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.start_game(game, id: {__MODULE__, game_id})

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    assert GameServer.snapshot(pid).id == game_id
    assert {:ok, ^pid} = GameSupervisor.lookup_game(game_id)
    assert GameSupervisor.game_pid(game_id) == pid
    assert GameRegistry.registered?(game_id)
    assert GameSupervisor.child_count().active >= 1
  end

  test "rejects duplicate game ids through the registry" do
    game_id = "duplicate_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.start_game(game, id: {__MODULE__, game_id})

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    assert {:error, {:already_started, ^pid}} =
             GameSupervisor.start_game(game, id: {__MODULE__, game_id, :again})
  end

  test "upserts existing games and stops them by id" do
    game_id = "upsert_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.upsert_game(game)

    updated = %{game | log: ["Mirror actualizado." | game.log]}
    assert {:ok, ^pid} = GameSupervisor.upsert_game(updated)
    assert GameServer.snapshot(pid).log == updated.log

    assert :ok = GameSupervisor.stop_game(game_id)
    assert GameSupervisor.lookup_game(game_id) == :error
  end
end
