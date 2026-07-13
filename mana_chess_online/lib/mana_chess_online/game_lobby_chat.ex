defmodule ManaChessOnline.GameLobbyChat do
  @moduledoc false

  alias ManaChessOnline.{GameChat, GameLobbyServers, RateLimiter}

  def send_chat(state, player_id, game_id, message, rate_limits, now_ms, sent_at) do
    with {:ok, text} <- GameChat.sanitize_message(message),
         {:ok, state} <-
           RateLimiter.take_state(state, {:chat, game_id, player_id}, rate_limits, now_ms),
         %{id: ^game_id} = game <- game_snapshot(game_id, state) do
      entry = %{
        id: System.unique_integer([:positive, :monotonic]),
        player_id: player_id,
        name: GameChat.player_name(player_id),
        role: GameChat.role(game, player_id),
        sent_at: sent_at,
        text: text
      }

      game = update_game_state(game, &GameChat.put_entry(&1, entry))

      {:ok, put_in(state.games[game_id], game)}
    else
      {:error, :rate_limited, state} -> {:error, :rate_limited, state}
      {:error, reason} -> {:error, reason, state}
      _ -> {:error, :no_game, state}
    end
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)
end
