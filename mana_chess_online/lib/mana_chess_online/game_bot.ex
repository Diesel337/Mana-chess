defmodule ManaChessOnline.GameBot do
  @moduledoc false

  alias ManaChessOnline.{GameEngine, GameRules}

  @default_move_seconds 1.2
  @search_depth 4
  @branch_limit 8
  @root_branch_limit 12
  @mate_score 100_000
  @piece_values %{
    pawn: 100,
    knight: 320,
    bishop: 330,
    rook: 500,
    queen: 900,
    king: 20_000
  }

  def default_move_seconds, do: @default_move_seconds

  def move_delay_ms(settings),
    do: round(Map.get(settings, :bot_move_seconds, @default_move_seconds) * 1000)

  def maybe_enqueue_move(
        %{
          practice?: true,
          bot_enabled?: true,
          status: :playing,
          queue: [],
          promotion_pending: nil,
          first_move_pending: nil
        } = game,
        now_ms
      ) do
    if is_integer(game.bot_ready_at) and game.bot_ready_at <= now_ms do
      case action(game, now_ms) do
        nil -> %{game | bot_ready_at: now_ms + move_delay_ms(game.settings)}
        action -> %{game | queue: [action], bot_ready_at: now_ms + move_delay_ms(game.settings)}
      end
    else
      game
    end
  end

  def maybe_enqueue_move(game, _now_ms), do: game

  def action(game, now_ms) do
    game.board
    |> actions_for(:black, game)
    |> affordable_actions(game)
    |> pick_best_action(game, now_ms)
  end

  defp actions_for(board, color, game) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        to <- GameRules.legal_moves_for(board, r, c, color, game.castling_rights),
        do: %{player_id: :bot, color: color, from: {r, c}, to: to}
  end

  defp affordable_actions(actions, game) do
    Enum.filter(actions, fn action ->
      piece = GameRules.at(game.board, elem(action.from, 0), elem(action.from, 1))
      game.elixir[action.color] >= GameEngine.piece_cost(game.settings, piece)
    end)
  end

  defp pick_best_action([], _game, _now_ms), do: nil

  defp pick_best_action(actions, game, now_ms) do
    actions
    |> order_search_actions(game.board)
    |> Enum.take(@root_branch_limit)
    |> Enum.map(fn action ->
      position = apply_search_action(game.board, game.castling_rights, action)

      score =
        minimax(
          position.board,
          position.castling_rights,
          :white,
          @search_depth - 1,
          -@mate_score,
          @mate_score
        )

      {score + tiebreaker(action, now_ms), action}
    end)
    |> Enum.max_by(fn {score, _action} -> score end)
    |> elem(1)
  end

  defp minimax(board, castling_rights, color, depth, alpha, beta) do
    cond do
      depth <= 0 ->
        evaluate_board(board, castling_rights)

      not GameRules.has_legal_moves?(board, color, castling_rights) ->
        terminal_score(board, color, depth)

      color == :black ->
        actions =
          board
          |> legal_search_actions(color, castling_rights)
          |> order_search_actions(board)
          |> Enum.take(@branch_limit)

        maximize(board, castling_rights, actions, depth, alpha, beta)

      true ->
        actions =
          board
          |> legal_search_actions(color, castling_rights)
          |> order_search_actions(board)
          |> Enum.take(@branch_limit)

        minimize(board, castling_rights, actions, depth, alpha, beta)
    end
  end

  defp maximize(_board, _rights, [], _depth, alpha, _beta), do: alpha

  defp maximize(board, rights, [action | rest], depth, alpha, beta) do
    position = apply_search_action(board, rights, action)
    score = minimax(position.board, position.castling_rights, :white, depth - 1, alpha, beta)
    alpha = max(alpha, score)

    if alpha >= beta do
      alpha
    else
      maximize(board, rights, rest, depth, alpha, beta)
    end
  end

  defp minimize(_board, _rights, [], _depth, _alpha, beta), do: beta

  defp minimize(board, rights, [action | rest], depth, alpha, beta) do
    position = apply_search_action(board, rights, action)
    score = minimax(position.board, position.castling_rights, :black, depth - 1, alpha, beta)
    beta = min(beta, score)

    if alpha >= beta do
      beta
    else
      minimize(board, rights, rest, depth, alpha, beta)
    end
  end

  defp legal_search_actions(board, color, castling_rights) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        to <- GameRules.legal_moves_for(board, r, c, color, castling_rights),
        do: %{color: color, from: {r, c}, to: to}
  end

  defp order_search_actions(actions, board) do
    Enum.sort_by(actions, &search_action_priority(board, &1), :desc)
  end

  defp search_action_priority(board, action) do
    piece = GameRules.at(board, elem(action.from, 0), elem(action.from, 1))
    captured = GameRules.at(board, elem(action.to, 0), elem(action.to, 1))

    capture_value =
      if captured == ".", do: 0, else: Map.fetch!(@piece_values, GameEngine.piece_type(captured))

    promotion_value = if GameRules.promotion_pending?(piece, elem(action.to, 0)), do: 900, else: 0

    capture_value + promotion_value
  end

  defp apply_search_action(board, castling_rights, action) do
    piece = GameRules.at(board, elem(action.from, 0), elem(action.from, 1))
    {board, captured} = GameRules.move(board, action.from, action.to, castling_rights)

    castling_rights =
      GameRules.update_castling_rights(castling_rights, piece, action.from, captured, action.to)

    board =
      if GameRules.promotion_pending?(piece, elem(action.to, 0)) do
        promote_for_search(board, action.to, action.color)
      else
        board
      end

    %{board: board, castling_rights: castling_rights}
  end

  defp promote_for_search(board, to, :white), do: GameRules.promote(board, to, "Q", :white)
  defp promote_for_search(board, to, :black), do: GameRules.promote(board, to, "q", :black)

  defp evaluate_board(board, castling_rights) do
    material_score(board) + check_score(board, castling_rights)
  end

  defp material_score(board) do
    board
    |> List.flatten()
    |> Enum.reduce(0, fn
      ".", score ->
        score

      piece, score ->
        value = Map.fetch!(@piece_values, GameEngine.piece_type(piece))
        if GameRules.color(piece) == :black, do: score + value, else: score - value
    end)
  end

  defp check_score(board, castling_rights) do
    cond do
      GameRules.in_check?(board, :white) and
          not GameRules.has_legal_moves?(board, :white, castling_rights) ->
        @mate_score

      GameRules.in_check?(board, :black) and
          not GameRules.has_legal_moves?(board, :black, castling_rights) ->
        -@mate_score

      GameRules.in_check?(board, :white) ->
        25

      GameRules.in_check?(board, :black) ->
        -25

      true ->
        0
    end
  end

  defp terminal_score(board, color, depth) do
    cond do
      GameRules.in_check?(board, color) and color == :white -> @mate_score + depth
      GameRules.in_check?(board, color) and color == :black -> -@mate_score - depth
      true -> 0
    end
  end

  defp tiebreaker(action, now_ms) do
    :erlang.phash2({action.from, action.to, now_ms}, 11) / 100
  end
end
