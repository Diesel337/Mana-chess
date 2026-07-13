defmodule ManaChessOnline.GameBroadcast do
  @moduledoc false

  alias ManaChessOnline.{GameLobbyServers, GameLobbyView}

  def game_update(topic, game, now) do
    game_payload_update(topic, GameLobbyView.public_game(game, now))
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

  def lobby_payload_update(topic, public_lobby) do
    Phoenix.PubSub.broadcast(
      ManaChessOnline.PubSub,
      topic,
      {:lobby_update, public_lobby}
    )
  end

  def live_lobby(state, now) do
    GameLobbyView.public_lobby(
      %{state | games: GameLobbyServers.server_backed_games(state.games)},
      now
    )
  end

  def game_update_needed?(previous_public_game, next_public_game, next_game) do
    previous_public_game != next_public_game or countdown_visible?(next_game) or
      cooldowns_visible?(next_game)
  end

  def lobby_update_needed?(previous_public_lobby, next_public_lobby, next_games) do
    previous_public_lobby != next_public_lobby or
      Enum.any?(next_games, fn {_game_id, game} -> countdown_visible?(game) end)
  end

  def countdown_visible?(%{status: {:starting, _starts_at}}), do: true
  def countdown_visible?(_game), do: false

  def cooldowns_visible?(%{status: :playing, cooldowns: cooldowns}), do: map_size(cooldowns) > 0
  def cooldowns_visible?(_game), do: false
end
