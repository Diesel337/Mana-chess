defmodule ManaChessOnline.GameMetricsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameMetrics, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "summarizes game and runtime health" do
    public_game = GameState.new_game("game_1", settings())
    private_game = %{GameState.private_game("private_1", settings()) | status: :ready}
    practice_game = GameState.practice_game("practice_1", "player", settings(), 0, 1_000)

    metrics =
      GameMetrics.snapshot(
        %{
          public_game.id => public_game,
          private_game.id => private_game,
          practice_game.id => practice_game
        },
        [self()],
        %{active: 3},
        %{{:chat, "player"} => [0]},
        123
      )

    assert metrics.measured_at_ms == 123
    assert metrics.game_count == 3
    assert metrics.public_game_count == 1
    assert metrics.private_game_count == 1
    assert metrics.practice_game_count == 1
    assert metrics.waiting_game_count == 1
    assert metrics.ready_game_count == 1
    assert metrics.playing_game_count == 1
    assert metrics.bot_game_count == 1
    assert metrics.rate_limit_bucket_count == 1
    assert metrics.game_server_count == 3
    assert metrics.game_server_memory_kb > 0
    assert metrics.process_count > 0
    assert metrics.memory_total_kb > 0
    assert is_integer(metrics.run_queue)
  end
end
