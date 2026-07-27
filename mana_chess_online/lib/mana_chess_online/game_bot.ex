defmodule ManaChessOnline.GameBot do
  @moduledoc false

  alias ManaChessOnline.{GameBotDifficulty, GameEngine, GameRules}

  @default_move_seconds 1.2
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

  def difficulties, do: GameBotDifficulty.levels()
  def difficulty_label(level), do: GameBotDifficulty.label(level)
  def difficulty_description(level), do: GameBotDifficulty.description(level)
  def parse_difficulty(level), do: GameBotDifficulty.parse(level)
  def normalize_difficulty(level), do: GameBotDifficulty.normalize(level)

  def difficulty(game),
    do: game |> Map.get(:bot_difficulty, :normal) |> normalize_difficulty()

  def move_delay_ms(settings, level \\ :normal) do
    multiplier = GameBotDifficulty.profile(level).delay_multiplier
    round(Map.get(settings, :bot_move_seconds, @default_move_seconds) * multiplier * 1000)
  end

  def maybe_enqueue_move(
        %{
          practice?: true,
          bot_enabled?: true,
          status: :playing,
          queue: [],
          promotion_pending: nil
        } = game,
        now_ms
      ) do
    color = bot_color(game)

    if bot_can_move?(game, color) and is_integer(game.bot_ready_at) and
         game.bot_ready_at <= now_ms do
      case action(game, now_ms) do
        nil ->
          %{game | bot_ready_at: now_ms + move_delay_ms(game.settings, difficulty(game))}

        action ->
          %{
            game
            | queue: [action],
              bot_ready_at: now_ms + move_delay_ms(game.settings, difficulty(game))
          }
      end
    else
      game
    end
  end

  def maybe_enqueue_move(game, _now_ms), do: game

  def action(game, now_ms) do
    color = bot_color(game)
    profile = GameBotDifficulty.profile(difficulty(game))

    game
    |> search_position()
    |> actions_for(color, game, now_ms)
    |> pick_best_action(game, now_ms, color, profile)
  end

  defp bot_color(%{bot_color: color}) when color in [:white, :black], do: color
  defp bot_color(_game), do: :black

  defp bot_can_move?(%{first_move_pending: nil}, _color), do: true
  defp bot_can_move?(%{first_move_pending: color}, color), do: true
  defp bot_can_move?(_game, _color), do: false

  defp actions_for(%{board: board} = position, color, game, now_ms) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        not GameEngine.cooldown_active?(game, {r, c}, now_ms),
        affordable?(position, game.settings, color, piece),
        to <- GameRules.legal_moves_for(board, r, c, color, position.castling_rights),
        do: %{player_id: :bot, color: color, from: {r, c}, to: to}
  end

  defp pick_best_action([], _game, _now_ms, _color, _profile), do: nil

  defp pick_best_action(actions, game, now_ms, color, profile) do
    position = search_position(game)

    scored_actions =
      actions
      |> order_search_actions(position.board)
      |> Enum.take(profile.root_branch_limit)
      |> Enum.map(fn action ->
        next_position = apply_search_action(position, action, game.settings)

        score =
          minimax(
            next_position,
            opposite(color),
            profile.search_depth - 1,
            -@mate_score,
            @mate_score,
            profile,
            game.settings
          )

        {score + tiebreaker(action, now_ms), action}
      end)

    scored_actions
    |> rank_for_color(color)
    |> Enum.take(profile.choice_pool)
    |> pick_from_pool(color, now_ms)
    |> elem(1)
  end

  defp rank_for_color(scored_actions, :black),
    do: Enum.sort_by(scored_actions, fn {score, _action} -> score end, :desc)

  defp rank_for_color(scored_actions, :white),
    do: Enum.sort_by(scored_actions, fn {score, _action} -> score end, :asc)

  defp pick_from_pool([only], _color, _now_ms), do: only

  defp pick_from_pool(pool, color, now_ms) do
    Enum.at(pool, :erlang.phash2({color, now_ms}, length(pool)))
  end

  defp minimax(position, color, depth, alpha, beta, profile, settings) do
    cond do
      depth <= 0 ->
        evaluate_position(position, profile)

      not GameRules.has_legal_moves?(position.board, color, position.castling_rights) ->
        terminal_score(position.board, color, depth)

      true ->
        actions =
          position
          |> legal_search_actions(color, settings)
          |> order_search_actions(position.board)
          |> Enum.take(profile.branch_limit)

        continue_search(position, color, actions, depth, alpha, beta, profile, settings)
    end
  end

  defp continue_search(position, _color, [], _depth, _alpha, _beta, profile, _settings),
    do: evaluate_position(position, profile)

  defp continue_search(position, :black, actions, depth, alpha, beta, profile, settings),
    do: maximize(position, actions, depth, alpha, beta, profile, settings)

  defp continue_search(position, :white, actions, depth, alpha, beta, profile, settings),
    do: minimize(position, actions, depth, alpha, beta, profile, settings)

  defp maximize(_position, [], _depth, alpha, _beta, _profile, _settings), do: alpha

  defp maximize(position, [action | rest], depth, alpha, beta, profile, settings) do
    next_position = apply_search_action(position, action, settings)

    score =
      minimax(next_position, :white, depth - 1, alpha, beta, profile, settings)

    alpha = max(alpha, score)

    if alpha >= beta do
      alpha
    else
      maximize(position, rest, depth, alpha, beta, profile, settings)
    end
  end

  defp minimize(_position, [], _depth, _alpha, beta, _profile, _settings), do: beta

  defp minimize(position, [action | rest], depth, alpha, beta, profile, settings) do
    next_position = apply_search_action(position, action, settings)

    score =
      minimax(next_position, :black, depth - 1, alpha, beta, profile, settings)

    beta = min(beta, score)

    if alpha >= beta do
      beta
    else
      minimize(position, rest, depth, alpha, beta, profile, settings)
    end
  end

  defp legal_search_actions(%{board: board} = position, color, settings) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        affordable?(position, settings, color, piece),
        to <- GameRules.legal_moves_for(board, r, c, color, position.castling_rights),
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

    castling_value =
      if GameEngine.piece_type(piece) == :king and
           abs(elem(action.from, 1) - elem(action.to, 1)) == 2,
         do: 45,
         else: 0

    destination_value = centrality(action.to)
    development_value = development_priority(piece, action.from, action.to)

    capture_value + promotion_value + castling_value + destination_value + development_value
  end

  defp apply_search_action(position, action, settings) do
    piece = GameRules.at(position.board, elem(action.from, 0), elem(action.from, 1))

    {board, captured} =
      GameRules.move(position.board, action.from, action.to, position.castling_rights)

    castling_rights =
      GameRules.update_castling_rights(
        position.castling_rights,
        piece,
        action.from,
        captured,
        action.to
      )

    board =
      if GameRules.promotion_pending?(piece, elem(action.to, 0)) do
        promote_for_search(board, action.to, action.color)
      else
        board
      end

    %{
      board: board,
      castling_rights: castling_rights,
      elixir: spend_search_elixir(position.elixir, action.color, piece, captured, settings)
    }
  end

  defp promote_for_search(board, to, :white), do: GameRules.promote(board, to, "Q", :white)
  defp promote_for_search(board, to, :black), do: GameRules.promote(board, to, "q", :black)

  defp evaluate_position(position, profile) do
    material_score(position.board) +
      check_score(position.board, position.castling_rights) +
      profile.positional_weight * positional_score(position.board) +
      round(profile.resource_weight * resource_score(position.elixir))
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

  defp opposite(:white), do: :black
  defp opposite(:black), do: :white

  defp search_position(game) do
    %{
      board: game.board,
      castling_rights: game.castling_rights,
      elixir: game.elixir
    }
  end

  defp affordable?(position, settings, color, piece) do
    Map.fetch!(position.elixir, color) >= GameEngine.piece_cost(settings, piece)
  end

  defp spend_search_elixir(elixir, color, piece, captured, settings) do
    cost = GameEngine.piece_cost(settings, piece)

    refund =
      if captured == "." do
        0.0
      else
        GameEngine.piece_cost(settings, captured) *
          Map.get(settings, :capture_refund_percent, 0) / 100
      end

    max_elixir = Map.get(settings, :max_elixir, 10.0)
    Map.update!(elixir, color, &min(max_elixir, &1 - cost + refund))
  end

  defp resource_score(elixir), do: elixir.black - elixir.white

  defp positional_score(board) do
    board
    |> Enum.with_index()
    |> Enum.reduce(0, fn {row, row_index}, score ->
      row
      |> Enum.with_index()
      |> Enum.reduce(score, fn
        {".", _col_index}, inner_score ->
          inner_score

        {piece, col_index}, inner_score ->
          value = piece_position_value(piece, {row_index, col_index})

          if GameRules.color(piece) == :black,
            do: inner_score + value,
            else: inner_score - value
      end)
    end)
  end

  defp piece_position_value(piece, square) do
    case GameEngine.piece_type(piece) do
      :pawn -> pawn_advancement(piece, square) * 4 + div(centrality(square), 3)
      :knight -> centrality(square) * 2
      :bishop -> centrality(square)
      :rook -> div(centrality(square), 4)
      :queen -> div(centrality(square), 3)
      :king -> king_position_value(piece, square)
    end
  end

  defp pawn_advancement(piece, {row, _col}) do
    if GameRules.color(piece) == :white, do: max(0, 6 - row), else: max(0, row - 1)
  end

  defp king_position_value(piece, {row, col}) do
    home_row = if GameRules.color(piece) == :white, do: 7, else: 0

    cond do
      row == home_row and col in [2, 6] -> 28
      row == home_row -> 6
      true -> -12
    end
  end

  defp development_priority(piece, {from_row, _from_col}, {to_row, _to_col}) do
    case {GameEngine.piece_type(piece), GameRules.color(piece), from_row, to_row} do
      {type, :white, 7, row} when type in [:knight, :bishop] and row < 7 -> 20
      {type, :black, 0, row} when type in [:knight, :bishop] and row > 0 -> 20
      _ -> 0
    end
  end

  defp centrality({row, col}) do
    14 - (abs(2 * row - 7) + abs(2 * col - 7))
  end

  defp tiebreaker(action, now_ms) do
    :erlang.phash2({action.from, action.to, now_ms}, 11) / 100
  end
end
