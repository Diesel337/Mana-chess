defmodule ManaChessOnline.GameLobbyRoomsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyRooms, GameLobbyServers, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(game) do
    %{global_settings: settings(), games: %{game.id => game}, players: %{}, rate_limits: %{}}
  end

  test "assigns players to open seats and refreshes room status" do
    game_id = "lobby_room_assign_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      game
      |> state()
      |> GameLobbyRooms.assign_player("white-player", game_id, :white)
      |> GameLobbyRooms.assign_player("black-player", game_id, :black)

    assert state.players["white-player"] == %{game_id: game_id, color: :white}
    assert state.players["black-player"] == %{game_id: game_id, color: :black}
    assert state.games[game_id].players.white == "white-player"
    assert state.games[game_id].players.black == "black-player"
    assert state.games[game_id].status == :ready
  end

  test "removes players from seats" do
    game_id = "lobby_room_remove_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      game
      |> state()
      |> GameLobbyRooms.assign_player("white-player", game_id, :white)
      |> GameLobbyRooms.remove_player("white-player")

    refute Map.has_key?(state.players, "white-player")
    assert state.games[game_id].players.white == nil
    assert state.games[game_id].status == :waiting
  end

  test "creates private games on demand" do
    game_id = "private_test_" <> Integer.to_string(System.unique_integer([:positive]))
    state = %{global_settings: settings(), games: %{}, players: %{}, rate_limits: %{}}
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = GameLobbyRooms.ensure_private_game(state, game_id)

    assert state.games[game_id].private?
    assert GameLobbyServers.assigned_game(%{game_id: game_id}, state.games).id == game_id
  end
end
