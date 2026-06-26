defmodule ManaChessOnline.GameEngineTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameEngine, GameRules, GameState}

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

  test "processes a queued move with elixir spend, cooldown and first move clear" do
    game =
      GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:bot_enabled?, false)
      |> Map.put(:queue, [%{player_id: "player-1", color: :white, from: {6, 4}, to: {4, 4}}])

    game = GameEngine.process_next_action(game, 10_000, 1.0)

    assert GameRules.at(game.board, 6, 4) == "."
    assert GameRules.at(game.board, 4, 4) == "P"
    assert game.queue == []
    assert game.first_move_pending == nil
    assert game.elixir.white == 4.0
    assert game.cooldowns == %{{4, 4} => 11_000}
    assert hd(game.log) == "Blancas movio peon e2 -> e4."
  end

  test "logs captures with piece and algebraic squares" do
    board = [
      [".", ".", ".", ".", "k", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "p", ".", ".", "."],
      [".", ".", ".", "P", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", ".", ".", ".", "."],
      [".", ".", ".", ".", "K", ".", ".", "."]
    ]

    game =
      GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:bot_enabled?, false)
      |> Map.put(:board, board)
      |> Map.put(:queue, [%{player_id: "player-1", color: :white, from: {4, 3}, to: {3, 4}}])

    game = GameEngine.process_next_action(game, 10_000, 1.0)

    assert GameRules.at(game.board, 4, 3) == "."
    assert GameRules.at(game.board, 3, 4) == "P"
    assert hd(game.log) == "Blancas movio peon d4 -> e5 y capturo peon."
  end

  test "discards queued moves when elixir is not enough" do
    game =
      GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:elixir, %{white: 0.0, black: 5.0})
      |> Map.put(:queue, [%{player_id: "player-1", color: :white, from: {6, 4}, to: {4, 4}}])

    game = GameEngine.process_next_action(game, 10_000, 1.0)

    assert GameRules.at(game.board, 6, 4) == "P"
    assert GameRules.at(game.board, 4, 4) == "."
    assert game.queue == []
    assert hd(game.log) == "Sin elixir para Blancas."
  end

  test "regenerates elixir only after the opening move has happened" do
    waiting_for_first_move =
      GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:elixir, %{white: 5.0, black: 9.95})

    active = %{waiting_for_first_move | first_move_pending: nil}

    assert GameEngine.regen_elixir(waiting_for_first_move, 250).elixir == %{
             white: 5.0,
             black: 9.95
           }

    assert GameEngine.regen_elixir(active, 250).elixir == %{white: 5.25, black: 10.0}
  end

  test "clears expired cooldowns and reports active ones" do
    game =
      GameState.new_game("game_1", settings())
      |> Map.put(:cooldowns, %{{6, 4} => 1_000, {6, 5} => 1_500})

    game = GameEngine.clear_expired_cooldowns(game, 1_000)

    refute GameEngine.cooldown_active?(game, {6, 4}, 1_000)
    assert GameEngine.cooldown_active?(game, {6, 5}, 1_000)
    assert game.cooldowns == %{{6, 5} => 1_500}
  end

  test "terminal status is nil for the initial board" do
    game = GameState.new_game("game_1", settings())

    assert GameEngine.terminal_status(game.board, game.castling_rights) == nil
  end
end
