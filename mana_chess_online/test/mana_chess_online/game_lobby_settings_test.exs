defmodule ManaChessOnline.GameLobbySettingsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbySettings, GameRooms, GameSupervisor, GameSettings}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(games, players \\ %{}) do
    %{global_settings: settings(), games: games, players: players, rate_limits: %{}}
  end

  test "updates global settings on empty waiting games" do
    game_id = "lobby_settings_global_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {state, updated_settings} =
      game
      |> then(&state(%{game_id => &1}))
      |> GameLobbySettings.update_global_settings(%{
        "max_elixir" => "12",
        "initial_elixir" => "7"
      })

    assert updated_settings.max_elixir == 12.0
    assert updated_settings.initial_elixir == 7.0
    assert state.global_settings == updated_settings
    assert state.games[game_id].settings == updated_settings
    assert state.games[game_id].elixir.white == 7.0
  end

  test "applies global settings to practice games" do
    player_id = "practice-player"
    game_id = "lobby_settings_practice_" <> Integer.to_string(System.unique_integer([:positive]))
    global_settings = %{settings() | initial_elixir: 8.0, max_elixir: 12.0}

    game =
      GameRooms.practice_game_for_player(game_id, player_id, settings(), 1_000)
      |> Map.put(:elixir, %{white: 99.0, black: 99.0})

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = %{
      state(%{game_id => game}, %{player_id => %{game_id: game_id, color: :practice}})
      | global_settings: global_settings
    }

    assert {:ok, state} = GameLobbySettings.apply_global_settings_to_practice(state, player_id)

    assert state.games[game_id].settings == global_settings

    assert state.games[game_id].elixir ==
             GameSettings.clamp_elixir(%{white: 99.0, black: 99.0}, global_settings)

    assert hd(state.games[game_id].log) == "Configuracion admin aplicada a la practica."
  end

  test "updates player-controlled room settings" do
    player_id = "white-player"
    game_id = "lobby_settings_player_" <> Integer.to_string(System.unique_integer([:positive]))
    game = %{GameRooms.new_game(game_id, settings()) | players: %{white: player_id, black: nil}}
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      game
      |> then(&state(%{game_id => &1}, %{player_id => %{game_id: game_id, color: :white}}))
      |> GameLobbySettings.update_player_settings(player_id, %{"initial_elixir" => "6"})

    assert state.games[game_id].settings.initial_elixir == 6.0
    assert state.games[game_id].elixir.white == 6.0
    assert hd(state.games[game_id].log) == "Blancas ajustaron la configuracion."
  end
end
