defmodule ManaChessOnline.GameRulesTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameRules

  test "legal moves do not include capturing the king" do
    board = [
      [".", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "Q", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]

    refute {0, 4} in GameRules.legal_moves_for(board, 3, 4, :white)
  end
end
