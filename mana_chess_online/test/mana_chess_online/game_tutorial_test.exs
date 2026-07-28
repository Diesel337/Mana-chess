defmodule ManaChessOnline.GameTutorialTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameEngine, GameRules, GameState, GameTutorial}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      regen_per_second: 1.0,
      capture_refund_percent: 40,
      cooldown_enabled: true,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "guides the opening, cooldown and capture stages with real game rules" do
    game = GameState.tutorial_game("tutorial_1", "player-1", settings())

    assert GameTutorial.stage(game) == :move
    assert GameTutorial.source_square(game) == {6, 3}
    assert GameTutorial.target_square(game) == {5, 3}
    assert GameTutorial.allowed_move?(game, {6, 3}, {5, 3})
    refute GameTutorial.allowed_move?(game, {6, 3}, {4, 3})

    game =
      game
      |> Map.put(:queue, [
        %{player_id: "player-1", color: :white, from: {6, 3}, to: {5, 3}}
      ])
      |> GameEngine.process_next_action(1_000, 1.0)

    assert GameTutorial.stage(game) == :cooldown
    assert game.elixir.white == 4.0

    public_after_cooldown = GameState.public_game(game, 2_100, 1.0)
    assert GameTutorial.stage(public_after_cooldown) == :cooldown

    game =
      game
      |> GameEngine.clear_expired_cooldowns(2_100)
      |> GameEngine.regen_elixir(1_000)
      |> GameTutorial.acknowledge_cooldown()
      |> Map.put(:queue, [
        %{player_id: "player-1", color: :white, from: {5, 3}, to: {4, 4}}
      ])
      |> GameEngine.process_next_action(2_100, 1.0)

    assert GameTutorial.stage(game) == :complete
    assert GameRules.at(game.board, 4, 4) == "P"
    assert game.elixir.white == 4.4
    assert hd(game.log) == "Blancas movio peon d3 -> e4 y capturo peon."
  end
end
