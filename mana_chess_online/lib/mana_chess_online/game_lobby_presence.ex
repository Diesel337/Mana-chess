defmodule ManaChessOnline.GameLobbyPresence do
  @moduledoc false

  alias ManaChessOnline.{GameLobbyRooms, GameLobbyServers, GamePlayers, GameRooms, RateLimiter}

  @presence_rate_limit {120, 60_000}

  def join(state, player_id, now) do
    case RateLimiter.take_state(state, {:join, player_id}, @presence_rate_limit, now) do
      {:ok, state} -> state
      {:error, :rate_limited, state} -> state
    end
  end

  def watch(state, player_id, game_id, now) do
    case RateLimiter.take_state(state, {:watch, player_id}, @presence_rate_limit, now) do
      {:ok, state} -> GameLobbyRooms.ensure_private_game(state, game_id)
      {:error, :rate_limited, state} -> state
    end
  end

  def leave(state, player_id) do
    previous_assignment = GamePlayers.assignment(state, player_id)
    previous_game = GameLobbyServers.assigned_game(previous_assignment, state.games)
    state = GameLobbyRooms.remove_player(state, player_id)

    GameLobbyServers.sync_assignment_game(previous_assignment, state.games)

    {state, GameRooms.public_lobby_game?(previous_game)}
  end
end
