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

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

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

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

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

  test "start_or_lookup_game does not replace an existing live game" do
    game_id = "start_lookup_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.start_game(game, id: {__MODULE__, game_id})

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    live_game = GameServer.update(pid, &%{&1 | log: ["Estado vivo." | &1.log]})
    stale_game = %{game | log: ["Mirror viejo." | game.log]}

    assert {:ok, ^pid} = GameSupervisor.start_or_lookup_game(stale_game)
    assert GameServer.snapshot(pid).log == live_game.log
  end

  test "lists live game snapshots from supervised servers" do
    game_id = "snapshot_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    {:ok, pid} = GameSupervisor.start_game(game, id: {__MODULE__, game_id})

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    GameServer.update(pid, fn game ->
      %{game | log: ["Snapshot vivo." | game.log]}
    end)

    snapshots = GameSupervisor.game_snapshots()

    assert snapshots[game_id].id == game_id
    assert "Snapshot vivo." in snapshots[game_id].log
  end
end
