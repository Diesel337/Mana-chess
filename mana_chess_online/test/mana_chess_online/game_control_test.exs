defmodule ManaChessOnline.GameControlTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameControl

  test "checks first move ownership" do
    assert GameControl.first_move_allowed?(%{first_move_pending: nil}, :white)
    assert GameControl.first_move_allowed?(%{first_move_pending: :white}, :white)
    refute GameControl.first_move_allowed?(%{first_move_pending: :black}, :white)
  end

  test "checks player color control" do
    assert GameControl.controls_color?(:practice, :white)
    assert GameControl.controls_color?(:practice, :black)
    assert GameControl.controls_color?(:white, :white)
    refute GameControl.controls_color?(:white, :black)
    refute GameControl.controls_color?(nil, :white)
  end

  test "checks bot color control" do
    assert GameControl.bot_controls_color?(
             %{practice?: true, bot_enabled?: true, bot_color: :white},
             :white
           )

    refute GameControl.bot_controls_color?(
             %{practice?: true, bot_enabled?: false, bot_color: :white},
             :white
           )

    assert GameControl.bot_color(%{}) == :black
    assert GameControl.opposite_color(:white) == :black
    assert GameControl.opposite_color(:black) == :white
  end

  test "validates board squares" do
    assert GameControl.valid_square?({0, 0})
    assert GameControl.valid_square?({7, 7})
    refute GameControl.valid_square?({8, 0})
    refute GameControl.valid_square?(:bad)
  end
end
