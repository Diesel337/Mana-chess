defmodule ManaChessOnline.GameLobbyRuntimeTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyRuntime, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "builds player views from the live game server" do
    game_id = "runtime_view_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "runtime-player"

    live_game =
      game_id
      |> GameRooms.new_game(settings())
      |> Map.put(:players, %{white: player_id, black: nil})
      |> Map.put(:log, ["Live runtime state."])

    stale_game = %{live_game | log: ["Stale lobby mirror."]}
    assert {:ok, pid} = GameSupervisor.upsert_game(live_game)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = %{
      global_settings: settings(),
      games: %{game_id => stale_game},
      players: %{player_id => %{game_id: game_id, color: :white}},
      rate_limits: %{}
    }

    view = GameLobbyRuntime.player_view(state, player_id)

    assert view.game.log == ["Live runtime state."]
    assert view.color == :white
    assert Enum.any?(view.lobby, &(&1.id == game_id))
    assert pid in GameLobbyRuntime.game_server_pids(%{state | games: %{}})
  end

  test "broadcasts a public snapshot read from the live server" do
    game_id = "runtime_broadcast_" <> Integer.to_string(System.unique_integer([:positive]))
    live_game = GameRooms.new_game(game_id, settings())
    stale_game = %{live_game | status: :ready}
    assert {:ok, _pid} = GameSupervisor.upsert_game(live_game)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = %{games: %{game_id => stale_game}, players: %{}, rate_limits: %{}}
    Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobbyRuntime.game_topic(game_id))

    assert :ok = GameLobbyRuntime.broadcast_game_snapshot(game_id, state)
    assert_receive {:game_update, %{id: ^game_id, status: :waiting}}
  end
end
