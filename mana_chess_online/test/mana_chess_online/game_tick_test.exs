defmodule ManaChessOnline.GameTickTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameRules, GameState, GameTick}

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

  test "finishes countdown when its start time has arrived" do
    game =
      GameState.new_game("game_1", settings())
      |> Map.put(:status, {:starting, 5_000})
      |> Map.put(:start_requests, MapSet.new(["white", "black"]))

    game = GameTick.finish_countdown(game, 5_000)

    assert game.status == :playing
    assert game.start_requests == MapSet.new()
    assert hd(game.log) == "Partida iniciada. Blancas abren."
  end

  test "starts immediately when every seated player is ready" do
    game =
      GameState.new_game("game_1", settings())
      |> Map.put(:status, {:starting, 5_000})
      |> Map.put(:start_requests, MapSet.new(["white", "black"]))

    game = GameTick.start_when_ready(game, ["white", "black"])

    assert game.status == :playing
  end

  test "tick runs cooldown cleanup, elixir regeneration and queued actions" do
    game =
      GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:bot_enabled?, false)
      |> Map.put(:first_move_pending, nil)
      |> Map.put(:elixir, %{white: 5.0, black: 9.95})
      |> Map.put(:cooldowns, %{{6, 4} => 1_000})
      |> Map.put(:queue, [%{player_id: "player-1", color: :white, from: {6, 4}, to: {5, 4}}])

    game = GameTick.tick(game, 1_000, 250, 1.0)

    assert GameRules.at(game.board, 6, 4) == "."
    assert GameRules.at(game.board, 5, 4) == "P"
    assert game.elixir == %{white: 4.25, black: 10.0}
    assert game.cooldowns == %{{5, 4} => 2_000}
  end
end
