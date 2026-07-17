defmodule ManaChessOnline.GameDirectoryTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameDirectory, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "returns public games sorted and excludes private and practice games" do
    games = %{
      "game_2" => GameState.new_game("game_2", settings()),
      "private_1" => GameState.private_game("private_1", settings()),
      "practice_1" => GameState.practice_game("practice_1", "player-1", settings(), 1_000, 1_200),
      "match_1" => GameState.matchmaking_game("match_1", settings()),
      "game_1" => GameState.new_game("game_1", settings())
    }

    assert Enum.map(GameDirectory.public_games(games), fn {game_id, _game} -> game_id end) == [
             "game_1",
             "game_2",
             "match_1"
           ]

    assert Enum.map(GameDirectory.lobby_games(games), fn {game_id, _game} -> game_id end) == [
             "game_1",
             "game_2"
           ]
  end

  test "finds the first open public slot" do
    games = %{
      "game_1" => %{
        GameState.new_game("game_1", settings())
        | players: %{white: "w1", black: "b1"}
      },
      "game_2" => %{
        GameState.new_game("game_2", settings())
        | players: %{white: "w2", black: nil}
      },
      "private_1" => GameState.private_game("private_1", settings())
    }

    assert GameDirectory.find_open_slot(games) == {"game_2", :black}
  end

  test "finds white before black in an empty public game" do
    games = %{"game_1" => GameState.new_game("game_1", settings())}

    assert GameDirectory.find_open_slot(games) == {"game_1", :white}
  end

  test "reports seated players without duplicates" do
    game = %{GameState.new_game("game_1", settings()) | players: %{white: "same", black: "same"}}

    assert GameDirectory.seated_players(game) == ["same"]
  end

  test "keeps existing empty waiting game semantics" do
    game = GameState.new_game("game_1", settings())
    private = GameState.private_game("private_1", settings())
    playing = %{game | status: :playing}

    assert GameDirectory.empty_waiting_game?(game)
    assert GameDirectory.empty_waiting_game?(private)
    refute GameDirectory.empty_waiting_game?(playing)
  end
end
