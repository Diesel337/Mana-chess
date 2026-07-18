defmodule ManaChessOnlineWeb.GameEffectEvents do
  @moduledoc false

  alias ManaChessOnline.{GamePersistence, GameRules}

  def derive(%{id: game_id} = previous, %{id: game_id} = current, result) do
    capture_events(previous, current) ++
      check_events(previous, current) ++
      result_events(previous, current, result)
  end

  def derive(_previous, _current, _result), do: []

  defp capture_events(%{board: previous}, %{board: current}) do
    if piece_count(current) < piece_count(previous) do
      case capture_square(previous, current) do
        {row, col} -> [%{kind: "capture", row: row, col: col}]
        nil -> []
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
