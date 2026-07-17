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

  test "builds shared pubsub topics" do
    assert GameBroadcast.game_topic("game_1") == "game:game_1"
    assert GameBroadcast.lobby_topic() == "lobby"
  end

  test "requires game updates from raw games and public snapshot builders" do
    previous_game = %{id: "game_1", status: :waiting, cooldowns: %{}}
    next_game = %{id: "game_1", status: :playing, cooldowns: %{}}
    public_game = fn game, _now -> %{id: game.id, status: game.status} end

    assert GameBroadcast.game_update_needed?(previous_game, next_game, 1_000, public_game)
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

    refute GameBroadcast.lobby_update_needed?([%{id: "game_1"}], [%{id: "game_1"}], %{
             "match_1" => %{
               practice?: false,
               private?: false,
               matchmaking?: true,
               status: {:starting, 1_000}
             }
           })
  end

  test "requires lobby updates from raw states and public lobby builders" do
    previous_state = %{games: %{"game_1" => %{id: "game_1", status: :waiting}}}
    next_state = %{games: %{"game_1" => %{id: "game_1", status: {:starting, 1_000}}}}
    public_lobby = fn state, _now -> Enum.map(state.games, fn {id, _game} -> %{id: id} end) end

    assert GameBroadcast.lobby_update_needed?(previous_state, next_state, 1_000, public_lobby)
  end

  test "broadcasts public game updates" do
    topic = "test_game:" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameState.new_game("game_broadcast", settings())

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, topic)

    assert :ok = GameBroadcast.game_update(topic, game, 1_000)
    assert_receive {:game_update, %{id: "game_broadcast", status: :waiting}}
  end

  test "broadcasts prebuilt public game payloads" do
    topic = "test_game_payload:" <> Integer.to_string(System.unique_integer([:positive]))
    payload = %{id: "game_payload", status: :ready}

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, topic)

    assert :ok = GameBroadcast.game_payload_update(topic, payload)
    assert_receive {:game_update, ^payload}
  end

  test "broadcasts prebuilt public game payloads by game id" do
    game_id = "test_game_payload_for_" <> Integer.to_string(System.unique_integer([:positive]))
    payload = %{id: game_id, status: :ready}

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameBroadcast.game_topic(game_id))

    assert :ok = GameBroadcast.game_payload_update_for(game_id, payload)
    assert_receive {:game_update, ^payload}
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

  test "broadcasts public live lobby updates on the shared lobby topic" do
    game = GameState.new_game("game_broadcast_lobby_topic", settings())
    state = %{games: %{game.id => game}}

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameBroadcast.lobby_topic())

    assert :ok = GameBroadcast.lobby_update(state, 1_000)
    assert_receive {:lobby_update, lobby}
    assert Enum.any?(lobby, &(&1.id == game.id))
  end

  test "broadcasts prebuilt public lobby payloads" do
    topic = "test_lobby_payload:" <> Integer.to_string(System.unique_integer([:positive]))
    payload = [%{id: "game_payload", status: :waiting}]

    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, topic)

    assert :ok = GameBroadcast.lobby_payload_update(topic, payload)
    assert_receive {:lobby_update, ^payload}
  end
end
