defmodule ManaChessOnline.GameLobbyView do
  @moduledoc false

  alias ManaChessOnline.{GameSettings, GameState}

  def player_view(player_id, assignment, public_game, public_lobby) do
    %{
      player_id: player_id,
      game_id: assignment.game_id,
      color: assignment.color,
      game: public_game,
      lobby: public_lobby
    }
  end

  def spectator_view(player_id, game_id, color, public_game, public_lobby) do
    %{
      player_id: player_id,
      game_id: game_id,
      color: color,
      game: public_game,
      lobby: public_lobby
    }
  end

  def public_game(game, now),
    do: GameState.public_game(game, now, GameSettings.default_cooldown_seconds())

  def public_lobby(state, now), do: GameState.public_lobby(state, now)
end
