defmodule ManaChessOnline.GameControl do
  @moduledoc false

  alias ManaChessOnline.GameRules

  def first_move_allowed?(%{first_move_pending: nil}, _color), do: true
  def first_move_allowed?(%{first_move_pending: color}, color), do: true
  def first_move_allowed?(_game, _color), do: false

  def controls_color?(:practice, color) when color in [:white, :black], do: true
  def controls_color?(color, color), do: true
  def controls_color?(_player_color, _piece_color), do: false

  def bot_controls_color?(%{practice?: true, bot_enabled?: true} = game, color),
    do: bot_color(game) == color

  def bot_controls_color?(_game, _color), do: false

  def bot_color(%{bot_color: color}) when color in [:white, :black], do: color
  def bot_color(_game), do: :black

  def opposite_color(:white), do: :black
  def opposite_color(:black), do: :white

  def valid_square?({r, c}), do: r in 0..7 and c in 0..7
  def valid_square?(_square), do: false

  def valid_move_squares?(from, to), do: valid_square?(from) and valid_square?(to)

  def playing?(%{status: :playing}), do: true
  def playing?(_game), do: false

  def promotion_blocking?(%{promotion_pending: nil}), do: false
  def promotion_blocking?(%{promotion_pending: _pending}), do: true
  def promotion_blocking?(_game), do: false

  def piece_at(game, square), do: GameRules.at(game.board, elem(square, 0), elem(square, 1))

  def piece_color(piece), do: GameRules.color(piece)

  def piece_present?(piece), do: piece != "."

  def playable_piece_color?(color), do: color in [:white, :black]

  def legal_destination?(game, from, to, color) do
    to in GameRules.legal_moves_for(
      game.board,
      elem(from, 0),
      elem(from, 1),
      color,
      game.castling_rights
    )
  end

  def move_action(player_id, color, from, to) do
    %{player_id: player_id, color: color, from: from, to: to}
  end
end
