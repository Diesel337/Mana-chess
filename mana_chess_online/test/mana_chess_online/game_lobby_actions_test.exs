defmodule ManaChessOnline.GameLobbyActionsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyActions, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(game, players) do
    %{global_settings: settings(), games: %{game.id => game}, players: players, rate_limits: %{}}
  end

  defp promotion_board do
    [
      ["P", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]
  end

  test "records reset requests until every seated player agrees" do
    game_id = "lobby_action_reset_" <> Integer.to_string(System.unique_integer([:positive]))
    white = "white-player"
    black = "black-player"

    game =
      GameRooms.new_game(game_id, settings())
      |> Map.merge(%{players: %{white: white, black: black}, status: :playing})

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      game
      |> state(%{
        white => %{game_id: game_id, color: :white},
        black => %{game_id: game_id, color: :black}
      })
      |> GameLobbyActions.reset(white, 1_000)

    assert MapSet.member?(state.games[game_id].reset_requests, white)
    assert hd(state.games[game_id].log) == "Blancas pidio reiniciar la partida."
  end

  test "starts countdowns and records ready players" do
    game_id = "lobby_action_start_" <> Integer.to_string(System.unique_integer([:positive]))
    white = "white-player"
    black = "black-player"

    game =
      GameRooms.new_game(game_id, settings())
      |> Map.merge(%{players: %{white: white, black: black}, status: :ready})

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    started_state =
      game
      |> state(%{
        white => %{game_id: game_id, color: :white},
        black => %{game_id: game_id, color: :black}
      })
      |> GameLobbyActions.start_game(white, 6_000)

    assert started_state.games[game_id].status == {:starting, 6_000}
    assert MapSet.member?(started_state.games[game_id].start_requests, white)
    assert hd(started_state.games[game_id].log) == "Cuenta regresiva iniciada."

    ready_state = GameLobbyActions.ready_to_start(started_state, black)

    assert ready_state.games[game_id].status == :playing
  end

  test "promotes pending pawns" do
    game_id = "lobby_action_promote_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "white-player"

    game =
      GameRooms.new_game(game_id, settings())
      |> Map.merge(%{
        board: promotion_board(),
        players: %{white: player_id, black: "black-player"},
        status: :playing,
        promotion_pending: %{player_id: player_id, color: :white, at: {0, 0}}
      })

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      game
      |> state(%{player_id => %{game_id: game_id, color: :white}})
      |> GameLobbyActions.promote(player_id, "R")

    assert state.games[game_id].promotion_pending == nil
    assert state.games[game_id].board |> Enum.at(0) |> Enum.at(0) == "R"
    assert hd(state.games[game_id].log) == "Blancas promociono peon."
  end
end
