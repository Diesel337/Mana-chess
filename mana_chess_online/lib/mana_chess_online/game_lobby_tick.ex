defmodule ManaChessOnline.GameLobbyTick do
  @moduledoc false

  alias ManaChessOnline.{GameBroadcast, GameLobbyServers, RateLimiter}

  def run(state, now, tick_ms, rate_limit_retention_ms, public_game, public_lobby)
      when is_function(public_game, 2) and is_function(public_lobby, 2) do
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
