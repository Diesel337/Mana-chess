defmodule ManaChessOnline.GameTutorial do
  @moduledoc false

  alias ManaChessOnline.GameRules

  @opening_from {6, 3}
  @opening_to {5, 3}
  @capture_to {4, 4}

  def board do
    [
      [".", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "p", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", "P", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]
  end

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
      step when step in [:move, :cooldown, :capture, :complete] -> step
      _step -> inferred_stage(game)
    end
  end

  def stage(_game), do: nil

  def after_move(%{tutorial?: true} = game, %{from: @opening_from, to: @opening_to}),
    do: Map.put(game, :tutorial_step, :cooldown)

  def after_move(%{tutorial?: true} = game, %{from: @opening_to, to: @capture_to}),
    do: Map.put(game, :tutorial_step, :complete)

  def after_move(game, _action), do: game

  def acknowledge_cooldown(%{tutorial?: true, tutorial_step: :cooldown} = game),
    do: Map.put(game, :tutorial_step, :capture)

  def acknowledge_cooldown(game), do: game

  def cooldown_remaining_ms(%{cooldowns: cooldowns}) when is_list(cooldowns) do
    cooldowns
    |> Enum.find_value(0, fn cooldown ->
      if cooldown.at == @opening_to, do: max(cooldown.remaining_ms, 0)
    end)
  end

  def cooldown_remaining_ms(_game), do: 0

  defp inferred_stage(game) do
    cond do
      GameRules.at(game.board, elem(@capture_to, 0), elem(@capture_to, 1)) == "P" ->
        :complete

      GameRules.at(game.board, elem(@opening_to, 0), elem(@opening_to, 1)) == "P" ->
        if cooldown_at?(game, @opening_to), do: :cooldown, else: :capture

      true ->
        :move
    end
  end

  def allowed_move?(%{tutorial?: true} = game, from, to) do
    case stage(game) do
      :move -> from == @opening_from and to == @opening_to
      :capture -> from == @opening_to and to == @capture_to
      :cooldown -> false
      :complete -> false
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
    case stage(game) do
      :move -> @opening_from
      stage when stage in [:cooldown, :capture] -> @opening_to
      _stage -> nil
    end
  end

  def source_square(_game), do: nil

  def target_square(%{tutorial?: true} = game) do
    case stage(game) do
      :move -> @opening_to
      stage when stage in [:cooldown, :capture] -> @capture_to
      _stage -> nil
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
end
