defmodule ManaChessOnlineWeb.GameEffectEvents do
  @moduledoc false

  alias ManaChessOnline.{GamePersistence, GameRules}

  def derive(%{id: game_id} = previous, %{id: game_id} = current, result) do
    capture_events(previous, current) ++
      check_events(previous, current) ++
      result_events(previous, current, result)
  end

  def derive(_previous, _current, _result), do: []

  defp capture_events(
         %{board: previous_board} = previous,
         %{board: current_board} = current
       ) do
    if piece_count(current_board) < piece_count(previous_board) do
      case capture_square(previous_board, current_board) do
        {row, col} = square ->
          event = %{kind: "capture", row: row, col: col}

          case recovered_mana(previous, current, square) do
            amount when is_number(amount) and amount > 0 -> [Map.put(event, :mana, amount)]
            _amount -> [event]
          end

        nil ->
          []
      end
    else
      []
    end
  end

  defp capture_events(_previous, _current), do: []

  defp capture_square(previous, current) do
    squares =
      for row <- 0..7,
          col <- 0..7,
          previous_piece = GameRules.at(previous, row, col),
          current_piece = GameRules.at(current, row, col),
          previous_piece != current_piece,
          current_piece != ".",
          previous_piece == "." or
            GameRules.color(previous_piece) != GameRules.color(current_piece),
          do: {row, col}

    List.first(squares)
  end

  defp piece_count(board) do
    Enum.reduce(board, 0, fn row, total ->
      total + Enum.count(row, &(&1 != "."))
    end)
  end

  defp recovered_mana(previous, current, {row, col} = destination) do
    case Map.get(current, :last_capture_refund) do
      amount when is_number(amount) -> Float.round(amount * 1.0, 2)
      _missing -> estimated_recovered_mana(previous, current, {row, col}, destination)
    end
  end

  defp estimated_recovered_mana(previous, current, {row, col}, destination) do
    captured_piece = GameRules.at(previous.board, row, col)
    current_piece = GameRules.at(current.board, row, col)
    mover_color = GameRules.color(current_piece)
    moving_piece = moving_piece(previous.board, current.board, mover_color, destination)
    settings = Map.get(previous, :settings, %{})
    costs = Map.get(settings, :costs, %{})

    with color when color in [:white, :black] <- mover_color,
         piece when is_binary(piece) <- moving_piece,
         mover_cost when is_number(mover_cost) <- Map.get(costs, piece_type(piece)),
         captured_cost when is_number(captured_cost) <-
           Map.get(costs, piece_type(captured_piece)),
         refund_percent when is_number(refund_percent) <-
           Map.get(settings, :capture_refund_percent),
         max_elixir when is_number(max_elixir) <- Map.get(settings, :max_elixir),
         elixir when is_map(elixir) <- Map.get(previous, :elixir),
         before_amount when is_number(before_amount) <- Map.get(elixir, color) do
      theoretical_refund = captured_cost * refund_percent / 100
      room_after_spending = max(max_elixir - (before_amount - mover_cost), 0)

      theoretical_refund
      |> min(room_after_spending)
      |> max(0)
      |> Float.round(2)
    else
      _missing_data -> nil
    end
  end

  defp moving_piece(previous, current, mover_color, destination) do
    for(
      row <- 0..7,
      col <- 0..7,
      {row, col} != destination,
      previous_piece = GameRules.at(previous, row, col),
      current_piece = GameRules.at(current, row, col),
      previous_piece != ".",
      GameRules.color(previous_piece) == mover_color,
      current_piece == ".",
      do: previous_piece
    )
    |> List.first()
  end

  defp piece_type(piece) do
    case String.downcase(piece) do
      "p" -> :pawn
      "n" -> :knight
      "b" -> :bishop
      "r" -> :rook
      "q" -> :queen
      "k" -> :king
      _piece -> nil
    end
  end

  defp check_events(previous, current) do
    previous_checks = Map.get(previous, :checked_colors, []) |> MapSet.new()

    current
    |> Map.get(:checked_colors, [])
    |> Enum.reject(&MapSet.member?(previous_checks, &1))
    |> Enum.flat_map(fn color ->
      case GameRules.king_square(current.board, color) do
        {row, col} ->
          [%{kind: "check", row: row, col: col, color: Atom.to_string(color)}]

        nil ->
          []
      end
    end)
  end

  defp result_events(previous, current, result) do
    if not GamePersistence.terminal?(previous) and GamePersistence.terminal?(current) and result do
      [
        %{
          kind: "result",
          title: result.title,
          detail: result.detail,
          tone: Atom.to_string(result.tone)
        }
      ]
    else
      []
    end
  end
end
