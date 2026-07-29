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

  test "guides a full mana, cooldown, sprint and capture comparison" do
    game = GameState.tutorial_game("tutorial_1", "player-1", settings())

    assert GameTutorial.stage(game) == :move
    assert GameTutorial.mission(game) == 1
    assert GameTutorial.source_square(game) == {6, 3}
    assert GameTutorial.target_square(game) == {5, 3}
    assert GameTutorial.allowed_move?(game, {6, 3}, {5, 3})
    refute GameTutorial.allowed_move?(game, {6, 3}, {4, 3})

    game = move(game, {6, 3}, {5, 3}, 1_000)

    assert GameTutorial.stage(game) == :cooldown
    assert game.elixir.white == 4.0

    public_after_cooldown = GameState.public_game(game, 2_100, 1.0)
    assert GameTutorial.stage(public_after_cooldown) == :cooldown

    game =
      game
      |> GameEngine.clear_expired_cooldowns(2_100)
      |> GameEngine.regen_elixir(1_000)
      |> GameTutorial.continue(2_100)

    assert GameTutorial.stage(game) == :capture_knight
    assert GameTutorial.capture_reward(game) == 1.2

    game = move(game, {5, 3}, {4, 4}, 2_100)

    assert GameTutorial.stage(game) == :capture_knight_result
    assert GameRules.at(game.board, 4, 4) == "P"
    assert game.elixir.white == 5.2
    assert game.last_capture_refund == 1.2
    assert hd(game.log) == "Blancas movio peon d3 -> e4 y capturo caballo."

    game = GameTutorial.continue(game, 2_200)

    assert GameTutorial.stage(game) == :sprint_pawn
    assert GameTutorial.mission(game) == 3
    assert game.board == GameTutorial.sprint_board()
    assert game.elixir.white == 7.0

    assert Enum.map(GameTutorial.sprint_plan(game.settings).actions, & &1.stage) == [
             :sprint_pawn,
             :sprint_knight,
             :sprint_bishop
           ]

    game = move(game, {6, 1}, {5, 1}, 3_000)
    assert GameTutorial.stage(game) == :sprint_knight
    assert game.elixir.white == 6.0

    game = move(game, {6, 3}, {4, 4}, 3_100)
    assert GameTutorial.stage(game) == :sprint_bishop
    assert game.elixir.white == 3.0

    game = move(game, {7, 5}, {4, 2}, 3_200)
    assert GameTutorial.stage(game) == :sprint_result
    assert game.elixir.white == 0.0

    game = GameTutorial.continue(game, 3_300)

    assert GameTutorial.stage(game) == :capture_pawn
    assert game.board == GameTutorial.capture_board()
    assert game.elixir.white == 2.0
    assert GameTutorial.capture_reward(game) == 0.4

    game = move(game, {5, 2}, {4, 3}, 4_000)

    assert GameTutorial.stage(game) == :capture_pawn_result
    assert game.last_capture_refund == 0.4
    assert game.elixir.white == 1.4

    game = GameTutorial.continue(game, 4_100)

    assert GameTutorial.stage(game) == :capture_queen
    assert GameTutorial.capture_reward(game) == 2.4

    game = move(game, {5, 5}, {4, 4}, 4_200)

    assert GameTutorial.stage(game) == :complete
    assert GameTutorial.mission(game) == 5
    assert GameRules.at(game.board, 4, 3) == "P"
    assert GameRules.at(game.board, 4, 4) == "P"
    assert game.last_capture_refund == 2.4
    assert game.elixir.white == 2.8
  end

  test "builds a sprint whose configured costs fit exactly inside the mana cap" do
    settings = %{settings() | max_elixir: 7.0}
    plan = GameTutorial.sprint_plan(settings)

    assert Enum.map(plan.actions, & &1.piece) == [:pawn, :knight, :bishop]
    assert plan.total == 7.0

    settings = %{settings | max_elixir: 5.0}
    plan = GameTutorial.sprint_plan(settings)

    assert Enum.map(plan.actions, & &1.piece) == [:pawn, :knight]
    assert plan.total == 4.0
  end

  defp move(game, from, to, now_ms) do
    game
    |> Map.put(:queue, [
      %{player_id: "player-1", color: :white, from: from, to: to}
    ])
    |> GameEngine.process_next_action(now_ms, 1.0)
  end
end
