defmodule ManaChessOnline.GameLobbyView do
  @moduledoc false

  alias ManaChessOnline.{GamePlayers, GameSettings, GameState}

  def current_player_view(state, player_id, public_game_snapshot, public_lobby)
      when is_function(public_game_snapshot, 1) do
    assignment = GamePlayers.assignment_or_empty(state, player_id)

    player_view(
      player_id,
      assignment,
      public_game_snapshot.(assignment.game_id),
      public_lobby
    )
  end

  def current_spectator_view(state, player_id, game_id, public_game_snapshot, public_lobby)
      when is_function(public_game_snapshot, 1) do
    assignment =
      case GamePlayers.assignment(state, player_id) do
        %{game_id: ^game_id} = assignment -> assignment
        _ -> %{game_id: game_id, color: nil}
      end

    spectator_view(
      player_id,
      game_id,
      assignment.color,
      public_game_snapshot.(game_id),
      public_lobby
    )
  end

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
