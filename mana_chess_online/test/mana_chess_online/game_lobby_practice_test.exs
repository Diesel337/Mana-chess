defmodule ManaChessOnline.GameLobbyPracticeTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyPractice, GameLobbyServers, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(games \\ %{}, players \\ %{}) do
    %{global_settings: settings(), games: games, players: players, rate_limits: %{}}
  end

  test "starts practice games and assigns the player" do
    player_id = "practice-player"
    game_id = GameRooms.practice_game_id(player_id)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = GameLobbyPractice.start_practice(state(), player_id, 1_000)

    assert state.players[player_id] == %{game_id: game_id, color: :practice}
    assert state.games[game_id].practice?
    assert state.games[game_id].bot_enabled?
    assert state.games[game_id].bot_color == :black
  end

  test "toggles practice bots" do
    player_id = "practice-bot-player"
    game_id = GameRooms.practice_game_id(player_id)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      state()
      |> GameLobbyPractice.start_practice(player_id, 1_000)
      |> GameLobbyPractice.toggle_bot(player_id, 2_000)

    refute state.games[game_id].bot_enabled?
    assert state.games[game_id].bot_ready_at == nil
    assert hd(state.games[game_id].log) == "Bot desactivado."
  end

  test "toggles practice sides and preserves chat" do
    player_id = "practice-side-player"
    game_id = GameRooms.practice_game_id(player_id)
    chat = [%{text: "hola"}]
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = GameLobbyPractice.start_practice(state(), player_id, 1_000)
    game = GameLobbyServers.update_state(state.games[game_id], &Map.put(&1, :chat, chat))
    state = %{state | games: Map.put(state.games, game_id, game)}
    state = GameLobbyPractice.toggle_side(state, player_id, 2_000)

    assert state.games[game_id].bot_color == :white
    assert state.games[game_id].chat == chat

    assert hd(state.games[game_id].log) ==
             "Ahora juegas Negras; BOT controla Blancas."
  end
end
