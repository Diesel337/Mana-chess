defmodule ManaChessOnline.GamePlayersTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GamePlayers

  test "assigns and reads player assignments" do
    state = %{players: %{}}

    state = GamePlayers.assign(state, "player", "game_1", :white)

    assert GamePlayers.assignment(state, "player") == %{game_id: "game_1", color: :white}
    assert GamePlayers.assignment_or_empty(state, "missing") == %{game_id: nil, color: nil}
  end

  test "removes one or many player assignments" do
    state = %{
      players: %{
        "one" => %{game_id: "game_1", color: :white},
        "two" => %{game_id: "game_1", color: :black},
        "three" => %{game_id: "game_2", color: :white}
      }
    }

    state = GamePlayers.remove(state, "one")
    refute Map.has_key?(state.players, "one")

    state = GamePlayers.remove_many(state, ["two", "missing"])
    refute Map.has_key?(state.players, "two")
    assert Map.has_key?(state.players, "three")
  end

  test "keeps assignments only for present player ids" do
    state = %{players: %{}}

    assert GamePlayers.keep_assignment_if_present(state, nil, "game_1", :white) == state

    state = GamePlayers.keep_assignment_if_present(state, "player", "game_1", :white)
    assert GamePlayers.assignment(state, "player") == %{game_id: "game_1", color: :white}
  end
end
