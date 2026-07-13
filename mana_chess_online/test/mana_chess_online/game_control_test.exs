defmodule ManaChessOnline.GameControlTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameControl, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

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

    assert GameControl.valid_move_squares?({0, 0}, {1, 1})
    refute GameControl.valid_move_squares?({0, 0}, {8, 1})
  end

  test "checks basic move gates" do
    assert GameControl.playing?(%{status: :playing})
    refute GameControl.playing?(%{status: :waiting})

    refute GameControl.promotion_blocking?(%{promotion_pending: nil})
    assert GameControl.promotion_blocking?(%{promotion_pending: %{at: {0, 0}}})
  end

  test "checks piece and destination gates" do
    game = GameState.new_game("game_1", settings())

    assert GameControl.piece_at(game, {6, 0}) == "P"
    assert GameControl.piece_color("P") == :white

    assert GameControl.piece_present?("P")
    refute GameControl.piece_present?(".")

    assert GameControl.playable_piece_color?(:white)
    refute GameControl.playable_piece_color?(nil)

    assert GameControl.legal_destination?(game, {6, 0}, {5, 0}, :white)
    refute GameControl.legal_destination?(game, {6, 0}, {4, 1}, :white)
  end

  test "builds move actions" do
    assert GameControl.move_action("player", :white, {6, 0}, {5, 0}) == %{
             player_id: "player",
             color: :white,
             from: {6, 0},
             to: {5, 0}
           }
  end
end
