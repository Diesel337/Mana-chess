defmodule ManaChessOnlineWeb.GameEffectEventsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnlineWeb.GameEffectEvents

  test "locates the destination square of a capture" do
    previous =
      game()
      |> put_piece({4, 2}, "P")
      |> put_piece({3, 3}, "p")

    current =
      previous
      |> put_piece({4, 2}, ".")
      |> put_piece({3, 3}, "P")

    assert GameEffectEvents.derive(previous, current, nil) == [
             %{kind: "capture", row: 3, col: 3}
           ]
  end

  test "announces only a newly checked king" do
    previous = game()

    current =
      previous
      |> put_piece({2, 4}, "R")
      |> Map.put(:checked_colors, [:black])

    assert GameEffectEvents.derive(previous, current, nil) == [
             %{kind: "check", row: 0, col: 4, color: "black"}
           ]

    assert GameEffectEvents.derive(current, current, nil) == []
  end

  test "announces a terminal transition with the rendered result copy" do
    previous = game()
    current = %{previous | status: {:checkmate, :white, :black}}
    result = %{title: "Ganaste", detail: "Jaque mate a negras.", tone: :win}

    assert GameEffectEvents.derive(previous, current, result) == [
             %{
               kind: "result",
               title: "Ganaste",
               detail: "Jaque mate a negras.",
               tone: "win"
             }
           ]

    assert GameEffectEvents.derive(current, current, result) == []
  end

  test "ignores updates for a different game" do
    assert GameEffectEvents.derive(game(), %{game() | id: "other"}, nil) == []
  end

  defp game do
    %{
      id: "effect-game",
      board:
        empty_board()
        |> put_board_piece({0, 4}, "k")
        |> put_board_piece({7, 4}, "K"),
      status: :active,
      checked_colors: []
    }
  end

  defp empty_board, do: List.duplicate(List.duplicate(".", 8), 8)

  defp put_piece(game, square, piece),
    do: %{game | board: put_board_piece(game.board, square, piece)}

  defp put_board_piece(board, {row, col}, piece) do
    List.update_at(board, row, &List.replace_at(&1, col, piece))
  end
end
