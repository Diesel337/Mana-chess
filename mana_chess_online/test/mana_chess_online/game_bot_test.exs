defmodule ManaChessOnline.GameBotTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameBot, GameBotDifficulty, GameEngine, GameRules, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 8.0,
      regen_per_second: 1.0,
      capture_refund_percent: 40,
      cooldown_enabled: true,
      cooldown_seconds: 1.0,
      bot_move_seconds: 1.2,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "exposes three distinct difficulty profiles" do
    assert GameBot.difficulties() == [:apprentice, :normal, :expert]
    assert GameBotDifficulty.profile(:apprentice).search_depth == 2
    assert GameBotDifficulty.profile(:normal).search_depth == 4
    assert GameBotDifficulty.profile(:expert).search_depth == 5
    assert GameBotDifficulty.profile(:apprentice).choice_pool == 3

    assert GameBotDifficulty.profile(:expert).resource_weight >
             GameBotDifficulty.profile(:normal).resource_weight
  end

  test "uses level-specific move delays" do
    assert GameBot.move_delay_ms(settings(), :apprentice) == 900
    assert GameBot.move_delay_ms(settings(), :normal) == 1_200
    assert GameBot.move_delay_ms(settings(), :expert) == 1_620
  end

  test "normalizes untrusted difficulty values without creating atoms" do
    assert GameBot.parse_difficulty("apprentice") == {:ok, :apprentice}
    assert GameBot.parse_difficulty("expert") == {:ok, :expert}
    assert GameBot.parse_difficulty("grandmaster") == :error
    assert GameBot.difficulty(%{bot_difficulty: "unknown"}) == :normal
  end

  test "never moves a piece while its cooldown is active" do
    cooldowns =
      for row <- 0..1, col <- 0..7, into: %{} do
        {{row, col}, 5_000}
      end

    game =
      GameState.practice_game("bot-cooldown", "player", settings(), 0, 0)
      |> Map.put(:first_move_pending, nil)
      |> Map.put(:cooldowns, cooldowns)

    assert GameBot.action(game, 1_000) == nil
  end

  test "every level returns a legal and affordable action" do
    for difficulty <- GameBot.difficulties() do
      game =
        GameState.practice_game(
          "bot-#{difficulty}",
          "player",
          settings(),
          0,
          0,
          :black,
          difficulty
        )
        |> Map.put(:first_move_pending, nil)

      action = GameBot.action(game, 1_000)
      piece = GameRules.at(game.board, elem(action.from, 0), elem(action.from, 1))

      assert action.color == :black

      assert action.to in GameRules.legal_moves_for(
               game.board,
               elem(action.from, 0),
               elem(action.from, 1),
               :black,
               game.castling_rights
             )

      assert game.elixir.black >= GameEngine.piece_cost(settings(), piece)
    end
  end
end
