defmodule ManaChessOnline.GameBroadcastTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameBroadcast, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

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

  test "broadcasts public game updates" do
    topic = "test_game:" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game("game_broadcast", settings())

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, topic)

    assert :ok = GameBroadcast.game_update(topic, game, 1_000)
    assert_receive {:game_update, %{id: "game_broadcast", status: :waiting}}
  end

  test "broadcasts public live lobby updates" do
    topic = "test_lobby:" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game("game_broadcast_lobby", settings())
    state = %{games: %{game.id => game}}

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, topic)

    assert :ok = GameBroadcast.lobby_update(topic, state, 1_000)
    assert_receive {:lobby_update, lobby}
    assert Enum.any?(lobby, &(&1.id == game.id))
  end
end
