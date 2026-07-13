defmodule ManaChessOnline.GameLobbyChatTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyChat, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(game, player_id \\ "white-player") do
    game = %{game | players: %{white: player_id, black: nil}}

    %{
      global_settings: settings(),
      games: %{game.id => game},
      players: %{player_id => %{game_id: game.id, color: :white}},
      rate_limits: %{}
    }
  end

  test "sanitizes and appends chat entries" do
    game_id = "lobby_chat_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert {:ok, state} =
             game
             |> state()
             |> GameLobbyChat.send_chat(
               "white-player",
               game_id,
               "  hola mesa  ",
               {30, 10_000},
               1_000,
               123
             )

    assert [%{player_id: "white-player", role: "Blancas", sent_at: 123, text: "hola mesa"}] =
             state.games[game_id].chat
  end

  test "returns errors for invalid messages and missing games" do
    game_id = "lobby_chat_errors_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = state(game)

    assert {:error, :empty, ^state} =
             GameLobbyChat.send_chat(
               state,
               "white-player",
               game_id,
               "   ",
               {30, 10_000},
               1_000,
               123
             )

    assert {:error, :no_game, ^state} =
             GameLobbyChat.send_chat(
               state,
               "white-player",
               "missing",
               "hola",
               {30, 10_000},
               1_000,
               123
             )
  end

  test "rate limits chat by game and player" do
    game_id = "lobby_chat_rate_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert {:ok, state} =
             game
             |> state()
             |> GameLobbyChat.send_chat("white-player", game_id, "uno", {1, 10_000}, 1_000, 123)

    assert {:error, :rate_limited, _state} =
             GameLobbyChat.send_chat(
               state,
               "white-player",
               game_id,
               "dos",
               {1, 10_000},
               1_001,
               124
             )
  end
end
