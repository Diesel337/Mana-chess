defmodule ManaChessOnline.CompetitiveMatchmakingTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{CompetitiveMatchmaking, GameRooms}

  test "prefers the closest waiting opponent over an empty room" do
    games = %{
      "game_1" => waiting_game("game_1", "far-player"),
      "game_2" => waiting_game("game_2", "near-player"),
      "game_3" => GameRooms.new_game("game_3", settings())
    }

    ratings = %{"far-player" => 1_700, "near-player" => 1_245}

    assert CompetitiveMatchmaking.find_open_slot(games, ratings, 1_220) ==
             {"game_2", :black}
  end

  test "uses the first empty public room when nobody is waiting" do
    games = %{
      "game_2" => GameRooms.new_game("game_2", settings()),
      "game_1" => GameRooms.new_game("game_1", settings())
    }

    assert CompetitiveMatchmaking.find_open_slot(games, %{}, 1_200) ==
             {"game_1", :white}
  end

  defp waiting_game(game_id, player_id) do
    game_id
    |> GameRooms.new_game(settings())
    |> put_in([:players, :white], player_id)
  end

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end
end
