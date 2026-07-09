defmodule ManaChessOnline.GameBroadcastTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameBroadcast

  test "requires game updates when public snapshots differ" do
    refute GameBroadcast.game_update_needed?(%{status: :waiting}, %{status: :waiting}, %{
             status: :waiting
           })

    assert GameBroadcast.game_update_needed?(%{status: :waiting}, %{status: :playing}, %{
             status: :playing,
             cooldowns: %{}
           })
  end

  test "keeps broadcasting visible countdowns and cooldowns" do
    assert GameBroadcast.game_update_needed?(%{}, %{}, %{status: {:starting, 1_000}})

    assert GameBroadcast.game_update_needed?(%{}, %{}, %{
             status: :playing,
             cooldowns: %{{6, 4} => 1_000}
           })
  end

  test "requires lobby updates when lobby snapshots differ or a countdown is visible" do
    refute GameBroadcast.lobby_update_needed?([%{id: "game_1"}], [%{id: "game_1"}], %{
             "game_1" => %{status: :waiting}
           })

    assert GameBroadcast.lobby_update_needed?([%{id: "game_1"}], [%{id: "game_2"}], %{
             "game_1" => %{status: :waiting}
           })

    assert GameBroadcast.lobby_update_needed?([%{id: "game_1"}], [%{id: "game_1"}], %{
             "game_1" => %{status: {:starting, 1_000}}
           })
  end
end
