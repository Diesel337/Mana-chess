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
end
