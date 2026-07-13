defmodule ManaChessOnline.GameLobbyMovesTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyMoves, GameRooms, GameRules, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp playing_state(game_id, player_id) do
    game =
      game_id
      |> GameRooms.new_game(settings())
      |> Map.merge(%{
        status: :playing,
        players: %{white: player_id, black: "black-player"},
        first_move_pending: :white
      })

    %{
      global_settings: settings(),
      games: %{game_id => game},
      players: %{player_id => %{game_id: game_id, color: :white}},
      rate_limits: %{}
    }
  end

  test "rejects invalid squares into the game log" do
    game_id = "lobby_move_invalid_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "white-player"
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {state, ^game_id} =
      game_id
      |> playing_state(player_id)
      |> GameLobbyMoves.enqueue_move(player_id, {9, 9}, {4, 4}, 1_000)

    assert hd(state.games[game_id].log) == "Movimiento rechazado: casilla invalida."
  end

  test "rejects empty origin squares into the game log" do
    game_id = "lobby_move_empty_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "white-player"
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {state, ^game_id} =
      game_id
      |> playing_state(player_id)
      |> GameLobbyMoves.enqueue_move(player_id, {4, 4}, {3, 4}, 1_000)

    assert hd(state.games[game_id].log) == "Movimiento rechazado: no hay pieza en origen {4, 4}."
  end

  test "enqueues valid move actions" do
    game_id = "lobby_move_valid_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "white-player"
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {state, ^game_id} =
      game_id
      |> playing_state(player_id)
      |> GameLobbyMoves.enqueue_move(player_id, {6, 4}, {4, 4}, 1_000)

    assert GameRules.at(state.games[game_id].board, 6, 4) == "."
    assert GameRules.at(state.games[game_id].board, 4, 4) == "P"
    assert state.games[game_id].first_move_pending == nil
  end
end
