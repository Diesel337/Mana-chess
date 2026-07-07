defmodule ManaChessOnline.GameRoomsTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameRooms

  test "builds stable practice game ids" do
    assert GameRooms.practice_game_id("player-1") == GameRooms.practice_game_id("player-1")
    assert String.starts_with?(GameRooms.practice_game_id("player-1"), "practice_")
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

  test "generates unique private ids outside existing games" do
    games = Map.new(1..20, fn n -> {"private_existing_#{n}", %{}} end)
    game_id = GameRooms.unique_private_game_id(games)

    assert GameRooms.private_game_id?(game_id)
    refute Map.has_key?(games, game_id)
  end
end
