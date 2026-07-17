defmodule ManaChessOnline.GameCapacityTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameCapacity, GameLobbyMatchmaking, GameSettings, GameSupervisor}

  setup do
    original_runtime = Application.get_env(:mana_chess_online, :game_runtime, [])
    baseline = GameSupervisor.game_snapshots() |> GameCapacity.dynamic_game_count()

    Application.put_env(
      :mana_chess_online,
      :game_runtime,
      Keyword.put(original_runtime, :max_dynamic_games, baseline + 1)
    )

    on_exit(fn -> Application.put_env(:mana_chess_online, :game_runtime, original_runtime) end)

    %{baseline: baseline}
  end

  test "rejects new dynamic rooms at the configured admission limit" do
    state = empty_state()

    assert {:ok, state, first_game_id} =
             GameLobbyMatchmaking.create_private(state, "capacity-owner-1", 1_000)

    on_exit(fn -> GameSupervisor.stop_game(first_game_id) end)

    assert {:error, :capacity, rejected_state} =
             GameLobbyMatchmaking.create_private(state, "capacity-owner-2", 2_000)

    assert rejected_state.capacity_stats.rejected_count == 1
  end

  test "allows a sole owner to replace its dynamic room at capacity" do
    assert {:ok, state, first_game_id} =
             GameLobbyMatchmaking.create_private(empty_state(), "capacity-replace", 1_000)

    assert {:ok, next_state, second_game_id} =
             GameLobbyMatchmaking.create_private(state, "capacity-replace", 2_000)

    on_exit(fn -> GameSupervisor.stop_game(first_game_id) end)
    on_exit(fn -> GameSupervisor.stop_game(second_game_id) end)

    refute first_game_id == second_game_id
    assert GameSupervisor.lookup_game(first_game_id) == :error
    assert next_state.players["capacity-replace"].game_id == second_game_id
  end

  test "applies the shared capacity limit to competitive queue rooms" do
    assert {:ok, state, game_id} =
             GameLobbyMatchmaking.create_matchmaking(empty_state(), "queue-capacity-1", 1_200)

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert {:error, :capacity, rejected_state} =
             GameLobbyMatchmaking.create_matchmaking(state, "queue-capacity-2", 1_200)

    assert rejected_state.capacity_stats.rejected_count == 1
  end

  defp empty_state do
    %{
      global_settings: GameSettings.default_settings(),
      games: %{},
      players: %{},
      rate_limits: %{}
    }
  end
end
