defmodule ManaChessOnline.GameTutorial do
  @moduledoc false

  alias ManaChessOnline.GameRules

  @opening_from {6, 3}
  @opening_to {5, 3}
  @opening_capture {4, 4}

  @sprint_actions [
    %{stage: :sprint_pawn, piece: :pawn, from: {6, 1}, to: {5, 1}},
    %{stage: :sprint_knight, piece: :knight, from: {6, 3}, to: {4, 4}},
    %{stage: :sprint_bishop, piece: :bishop, from: {7, 5}, to: {4, 2}},
    %{stage: :sprint_rook, piece: :rook, from: {6, 7}, to: {4, 7}}
  ]

  @capture_pawn_from {5, 2}
  @capture_pawn_to {4, 3}
  @capture_queen_from {5, 5}
  @capture_queen_to {4, 4}

  @stages [
    :move,
    :cooldown,
    :capture_knight,
    :capture_knight_result,
    :sprint_pawn,
    :sprint_knight,
    :sprint_bishop,
    :sprint_rook,
    :sprint_result,
    :capture_pawn,
    :capture_pawn_result,
    :capture_queen,
    :complete
  ]

  def board do
    [
      [".", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "n", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", "P", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]
  end

  def sprint_board do
    [
      [".", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", "P", ".", "N", ".", ".", ".", "R"],
      [".", ".", ".", ".", "K", "B", ".", "."]
    ]
  end

  def capture_board do
    [
      [".", ".", ".", ".", ".", ".", ".", "k"],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", "p", "q", ".", ".", "."],
      [".", ".", "P", ".", ".", "P", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      ["K", ".", ".", ".", ".", ".", ".", "."]
    ]
  end

  def capture_piece_type, do: :knight

  def castling_rights do
    %{
      {:white, :king} => false,
      {:white, :queen} => false,
      {:black, :king} => false,
      {:black, :queen} => false
    }
  end

  def tutorial?(%{tutorial?: true}), do: true
  def tutorial?(_game), do: false

  def stage(%{tutorial?: true} = game) do
    case Map.get(game, :tutorial_step) do
      step when step in @stages -> step
      _step -> inferred_stage(game)
    end
  end

  def stage(_game), do: nil

  def mission(%{tutorial?: true} = game) do
    case stage(game) do
      stage when stage in [:move, :cooldown] ->
        1

      stage when stage in [:capture_knight, :capture_knight_result] ->
        2

      stage
      when stage in [:sprint_pawn, :sprint_knight, :sprint_bishop, :sprint_rook, :sprint_result] ->
        3

      stage when stage in [:capture_pawn, :capture_pawn_result] ->
        4

      stage when stage in [:capture_queen, :complete] ->
        5
    end
  end

  def mission(_game), do: nil

  def after_move(%{tutorial?: true} = game, action) do
    case {stage(game), action.from, action.to} do
      {:move, @opening_from, @opening_to} ->
        Map.put(game, :tutorial_step, :cooldown)

      {:capture_knight, @opening_to, @opening_capture} ->
        Map.put(game, :tutorial_step, :capture_knight_result)

      {:capture_pawn, @capture_pawn_from, @capture_pawn_to} ->
        Map.put(game, :tutorial_step, :capture_pawn_result)

      {:capture_queen, @capture_queen_from, @capture_queen_to} ->
        Map.put(game, :tutorial_step, :complete)

      {sprint_stage, from, to}
      when sprint_stage in [:sprint_pawn, :sprint_knight, :sprint_bishop, :sprint_rook] ->
        if expected_action(game) == {from, to} do
          Map.put(game, :tutorial_step, next_sprint_stage(game, sprint_stage))
        else
          game
        end

      _other ->
        game
    end
  end

  def after_move(game, _action), do: game

  def acknowledge_cooldown(%{tutorial?: true, tutorial_step: :cooldown} = game),
    do: Map.put(game, :tutorial_step, :capture_knight)

  def acknowledge_cooldown(game), do: game

  def continue(%{tutorial?: true} = game, now_ms) do
    case stage(game) do
      :cooldown ->
        if cooldown_active?(game, @opening_to, now_ms) do
          game
        else
          game
          |> Map.put(:tutorial_step, :capture_knight)
          |> add_log("Cooldown listo. Captura el caballo de e4.")
        end

      :capture_knight_result ->
        prepare_sprint(game)

      :sprint_result ->
        prepare_capture_comparison(game)

      :capture_pawn_result ->
        game
        |> ensure_white_elixir(piece_cost(game.settings, :pawn))
        |> Map.put(:tutorial_step, :capture_queen)
        |> add_log("Compara la recompensa: captura la dama de e4.")

      _stage ->
        game
    end
  end

  def continue(game, _now_ms), do: game

  def prepare_initial(%{tutorial?: true} = game) do
    ensure_white_elixir(game, piece_cost(game.settings, :pawn))
  end

  def prepare_initial(game), do: game

  def cooldown_remaining_ms(%{cooldowns: cooldowns}) when is_list(cooldowns) do
    cooldowns
    |> Enum.find_value(0, fn cooldown ->
      if cooldown.at == @opening_to, do: max(cooldown.remaining_ms, 0)
    end)
  end

  def cooldown_remaining_ms(_game), do: 0

  def checkpoint?(%{tutorial?: true} = game) do
    stage(game) in [:cooldown, :capture_knight_result, :sprint_result, :capture_pawn_result]
  end

  def checkpoint?(_game), do: false

  def current_piece_type(%{tutorial?: true} = game) do
    case stage(game) do
      stage when stage in [:move, :cooldown, :capture_knight, :capture_pawn, :capture_queen] ->
        :pawn

      sprint_stage ->
        case Enum.find(@sprint_actions, &(&1.stage == sprint_stage)) do
          nil -> nil
          action -> action.piece
        end
    end
  end

  def current_piece_type(_game), do: nil

  def current_move_cost(%{tutorial?: true} = game) do
    case current_piece_type(game) do
      nil -> nil
      piece -> piece_cost(game.settings, piece)
    end
  end

  def current_move_cost(_game), do: nil

  def capture_reward(%{tutorial?: true} = game) do
    if stage(game) in [:cooldown, :capture_knight, :capture_pawn, :capture_queen] do
      with {row, col} <- target_square(game),
           piece when piece != "." <- GameRules.at(game.board, row, col),
           :black <- GameRules.color(piece) do
        refund(game.settings, piece_type(piece))
      else
        _other -> nil
      end
    end
  end

  def capture_reward(_game), do: nil

  def sprint_plan(settings) do
    max_elixir = setting(settings, :max_elixir, 10.0)

    {actions, total} =
      Enum.reduce(@sprint_actions, {[], 0.0}, fn action, {selected, spent} ->
        cost = piece_cost(settings, action.piece)

        if cost <= max_elixir and spent + cost <= max_elixir do
          {selected ++ [Map.put(action, :cost, cost)], spent + cost}
        else
          {selected, spent}
        end
      end)

    %{actions: actions, total: rounded(total)}
  end

  def sprint_progress(%{tutorial?: true} = game) do
    plan = sprint_plan(game.settings)

    current_index =
      Enum.find_index(plan.actions, &(&1.stage == stage(game))) ||
        if(stage(game) == :sprint_result, do: length(plan.actions), else: 0)

    %{current: min(current_index + 1, max(length(plan.actions), 1)), total: length(plan.actions)}
  end

  def sprint_progress(_game), do: %{current: 0, total: 0}

  def piece_cost(settings, piece), do: setting(settings, :costs, %{}) |> Map.get(piece, 0.0)

  def refund(settings, piece) do
    (piece_cost(settings, piece) * setting(settings, :capture_refund_percent, 0) / 100)
    |> rounded()
  end

  def square_name({row, col})
      when row in 0..7 and col in 0..7,
      do: "#{Enum.at(~w(a b c d e f g h), col)}#{8 - row}"

  def square_name(_square), do: ""

  defp inferred_stage(game) do
    cond do
      game.board == sprint_board() ->
        sprint_plan(game.settings).actions |> List.first() |> stage_or_result()

      game.board == capture_board() ->
        :capture_pawn

      GameRules.at(game.board, elem(@opening_to, 0), elem(@opening_to, 1)) == "P" ->
        if cooldown_at?(game, @opening_to), do: :cooldown, else: :capture_knight

      GameRules.at(game.board, elem(@opening_capture, 0), elem(@opening_capture, 1)) == "P" ->
        :capture_knight_result

      true ->
        :move
    end
  end

  def allowed_move?(%{tutorial?: true} = game, from, to) do
    case expected_action(game) do
      {expected_from, expected_to} -> from == expected_from and to == expected_to
      nil -> false
    end
  end

  def allowed_move?(_game, _from, _to), do: true

  def legal_moves(game, from, legal_moves) do
    if tutorial?(game) do
      Enum.filter(legal_moves, &allowed_move?(game, from, &1))
    else
      legal_moves
    end
  end

  def source_square(%{tutorial?: true} = game) do
    case {expected_action(game), stage(game)} do
      {{from, _to}, _stage} -> from
      {nil, :cooldown} -> @opening_to
      {nil, _stage} -> nil
    end
  end

  def source_square(_game), do: nil

  def target_square(%{tutorial?: true} = game) do
    case {expected_action(game), stage(game)} do
      {{_from, to}, _stage} -> to
      {nil, :cooldown} -> @opening_capture
      {nil, _stage} -> nil
    end
  end

  def target_square(_game), do: nil

  def square_role(game, square) do
    cond do
      source_square(game) == square -> :source
      target_square(game) == square -> :target
      true -> nil
    end
  end

  defp cooldown_at?(%{cooldowns: cooldowns}, square) when is_map(cooldowns),
    do: Map.has_key?(cooldowns, square)

  defp cooldown_at?(%{cooldowns: cooldowns}, square) when is_list(cooldowns),
    do: Enum.any?(cooldowns, &(&1.at == square))

  defp cooldown_at?(_game, _square), do: false

  defp expected_action(game) do
    case stage(game) do
      :move -> {@opening_from, @opening_to}
      :capture_knight -> {@opening_to, @opening_capture}
      :capture_pawn -> {@capture_pawn_from, @capture_pawn_to}
      :capture_queen -> {@capture_queen_from, @capture_queen_to}
      sprint_stage -> sprint_action(game.settings, sprint_stage)
    end
  end

  defp sprint_action(settings, sprint_stage) do
    settings
    |> sprint_plan()
    |> Map.fetch!(:actions)
    |> Enum.find_value(fn action ->
      if action.stage == sprint_stage, do: {action.from, action.to}
    end)
  end

  defp next_sprint_stage(game, current_stage) do
    stages = Enum.map(sprint_plan(game.settings).actions, & &1.stage)

    case Enum.find_index(stages, &(&1 == current_stage)) do
      nil -> :sprint_result
      index -> Enum.at(stages, index + 1, :sprint_result)
    end
  end

  defp prepare_sprint(game) do
    plan = sprint_plan(game.settings)
    next_stage = plan.actions |> List.first() |> stage_or_result()

    game
    |> prepare_board(sprint_board(), plan.total, next_stage)
    |> add_log(
      "Prueba de costes: encadena #{length(plan.actions)} piezas distintas y compara el gasto."
    )
  end

  defp prepare_capture_comparison(game) do
    pawn_cost = piece_cost(game.settings, :pawn)
    budget = min(setting(game.settings, :max_elixir, pawn_cost), pawn_cost * 2)

    game
    |> prepare_board(capture_board(), budget, :capture_pawn)
    |> add_log("Comparacion de capturas: primero captura el peon de d4.")
  end

  defp prepare_board(game, board, white_elixir, next_stage) do
    %{
      game
      | board: board,
        castling_rights: castling_rights(),
        cooldowns: %{},
        queue: [],
        promotion_pending: nil,
        first_move_pending: nil,
        status: :playing
    }
    |> Map.put(:tutorial_step, next_stage)
    |> Map.put(:last_capture_refund, nil)
    |> put_in([:elixir, :white], rounded(white_elixir))
  end

  defp ensure_white_elixir(game, required) do
    max_elixir = setting(game.settings, :max_elixir, required)
    available = get_in(game, [:elixir, :white]) || 0
    put_in(game, [:elixir, :white], rounded(min(max_elixir, max(available, required))))
  end

  defp cooldown_active?(%{cooldowns: cooldowns}, square, now_ms) when is_map(cooldowns) do
    case Map.get(cooldowns, square) do
      ready_at when is_number(ready_at) -> ready_at > now_ms
      _ready_at -> false
    end
  end

  defp cooldown_active?(%{cooldowns: cooldowns}, square, _now_ms) when is_list(cooldowns) do
    Enum.any?(cooldowns, &(&1.at == square and &1.remaining_ms > 0))
  end

  defp cooldown_active?(_game, _square, _now_ms), do: false

  defp stage_or_result(nil), do: :sprint_result
  defp stage_or_result(action), do: action.stage

  defp piece_type(piece) do
    case String.downcase(piece) do
      "p" -> :pawn
      "n" -> :knight
      "b" -> :bishop
      "r" -> :rook
      "q" -> :queen
      "k" -> :king
    end
  end

  defp setting(settings, key, fallback), do: Map.get(settings, key, fallback)

  defp rounded(value) when is_integer(value), do: value * 1.0
  defp rounded(value) when is_float(value), do: Float.round(value, 2)

  defp add_log(game, message), do: update_in(game.log, &[message | &1])
end
