defmodule ManaChessOnline.GameLobbyTick do
  @moduledoc false

  alias ManaChessOnline.{
    GameBroadcast,
    GameDirectory,
    GameLobbyServers,
    GameRuntimeConfig,
    RateLimiter
  }

  def run(state, now, tick_ms, rate_limit_retention_ms, public_game, public_lobby)
      when is_function(public_game, 2) and is_function(public_lobby, 2) do
    if GameRuntimeConfig.auto_tick?() do
      run_autonomous(state, now, rate_limit_retention_ms, public_lobby)
    else
      run_batch(
        state,
        now,
        tick_ms,
        rate_limit_retention_ms,
        public_game,
        public_lobby
      )
    end
  end

  defp run_autonomous(state, now, rate_limit_retention_ms, public_lobby) do
    previous_public_lobby = public_lobby.(state, now)
    games = GameLobbyServers.refresh_public_games(state.games)

    next_state = %{
      state
      | games: games,
        rate_limits: RateLimiter.prune(state.rate_limits, now, rate_limit_retention_ms)
    }

    next_public_lobby = public_lobby.(next_state, now)
    lobby_games = next_state.games |> GameDirectory.lobby_games() |> Map.new()

    lobby_update? =
      GameBroadcast.lobby_update_needed?(
        previous_public_lobby,
        next_public_lobby,
        lobby_games
      )

    {next_state, [], lobby_update?}
  end

  defp run_batch(state, now, tick_ms, rate_limit_retention_ms, public_game, public_lobby) do
    live_games = GameLobbyServers.server_backed_games(state.games)

    {games, changed_game_ids} =
      Enum.reduce(live_games, {%{}, []}, fn {game_id, game}, {games, changed_game_ids} ->
        ticked_game = GameLobbyServers.tick_game(game, now, tick_ms)

        changed_game_ids =
          if GameBroadcast.game_update_needed?(game, ticked_game, now, public_game) do
            [game_id | changed_game_ids]
          else
            changed_game_ids
          end

        {Map.put(games, game_id, ticked_game), changed_game_ids}
      end)

    next_state = %{
      state
      | games: games,
        rate_limits: RateLimiter.prune(state.rate_limits, now, rate_limit_retention_ms)
    }

    {next_state, Enum.reverse(changed_game_ids),
     GameBroadcast.lobby_update_needed?(state, next_state, now, public_lobby)}
  end
end
