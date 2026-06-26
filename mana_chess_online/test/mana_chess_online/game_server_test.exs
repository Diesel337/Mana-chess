defmodule ManaChessOnline.GameServerTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameRules, GameServer, GameState}

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

  test "keeps an isolated game snapshot and supports pure state updates" do
    game = GameState.new_game("server_test_1", settings())
    {:ok, pid} = start_supervised({GameServer, game: game, id: {:game_server_test, 1}})

    assert GameServer.snapshot(pid).id == "server_test_1"

    updated = GameServer.update(pid, &%{&1 | log: ["Actualizado." | &1.log]})

    assert hd(updated.log) == "Actualizado."
    assert GameServer.snapshot(pid).log == updated.log
  end

  test "enqueues and processes a move inside the game process" do
    game =
      GameState.practice_game("server_practice_1", "player-1", settings(), 1_000, 1_200)
      |> Map.put(:bot_enabled?, false)

    {:ok, pid} = start_supervised({GameServer, game: game, id: {:game_server_test, 2}})

    game =
      GameServer.enqueue(
        pid,
        %{player_id: "player-1", color: :white, from: {6, 4}, to: {4, 4}},
        10_000
      )

    assert GameRules.at(game.board, 6, 4) == "."
    assert GameRules.at(game.board, 4, 4) == "P"
    assert game.elixir.white == 4.0
    assert game.cooldowns == %{{4, 4} => 11_000}
    assert GameServer.snapshot(pid).board == game.board
  end

  test "ticks cooldown cleanup and elixir regeneration in one process cycle" do
    game =
      GameState.new_game("server_test_2", settings())
      |> Map.put(:status, :playing)
      |> Map.put(:first_move_pending, nil)
      |> Map.put(:elixir, %{white: 5.0, black: 9.95})
      |> Map.put(:cooldowns, %{{6, 4} => 1_000, {6, 5} => 1_500})

    {:ok, pid} =
      start_supervised({GameServer, game: game, id: {:game_server_test, 3}, tick_ms: 250})

    game = GameServer.tick(pid, 1_000)

    assert game.cooldowns == %{{6, 5} => 1_500}
    assert game.elixir == %{white: 5.25, black: 10.0}
  end
end
