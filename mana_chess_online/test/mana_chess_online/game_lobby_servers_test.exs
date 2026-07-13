defmodule ManaChessOnline.GameLobbyServersTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameLobbyServers, GameState, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "syncs missing game servers and lists their pids" do
    game_id = "server_sync_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert :ok = GameLobbyServers.sync_game_servers(%{game_id => game})
    assert {:ok, pid} = GameSupervisor.lookup_game(game_id)
    assert pid in GameLobbyServers.game_server_pids(%{game_id => game})
  end

  test "syncing nil and stopping missing servers are harmless" do
    assert :ok = GameLobbyServers.sync_game_server(nil)

    assert :ok =
             GameLobbyServers.stop_game_server(
               "missing_" <> Integer.to_string(System.unique_integer([:positive]))
             )
  end

  test "reads and replaces game state through live servers" do
    game_id = "server_replace_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    replaced = GameLobbyServers.replace_game_state(game)
    assert replaced.id == game_id
    assert GameLobbyServers.game_snapshot(game_id, %{}) == replaced
    assert Map.has_key?(GameLobbyServers.server_backed_games(%{}), game_id)
  end

  test "reads and syncs assigned games" do
    game_id = "server_assignment_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())
    assignment = %{game_id: game_id, color: :white}

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert GameLobbyServers.assigned_game(assignment, %{game_id => game}) == game
    assert GameLobbyServers.assigned_game(nil, %{game_id => game}) == nil

    assert :ok = GameLobbyServers.sync_assignment_game(assignment, %{game_id => game})
    assert {:ok, _pid} = GameSupervisor.lookup_game(game_id)
    assert :ok = GameLobbyServers.sync_assignment_game(nil, %{game_id => game})
  end

  test "enqueues, updates, and ticks through live servers" do
    game_id = "server_actions_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game(game_id, settings())
    action = %{player_id: "player", color: :white, from: {6, 0}, to: {5, 0}}

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    enqueued = GameLobbyServers.enqueue_action(game, action, 1_000)
    assert enqueued.id == game_id
    assert GameLobbyServers.game_snapshot(game_id, %{}) == enqueued

    updated =
      GameLobbyServers.update_state(enqueued, fn game ->
        %{game | log: ["updated" | game.log]}
      end)

    assert hd(updated.log) == "updated"

    ticked = GameLobbyServers.tick_game(updated, 1_250, 250)
    assert ticked.id == game_id
    assert GameLobbyServers.game_snapshot(game_id, %{}) == ticked
  end
end
