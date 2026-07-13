defmodule ManaChessOnline.GameLobbyMoves do
  @moduledoc false

  alias ManaChessOnline.{GameChat, GameControl, GameEngine, GameLobbyServers, GamePlayers}

  def enqueue_move(state, player_id, from, to, now) do
    with %{game_id: game_id, color: player_color} <- GamePlayers.assignment(state, player_id),
         game when not is_nil(game) <- game_snapshot(game_id, state) do
      cond do
        not GameControl.valid_move_squares?(from, to) ->
          reject_move(state, game_id, "Movimiento rechazado: casilla invalida.")

        not GameControl.playing?(game) ->
          reject_move(state, game_id, "Movimiento rechazado: la partida no esta jugando.")

        GameControl.promotion_blocking?(game) ->
          reject_move(state, game_id, "Movimiento rechazado: hay una promocion pendiente.")

        true ->
          enqueue_valid_move(state, game_id, game, player_id, player_color, from, to, now)
      end
    else
      _ -> {state, nil}
    end
  end

  defp enqueue_valid_move(state, game_id, game, player_id, player_color, from, to, now) do
    piece = GameControl.piece_at(game, from)
    color = GameControl.piece_color(piece)

    cond do
      not GameControl.piece_present?(piece) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: no hay pieza en origen #{inspect(from)}."
        )

      not GameControl.playable_piece_color?(color) ->
        reject_move(state, game_id, "Movimiento rechazado: pieza sin color.")

      GameControl.bot_controls_color?(game, color) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: BOT controla #{GameChat.label(color)}."
        )

      not GameControl.controls_color?(player_color, color) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: no controlas #{GameChat.label(color)}."
        )

      not GameControl.first_move_allowed?(game, color) ->
        reject_move(state, game_id, "Movimiento rechazado: Blancas deben abrir.")

      cooldown_active?(game, from, now) ->
        reject_move(state, game_id, "Movimiento rechazado: pieza en cooldown.")

      not GameControl.legal_destination?(game, from, to, color) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: #{inspect(from)} -> #{inspect(to)} no es legal."
        )

      true ->
        action = GameControl.move_action(player_id, color, from, to)
        game = enqueue_game_action(game, action, now)

        {put_in(state.games[game_id], game), game_id}
    end
  end

  defp reject_move(state, game_id, message) do
    case game_snapshot(game_id, state) do
      nil ->
        {state, nil}

      game ->
        game = update_game_state(game, &update_in(&1.log, fn log -> [message | log] end))
        state = put_in(state.games[game_id], game)

        {state, game_id}
    end
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)

  defp enqueue_game_action(game, action, now),
    do: GameLobbyServers.enqueue_action(game, action, now)

  defp cooldown_active?(game, square, now),
    do: GameEngine.cooldown_active?(game, square, now)
end
