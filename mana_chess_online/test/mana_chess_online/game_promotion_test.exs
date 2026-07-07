defmodule ManaChessOnline.GamePromotionTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GamePromotion

  test "maps promotion choices for white" do
    assert GamePromotion.choice("Q", :white) == "Q"
    assert GamePromotion.choice("R", :white) == "R"
    assert GamePromotion.choice("B", :white) == "B"
    assert GamePromotion.choice("N", :white) == "N"
    assert GamePromotion.choice("bad", :white) == "Q"
  end

  test "maps promotion choices for black" do
    assert GamePromotion.choice("Q", :black) == "q"
    assert GamePromotion.choice("R", :black) == "r"
    assert GamePromotion.choice("B", :black) == "b"
    assert GamePromotion.choice("N", :black) == "n"
    assert GamePromotion.choice("bad", :black) == "q"
  end
end
