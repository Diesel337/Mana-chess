defmodule ManaChessOnline.GamePersistence do
  @moduledoc false

  alias ManaChessOnline.{GameEngine, Persistence}

  def observe(previous_game, next_game) do
    if not terminal?(previous_game) and terminal?(next_game) do
      Persistence.record_match(next_game)
    end

    next_game
  end

  def terminal?(%{status: status}), do: GameEngine.terminal_status?(status)
  def terminal?(_game), do: false
end
