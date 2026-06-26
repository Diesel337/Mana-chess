defmodule ManaChessOnline.GameStateTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameState

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.25,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "builds a waiting game with default public-safe state" do
    game = GameState.new_game("game_test", settings())

    assert game.id == "game_test"
    assert game.players == %{white: nil, black: nil}
    assert game.practice? == false
    assert game.private? == false
    assert game.elixir == %{white: 5.0, black: 5.0}
    assert game.status == :waiting
    assert game.log == ["Esperando jugadores..."]
  end

  test "builds practice and private game variants" do
    practice = GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
    private = GameState.private_game("private_1", settings())

    assert practice.practice?
    assert practice.bot_enabled?
    assert practice.bot_ready_at == 2_200
    assert practice.players == %{white: "player-1", black: "player-1"}
    assert practice.status == :playing

    assert private.private?
    assert private.practice? == false
    assert private.log == ["Sala privada creada. Comparte el link para invitar."]
  end

  test "public snapshots trim logs and expose countdowns and cooldowns" do
    game =
      GameState.new_game("game_test", settings())
      |> Map.put(:status, {:starting, 15_000})
      |> Map.put(:log, Enum.map(1..12, &"log #{&1}"))
      |> Map.put(:cooldowns, %{{6, 4} => 12_500})

    public = GameState.public_game(game, 10_000, 1.0)

    assert public.countdown_seconds == 5
    assert length(public.log) == 8
    assert [%{at: {6, 4}, seconds: 3, remaining_ms: 2_500, total_ms: 1_250}] = public.cooldowns
  end

  test "public lobby excludes practice and private games" do
    state = %{
      games: %{
        "game_1" => GameState.new_game("game_1", settings()),
        "private_1" => GameState.private_game("private_1", settings()),
        "practice_1" =>
          GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200)
      }
    }

    assert [%{id: "game_1", countdown_seconds: nil}] = GameState.public_lobby(state, 1_000)
  end
end
