defmodule ManaChessOnline.GameLifecycleTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameLifecycle, GameState, GameSupervisor}

  setup do
    original_runtime = Application.get_env(:mana_chess_online, :game_runtime, [])

    Application.put_env(
      :mana_chess_online,
      :game_runtime,
      original_runtime
      |> Keyword.put(:dynamic_idle_ttl_ms, 100)
      |> Keyword.put(:lifecycle_interval_ms, 1)
    )

    on_exit(fn -> Application.put_env(:mana_chess_online, :game_runtime, original_runtime) end)
    :ok
  end

  test "heartbeats keep assigned players and private spectators active" do
    game = GameState.private_game("private_heartbeat_test", settings())

    state = %{
      games: %{game.id => game},
      players: %{"owner" => %{game_id: game.id, color: :white}},
      rate_limits: %{}
    }

    state = GameLifecycle.heartbeat(state, "owner", game.id, 100)
    state = GameLifecycle.heartbeat(state, "spectator", game.id, 200)

    assert state.game_activity[game.id] == 200
  end

  test "maintenance removes idle dynamic games and their assignments" do
    game_id = "private_idle_lifecycle_test"

    game =
      game_id
      |> GameState.private_game(settings())
      |> Map.put(:players, %{white: "idle-owner", black: nil})

    assert {:ok, _pid} = GameSupervisor.upsert_game(game)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = %{
      games: %{game_id => game},
      players: %{"idle-owner" => %{game_id: game_id, color: :white}},
      rate_limits: %{},
      game_activity: %{game_id => 1},
      last_lifecycle_at: 0,
      capacity_stats: %{rejected_count: 0, cleaned_count: 0}
    }

    next_state = GameLifecycle.maintain(state, 200)

    refute Map.has_key?(next_state.games, game_id)
    refute Map.has_key?(next_state.players, "idle-owner")
    assert next_state.capacity_stats.cleaned_count == 1
    assert GameSupervisor.lookup_game(game_id) == :error
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
