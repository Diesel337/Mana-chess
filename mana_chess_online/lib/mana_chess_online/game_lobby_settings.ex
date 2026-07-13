defmodule ManaChessOnline.GameLobbySettings do
  @moduledoc false

  alias ManaChessOnline.{GameLobbyServers, GamePlayers, GameRooms, GameSettings}

  def update_global_settings(state, params) do
    settings = GameSettings.sanitize(params, state.global_settings)
    GameSettings.persist_global(settings)

    games =
      state.games
      |> GameLobbyServers.server_backed_games()
      |> Map.new(fn {game_id, game} ->
        if GameRooms.empty_waiting_game?(game) do
          {game_id, apply_global_settings_to_waiting_game(game, settings)}
        else
          {game_id, game}
        end
      end)

    {%{state | global_settings: settings, games: games}, settings}
  end

  def apply_global_settings_to_practice(state, player_id) do
    with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
         %{practice?: true} = game <- game_snapshot(game_id, state) do
      game =
        update_game_state(game, fn game ->
          %{
            game
            | settings: state.global_settings,
              elixir: GameSettings.clamp_elixir(game.elixir, state.global_settings),
              cooldowns: %{},
              log: ["Configuracion admin aplicada a la practica." | game.log]
          }
        end)

      {:ok, put_in(state.games[game_id], game)}
    else
      _ -> {:error, :no_practice, state}
    end
  end

  def update_player_settings(state, player_id, params) do
    with %{game_id: game_id, color: color} when color in [:white, :practice] <-
           GamePlayers.assignment(state, player_id),
         game when game.practice? or game.status in [:waiting, :ready] <-
           game_snapshot(game_id, state) do
      settings = GameSettings.sanitize(params, game.settings)

      game =
        update_game_state(game, fn game ->
          %{
            game
            | settings: settings,
              elixir: GameSettings.full_elixir(settings),
              cooldowns: %{},
              log: ["Blancas ajustaron la configuracion." | game.log]
          }
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  defp apply_global_settings_to_waiting_game(game, settings) do
    update_game_state(game, fn game ->
      if GameRooms.empty_waiting_game?(game) do
        %{game | settings: settings, elixir: GameSettings.full_elixir(settings), cooldowns: %{}}
      else
        game
      end
    end)
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)
end
