defmodule ManaChessOnline.GameEngine do
  @moduledoc false

  alias ManaChessOnline.{GameRules, GameState}

  @files ~w(a b c d e f g h)

  def process_next_action(%{queue: []} = game, _now_ms, _default_cooldown_seconds), do: game

  def process_next_action(
        %{promotion_pending: pending} = game,
        _now_ms,
        _default_cooldown_seconds
      )
      when not is_nil(pending),
      do: game

  def process_next_action(%{queue: [action | rest]} = game, now_ms, default_cooldown_seconds) do
    piece = GameRules.at(game.board, elem(action.from, 0), elem(action.from, 1))

    cond do
      piece == "." or GameRules.color(piece) != action.color ->
        %{game | queue: rest, log: ["Movimiento descartado: la pieza ya no esta ahi." | game.log]}

      game.elixir[action.color] < piece_cost(game.settings, piece) ->
        %{game | queue: rest, log: ["Sin elixir para #{label(action.color)}." | game.log]}

      action.to not in GameRules.legal_moves_for(
        game.board,
        elem(action.from, 0),
        elem(action.from, 1),
        action.color,
        game.castling_rights
      ) ->
        %{game | queue: rest, log: ["Movimiento descartado: ya no es valido." | game.log]}

      true ->
        cost = piece_cost(game.settings, piece)

        {board, captured} =
          GameRules.move(game.board, action.from, action.to, game.castling_rights)

        castling_rights =
          GameRules.update_castling_rights(
            game.castling_rights,
            piece,
            action.from,
            captured,
            action.to
          )

        cooldowns =
          game.cooldowns
          |> Map.delete(action.from)
          |> put_piece_cooldown(action.to, game.settings, now_ms, default_cooldown_seconds)

        {board, promotion_pending, status} =
          resolve_promotion(board, piece, action, castling_rights)

        %{
          game
          | board: board,
            castling_rights: castling_rights,
            cooldowns: cooldowns,
            promotion_pending: promotion_pending,
            queue: rest,
            first_move_pending: clear_first_move(game.first_move_pending, action.color),
            elixir: spend_and_refund_elixir(game, action.color, cost, captured),
            status: status || game.status,
            log: [move_message(action, piece, captured) | game.log]
        }
    end
  end

  def regen_elixir(%{status: :playing, first_move_pending: nil} = game, tick_ms) do
    regen_per_tick = game.settings.regen_per_second * tick_ms / 1000

    update_in(game.elixir, fn elixir ->
      Map.new(elixir, fn {color, amount} ->
        {color, min(game.settings.max_elixir, Float.round(amount + regen_per_tick, 2))}
      end)
    end)
  end

  def regen_elixir(game, _tick_ms), do: game

  def clear_expired_cooldowns(game, now_ms) do
    %{
      game
      | cooldowns: Map.reject(game.cooldowns, fn {_square, ready_at} -> ready_at <= now_ms end)
    }
  end

  def cooldown_active?(game, square, now_ms) do
    case Map.fetch(game.cooldowns, square) do
      {:ok, ready_at} -> ready_at > now_ms
      :error -> false
    end
  end

  def refresh_terminal_status(%{status: :playing} = game, now_ms) do
    case terminal_status(game.board, game.castling_rights) do
      nil -> game
      status -> %{game | status: status, queue: [], finished_at: now_ms}
    end
  end

  def refresh_terminal_status(game, _now_ms), do: game

  def terminal_status(board, castling_rights) do
    cond do
      GameRules.in_check?(board, :white) and
          not GameRules.has_legal_moves?(board, :white, castling_rights) ->
        {:checkmate, :black, :white}

      GameRules.in_check?(board, :black) and
          not GameRules.has_legal_moves?(board, :black, castling_rights) ->
        {:checkmate, :white, :black}

      not GameRules.has_legal_moves?(board, :white, castling_rights) and
          not GameRules.has_legal_moves?(board, :black, castling_rights) ->
        :draw

      true ->
        nil
    end
  end

  def piece_cost(settings, piece), do: Map.fetch!(settings.costs, piece_type(piece))

  def piece_type(piece) do
    case String.downcase(piece) do
      "p" -> :pawn
      "n" -> :knight
      "b" -> :bishop
      "r" -> :rook
      "q" -> :queen
      "k" -> :king
    end
  end

  defp put_piece_cooldown(cooldowns, square, settings, now_ms, default_cooldown_seconds) do
    cooldown_ms = round(GameState.piece_cooldown(settings, default_cooldown_seconds) * 1000)

    if not Map.get(settings, :cooldown_enabled, true) or cooldown_ms <= 0 do
      cooldowns
    else
      Map.put(cooldowns, square, now_ms + cooldown_ms)
    end
  end

  defp resolve_promotion(board, piece, %{player_id: :bot, color: :black, to: to}, castling_rights) do
    if GameRules.promotion_pending?(piece, elem(to, 0)) do
      board = GameRules.promote(board, to, "q", :black)
      {board, nil, terminal_status(board, castling_rights)}
    else
      {board, nil, terminal_status(board, castling_rights)}
    end
  end

  defp resolve_promotion(board, piece, action, castling_rights) do
    if GameRules.promotion_pending?(piece, elem(action.to, 0)) do
      {board, %{player_id: action.player_id, color: action.color, at: action.to}, :promotion}
    else
      {board, nil, terminal_status(board, castling_rights)}
    end
  end

  defp spend_and_refund_elixir(game, color, cost, captured) do
    max_elixir = game.settings.max_elixir
    refund = capture_refund(game.settings, captured)

    Map.update!(game.elixir, color, fn amount ->
      amount
      |> Kernel.-(cost)
      |> Kernel.+(refund)
      |> min(max_elixir)
      |> Float.round(2)
    end)
  end

  defp capture_refund(_settings, "."), do: 0.0

  defp capture_refund(settings, captured),
    do: piece_cost(settings, captured) * settings.capture_refund_percent / 100

  defp move_message(action, piece, ".") do
    "#{label(action.color)} movio #{piece_label(piece)} #{square_name(action.from)} -> #{square_name(action.to)}."
  end

  defp move_message(action, piece, captured) do
    "#{label(action.color)} movio #{piece_label(piece)} #{square_name(action.from)} -> #{square_name(action.to)} y capturo #{piece_label(captured)}."
  end

  defp piece_label(piece) do
    case piece_type(piece) do
      :pawn -> "peon"
      :knight -> "caballo"
      :bishop -> "alfil"
      :rook -> "torre"
      :queen -> "reina"
      :king -> "rey"
    end
  end

  defp square_name({row, col})
       when is_integer(row) and is_integer(col) and row >= 0 and row <= 7 and col >= 0 and
              col <= 7 do
    "#{Enum.at(@files, col)}#{8 - row}"
  end

  defp square_name(square), do: inspect(square)

  defp label(:white), do: "Blancas"
  defp label(:black), do: "Negras"

  defp clear_first_move(:white, :white), do: nil
  defp clear_first_move(first_move_pending, _color), do: first_move_pending
end
