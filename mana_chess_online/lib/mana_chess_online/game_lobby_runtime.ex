defmodule ManaChessOnline.GameLobbyRuntime do
  @moduledoc false

  alias ManaChessOnline.{GameBroadcast, GameLobbyServers, GameLobbyView}

  def now_ms, do: System.monotonic_time(:millisecond)

  def sync_game_servers(state), do: GameLobbyServers.sync_game_servers(state.games)

  def game_server_pids(state) do
    state
    |> server_backed_games()
    |> GameLobbyServers.game_server_pids()
  end

  def game_snapshot(game_id, state) when is_binary(game_id) do
    GameLobbyServers.game_snapshot(game_id, state.games)
  end

  def game_snapshot(_game_id, _state), do: nil

  def server_backed_games(state), do: GameLobbyServers.server_backed_games(state.games)

  def public_game(game), do: public_game_at(game, now_ms())

  def public_game_at(game, now), do: GameLobbyView.public_game(game, now)

  def public_game_snapshot(game_id, state) do
    game_id
    |> game_snapshot(state)
    |> public_game()
  end

  def public_lobby_at(state, now), do: GameLobbyView.public_lobby(state, now)

  def public_live_lobby(state), do: GameBroadcast.live_lobby(state, now_ms())

  def player_view(state, player_id) do
    GameLobbyView.current_player_view(
      state,
      player_id,
      &public_game_snapshot(&1, state),
      public_live_lobby(state)
    )
  end

  def spectator_view(state, player_id, game_id) do
    GameLobbyView.current_spectator_view(
      state,
      player_id,
      game_id,
      &public_game_snapshot(&1, state),
      public_live_lobby(state)
    )
  end

  def broadcast_game_snapshot(game_id, state) do
    GameBroadcast.game_payload_update_for(game_id, public_game_snapshot(game_id, state))
  end

  def broadcast_game_update(game, now), do: GameBroadcast.game_update_for(game, now)

  def broadcast_lobby(state) do
    sync_game_servers(state)
    GameBroadcast.lobby_update(state, now_ms())
  end

  def broadcast_lobby_payload(state, now) do
    GameBroadcast.lobby_payload_update(GameBroadcast.lobby_topic(), public_lobby_at(state, now))
  end

  def game_topic(game_id), do: GameBroadcast.game_topic(game_id)
  def lobby_topic, do: GameBroadcast.lobby_topic()
end
