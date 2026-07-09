defmodule ManaChessOnline.GameRoomsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameRooms, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "builds stable practice game ids" do
    assert GameRooms.practice_game_id("player-1") == GameRooms.practice_game_id("player-1")
    assert String.starts_with?(GameRooms.practice_game_id("player-1"), "practice_")
  end

  test "builds room game states" do
    assert GameRooms.new_game("game_1", settings()).id == "game_1"
    assert GameRooms.private_game("private_1", settings()).private? == true

    practice = GameRooms.practice_game("practice_1", "player", settings(), 10, 1_200, :white)
    assert practice.practice? == true
    assert practice.bot_color == :white
  end

  test "validates private game ids" do
    assert GameRooms.private_game_id?("private_abcdef")
    refute GameRooms.private_game_id?("private_short")
    refute GameRooms.private_game_id?("game_1")
    refute GameRooms.private_game_id?(nil)
  end

  test "detects empty private games" do
    assert GameRooms.empty_private_game?(%{
             private?: true,
             players: %{white: nil, black: nil}
           })

    refute GameRooms.empty_private_game?(%{
             private?: true,
             players: %{white: "player", black: nil}
           })

    refute GameRooms.empty_private_game?(%{
             private?: false,
             players: %{white: nil, black: nil}
           })
  end

  test "detects public lobby games" do
    assert GameRooms.public_lobby_game?(%{practice?: false, private?: false})
    refute GameRooms.public_lobby_game?(%{practice?: false, private?: true})
    refute GameRooms.public_lobby_game?(%{practice?: true, private?: false})
    refute GameRooms.public_lobby_game?(nil)
  end

  test "checks reset readiness from seated players" do
    game =
      GameState.new_game("game_1", settings())
      |> put_in([:players, :white], "white")
      |> put_in([:players, :black], "black")
      |> Map.put(:reset_requests, MapSet.new(["white"]))

    refute GameRooms.reset_ready?(game, "white")
    assert GameRooms.reset_ready?(game, "black")
  end

  test "checks whether a player may clear a room" do
    game =
      GameState.new_game("game_1", settings())
      |> put_in([:players, :white], "white")
      |> put_in([:players, :black], "black")

    assert GameRooms.can_clear_room?(%{game_id: "game_1", color: :white}, "white", "game_1", game)
    refute GameRooms.can_clear_room?(%{game_id: "game_1", color: nil}, "white", "game_1", game)
    refute GameRooms.can_clear_room?(%{game_id: "game_2", color: :white}, "white", "game_1", game)
    refute GameRooms.can_clear_room?(nil, "white", "game_1", game)
  end

  test "generates unique private ids outside existing games" do
    games = Map.new(1..20, fn n -> {"private_existing_#{n}", %{}} end)
    game_id = GameRooms.unique_private_game_id(games)

    assert GameRooms.private_game_id?(game_id)
    refute Map.has_key?(games, game_id)
  end

  test "builds cleared and reset room states from room type" do
    public = GameState.new_game("game_1", settings())
    private = GameState.private_game("private_1", settings())

    assert GameRooms.cleared_game_state("game_1", public).private? == false
    assert GameRooms.reset_room_state("game_1", public).players == %{white: nil, black: nil}
    assert GameRooms.cleared_game_state("private_1", private).private? == true
    assert GameRooms.reset_room_state("private_1", private).private? == true
  end

  test "preserves disabled practice bot state" do
    next_game = GameState.practice_game("practice_1", "player", settings(), 0, 1_200)
    previous_game = %{bot_enabled?: false}

    assert %{bot_enabled?: false, bot_ready_at: nil} =
             GameRooms.preserve_practice_bot_state(next_game, previous_game)

    assert GameRooms.preserve_practice_bot_state(next_game, %{}) == next_game
  end
end
