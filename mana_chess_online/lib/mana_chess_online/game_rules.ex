defmodule ManaChessOnline.GameRules do
  @moduledoc false

  @empty "."
  @costs %{"P" => 1.0, "N" => 3.0, "B" => 3.0, "R" => 4.0, "Q" => 6.0, "K" => 3.0}

  def initial_board do
    [
      ["r", "n", "b", "q", "k", "b", "n", "r"],
      ["p", "p", "p", "p", "p", "p", "p", "p"],
      empty_row(),
      empty_row(),
      empty_row(),
      empty_row(),
      ["P", "P", "P", "P", "P", "P", "P", "P"],
      ["R", "N", "B", "Q", "K", "B", "N", "R"]
    ]
  end

  def piece_cost(piece), do: Map.fetch!(@costs, String.upcase(piece))

  def color("."), do: nil
  def color(piece), do: if(piece == String.upcase(piece), do: :white, else: :black)

  def legal_move?(board, color, {from_r, from_c}, {to_r, to_c}) do
    with true <- in_bounds?(from_r, from_c) and in_bounds?(to_r, to_c),
         piece when piece != @empty <- at(board, from_r, from_c),
         ^color <- color(piece),
         true <- {to_r, to_c} in legal_moves_for(board, from_r, from_c, color) do
      true
    else
      _ -> false
    end
  end

  def legal_moves_for(board, r, c, color, castling_rights \\ %{}) do
    board
    |> moves_for(r, c, color, castling_rights)
    |> Enum.reject(&king_capture?(board, &1))
    |> Enum.filter(fn to ->
      {next_board, _captured} = move(board, {r, c}, to, castling_rights)
      not in_check?(next_board, color)
    end)
  end

  def in_check?(board, color) do
    with {king_r, king_c} <- king_position(board, color) do
      attacked?(board, {king_r, king_c}, opposite(color))
    else
      nil -> true
    end
  end

  def checked_colors(board) do
    [:white, :black]
    |> Enum.filter(&in_check?(board, &1))
  end

  def king_square(board, color), do: king_position(board, color)

  def has_legal_moves?(board, color, castling_rights \\ %{}) do
    board
    |> all_piece_squares(color)
    |> Enum.any?(fn {r, c} -> legal_moves_for(board, r, c, color, castling_rights) != [] end)
  end

  def move(board, {from_r, from_c}, {to_r, to_c}, _castling_rights \\ %{}) do
    piece = at(board, from_r, from_c)
    captured = at(board, to_r, to_c)

    board =
      board
      |> put_at(from_r, from_c, @empty)
      |> put_at(to_r, to_c, piece)
      |> maybe_move_castling_rook(piece, {from_r, from_c}, {to_r, to_c})

    {board, captured}
  end

  def promotion_pending?(piece, row), do: piece == "P" and row == 0 or piece == "p" and row == 7

  def promote(board, {r, c}, choice, :white) when choice in ["Q", "R", "B", "N"], do: put_at(board, r, c, choice)
  def promote(board, {r, c}, choice, :black) when choice in ["q", "r", "b", "n"], do: put_at(board, r, c, choice)

  def moves_for(board, r, c, color, castling_rights \\ %{}) do
    piece = at(board, r, c)

    case String.downcase(piece) do
      "p" -> pawn_moves(board, r, c, color)
      "n" -> knight_moves(board, r, c, color)
      "b" -> sliding_moves(board, r, c, color, [{-1, -1}, {-1, 1}, {1, -1}, {1, 1}])
      "r" -> sliding_moves(board, r, c, color, [{-1, 0}, {1, 0}, {0, -1}, {0, 1}])
      "q" -> sliding_moves(board, r, c, color, [{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {-1, 1}, {1, -1}, {1, 1}])
      "k" -> king_moves(board, r, c, color, castling_rights)
      _ -> []
    end
  end

  def update_castling_rights(rights, piece, from, captured, to) do
    rights
    |> disable_moved_piece(piece, from)
    |> disable_captured_rook(captured, to)
  end

  def at(board, r, c), do: board |> Enum.at(r) |> Enum.at(c)

  defp king_position(board, color) do
    king = if color == :white, do: "K", else: "k"

    Enum.find_value(Enum.with_index(board), fn {row, r} ->
      Enum.find_value(Enum.with_index(row), fn
        {^king, c} -> {r, c}
        _ -> nil
      end)
    end)
  end

  defp attacked?(board, pos, by_color) do
    board
    |> all_piece_squares(by_color)
    |> Enum.any?(fn {r, c} -> pos in attacks_for(board, r, c, by_color) end)
  end

  defp all_piece_squares(board, color) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != @empty,
        color(piece) == color,
        do: {r, c}
  end

  defp attacks_for(board, r, c, color) do
    case String.downcase(at(board, r, c)) do
      "p" -> pawn_attacks(r, c, color)
      "n" -> knight_moves(board, r, c, color)
      "b" -> sliding_attacks(board, r, c, [{-1, -1}, {-1, 1}, {1, -1}, {1, 1}])
      "r" -> sliding_attacks(board, r, c, [{-1, 0}, {1, 0}, {0, -1}, {0, 1}])
      "q" -> sliding_attacks(board, r, c, [{-1, 0}, {1, 0}, {0, -1}, {0, 1}, {-1, -1}, {-1, 1}, {1, -1}, {1, 1}])
      "k" -> king_attacks(r, c)
      _ -> []
    end
  end

  defp empty_row, do: List.duplicate(@empty, 8)

  defp king_capture?(board, {r, c}), do: at(board, r, c) in ["K", "k"]

  defp put_at(board, r, c, value) do
    List.update_at(board, r, fn row -> List.replace_at(row, c, value) end)
  end

  defp maybe_move_castling_rook(board, "K", {7, 4}, {7, 6}), do: board |> put_at(7, 7, @empty) |> put_at(7, 5, "R")
  defp maybe_move_castling_rook(board, "K", {7, 4}, {7, 2}), do: board |> put_at(7, 0, @empty) |> put_at(7, 3, "R")
  defp maybe_move_castling_rook(board, "k", {0, 4}, {0, 6}), do: board |> put_at(0, 7, @empty) |> put_at(0, 5, "r")
  defp maybe_move_castling_rook(board, "k", {0, 4}, {0, 2}), do: board |> put_at(0, 0, @empty) |> put_at(0, 3, "r")
  defp maybe_move_castling_rook(board, _piece, _from, _to), do: board

  defp pawn_moves(board, r, c, :white), do: pawn_moves(board, r, c, :white, -1, 6)
  defp pawn_moves(board, r, c, :black), do: pawn_moves(board, r, c, :black, 1, 1)

  defp pawn_moves(board, r, c, color, dir, start_row) do
    forward = {r + dir, c}
    double = {r + 2 * dir, c}

    []
    |> add_if(empty?(board, forward), forward)
    |> add_if(r == start_row and empty?(board, forward) and empty?(board, double), double)
    |> add_if(enemy?(board, {r + dir, c - 1}, color), {r + dir, c - 1})
    |> add_if(enemy?(board, {r + dir, c + 1}, color), {r + dir, c + 1})
  end

  defp pawn_attacks(r, c, :white), do: [{r - 1, c - 1}, {r - 1, c + 1}] |> Enum.filter(&in_bounds?/1)
  defp pawn_attacks(r, c, :black), do: [{r + 1, c - 1}, {r + 1, c + 1}] |> Enum.filter(&in_bounds?/1)

  defp knight_moves(board, r, c, color) do
    [{-2, -1}, {-2, 1}, {-1, -2}, {-1, 2}, {1, -2}, {1, 2}, {2, -1}, {2, 1}]
    |> Enum.map(fn {dr, dc} -> {r + dr, c + dc} end)
    |> Enum.filter(&open_or_enemy?(board, &1, color))
  end

  defp king_moves(board, r, c, color, castling_rights) do
    king_attacks(r, c)
    |> Enum.filter(&open_or_enemy?(board, &1, color))
    |> Kernel.++(castling_moves(board, r, c, color, castling_rights))
  end

  defp king_attacks(r, c) do
    for dr <- -1..1,
        dc <- -1..1,
        {dr, dc} != {0, 0},
        in_bounds?({r + dr, c + dc}),
        do: {r + dr, c + dc}
  end

  defp sliding_moves(board, r, c, color, directions) do
    Enum.flat_map(directions, fn {dr, dc} ->
      1..7
      |> Enum.reduce_while([], fn step, acc ->
        pos = {r + dr * step, c + dc * step}

        cond do
          not in_bounds?(pos) -> {:halt, acc}
          empty?(board, pos) -> {:cont, [pos | acc]}
          enemy?(board, pos, color) -> {:halt, [pos | acc]}
          true -> {:halt, acc}
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp sliding_attacks(board, r, c, directions) do
    Enum.flat_map(directions, fn {dr, dc} ->
      1..7
      |> Enum.reduce_while([], fn step, acc ->
        pos = {r + dr * step, c + dc * step}

        cond do
          not in_bounds?(pos) -> {:halt, acc}
          empty?(board, pos) -> {:cont, [pos | acc]}
          true -> {:halt, [pos | acc]}
        end
      end)
      |> Enum.reverse()
    end)
  end

  defp castling_moves(board, 7, 4, :white, rights) do
    []
    |> add_if(can_castle_kingside?(board, :white, rights), {7, 6})
    |> add_if(can_castle_queenside?(board, :white, rights), {7, 2})
  end

  defp castling_moves(board, 0, 4, :black, rights) do
    []
    |> add_if(can_castle_kingside?(board, :black, rights), {0, 6})
    |> add_if(can_castle_queenside?(board, :black, rights), {0, 2})
  end

  defp castling_moves(_board, _r, _c, _color, _rights), do: []

  defp can_castle_kingside?(board, color, rights) do
    row = if color == :white, do: 7, else: 0
    rook = if color == :white, do: "R", else: "r"

    Map.get(rights, {color, :king}, false) and
      at(board, row, 7) == rook and
      empty?(board, {row, 5}) and
      empty?(board, {row, 6}) and
      not in_check?(board, color) and
      not attacked?(board, {row, 5}, opposite(color)) and
      not attacked?(board, {row, 6}, opposite(color))
  end

  defp can_castle_queenside?(board, color, rights) do
    row = if color == :white, do: 7, else: 0
    rook = if color == :white, do: "R", else: "r"

    Map.get(rights, {color, :queen}, false) and
      at(board, row, 0) == rook and
      empty?(board, {row, 1}) and
      empty?(board, {row, 2}) and
      empty?(board, {row, 3}) and
      not in_check?(board, color) and
      not attacked?(board, {row, 3}, opposite(color)) and
      not attacked?(board, {row, 2}, opposite(color))
  end

  defp add_if(list, true, value), do: [value | list]
  defp add_if(list, false, _value), do: list

  defp open_or_enemy?(board, pos, color), do: empty?(board, pos) or enemy?(board, pos, color)
  defp empty?(board, pos), do: in_bounds?(pos) and at(board, elem(pos, 0), elem(pos, 1)) == @empty
  defp enemy?(board, pos, color), do: in_bounds?(pos) and at(board, elem(pos, 0), elem(pos, 1)) not in [@empty] and color(at(board, elem(pos, 0), elem(pos, 1))) != color
  defp in_bounds?({r, c}), do: in_bounds?(r, c)
  defp in_bounds?(r, c), do: r in 0..7 and c in 0..7
  defp opposite(:white), do: :black
  defp opposite(:black), do: :white

  defp disable_moved_piece(rights, "K", _from), do: rights |> Map.put({:white, :king}, false) |> Map.put({:white, :queen}, false)
  defp disable_moved_piece(rights, "k", _from), do: rights |> Map.put({:black, :king}, false) |> Map.put({:black, :queen}, false)
  defp disable_moved_piece(rights, "R", {7, 7}), do: Map.put(rights, {:white, :king}, false)
  defp disable_moved_piece(rights, "R", {7, 0}), do: Map.put(rights, {:white, :queen}, false)
  defp disable_moved_piece(rights, "r", {0, 7}), do: Map.put(rights, {:black, :king}, false)
  defp disable_moved_piece(rights, "r", {0, 0}), do: Map.put(rights, {:black, :queen}, false)
  defp disable_moved_piece(rights, _piece, _from), do: rights

  defp disable_captured_rook(rights, "R", {7, 7}), do: Map.put(rights, {:white, :king}, false)
  defp disable_captured_rook(rights, "R", {7, 0}), do: Map.put(rights, {:white, :queen}, false)
  defp disable_captured_rook(rights, "r", {0, 7}), do: Map.put(rights, {:black, :king}, false)
  defp disable_captured_rook(rights, "r", {0, 0}), do: Map.put(rights, {:black, :queen}, false)
  defp disable_captured_rook(rights, _captured, _to), do: rights
end
