defmodule ManaChessOnline.GameBroadcast do
  @moduledoc false

  alias ManaChessOnline.{GameDirectory, GameLobbyServers, GameLobbyView}

  def game_topic(game_id), do: "game:" <> game_id
  def lobby_topic, do: "lobby"

  def game_payload_update_for(game_id, public_game) do
    game_payload_update(game_topic(game_id), public_game)
  end

  def game_update(topic, game, now) do
    game_payload_update(topic, GameLobbyView.public_game(game, now))
  end

  def game_update_for(game, now) do
    game_update(game_topic(game.id), game, now)
  end

  def game_payload_update(topic, public_game) do
    Phoenix.PubSub.broadcast(
      ManaChessOnline.PubSub,
      topic,
      {:game_update, public_game}
    )
  end

  def lobby_update(topic, state, now) do
    lobby_payload_update(topic, live_lobby(state, now))
  end

  def lobby_update(state, now) do
    lobby_update(lobby_topic(), state, now)
  end

  def lobby_payload_update(topic, public_lobby) do
    Phoenix.PubSub.broadcast(
      ManaChessOnline.PubSub,
      topic,
      {:lobby_update, public_lobby}
    )
  end

  def live_lobby(state, now) do
    GameLobbyView.public_lobby(
      %{state | games: GameLobbyServers.refresh_public_games(state.games)},
      now
    )
  end

  def game_update_needed?(previous_public_game, next_public_game, next_game) do
    previous_public_game != next_public_game or countdown_visible?(next_game) or
      cooldowns_visible?(next_game)
  end

  def game_update_needed?(previous_game, next_game, now, public_game)
      when is_function(public_game, 2) do
    game_update_needed?(
      public_game.(previous_game, now),
      public_game.(next_game, now),
      next_game
    )
  end

  def lobby_update_needed?(previous_public_lobby, next_public_lobby, next_games) do
    previous_public_lobby != next_public_lobby or
      Enum.any?(next_games, fn {_game_id, game} ->
        GameDirectory.lobby_game?(game) and countdown_visible?(game)
      end)
  end

  def lobby_update_needed?(previous_state, next_state, now, public_lobby)
      when is_function(public_lobby, 2) do
    lobby_update_needed?(
      public_lobby.(previous_state, now),
      public_lobby.(next_state, now),
      next_state.games
    )
  end

  def countdown_visible?(%{status: {:starting, _starts_at}}), do: true
  def countdown_visible?(_game), do: false

  def cooldowns_visible?(%{status: :playing, cooldowns: cooldowns}), do: map_size(cooldowns) > 0
  def cooldowns_visible?(_game), do: false
end
