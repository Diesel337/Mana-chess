defmodule ManaChessOnline.GameLobbyTickTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{
    GameLobbyTick,
    GameLobbyView,
    GameRooms,
    GameRuntimeConfig,
    GameSupervisor
  }

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(game, rate_limits \\ %{}) do
    %{
      global_settings: settings(),
      games: %{game.id => game},
      players: %{},
      rate_limits: rate_limits
    }
  end

  test "refreshes public mirrors without ticking every live game" do
    game_id = "lobby_tick_game_" <> Integer.to_string(System.unique_integer([:positive]))
    stale_game = %{GameRooms.new_game(game_id, settings()) | status: {:starting, 5_000}}
    live_game = %{stale_game | status: :playing}
    assert {:ok, _pid} = GameSupervisor.upsert_game(live_game)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {next_state, changed_game_ids, lobby_update?} =
      GameLobbyTick.run(
        state(stale_game),
        1_000,
        250,
        60_000,
        &GameLobbyView.public_game/2,
        &GameLobbyView.public_lobby/2
      )

    assert next_state.games[game_id].status == :playing
    assert changed_game_ids == []
    assert lobby_update?
  end

  test "prunes stale rate limits" do
    game_id = "lobby_tick_rates_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    rate_limits = %{
      {:join, "old"} => [1],
      {:join, "fresh"} => [60_000]
    }

    {next_state, _changed_game_ids, _lobby_update?} =
      GameLobbyTick.run(
        state(game, rate_limits),
        60_001,
        250,
        60_000,
        &GameLobbyView.public_game/2,
        &GameLobbyView.public_lobby/2
      )

    refute Map.has_key?(next_state.rate_limits, {:join, "old"})
    assert Map.has_key?(next_state.rate_limits, {:join, "fresh"})
  end

  test "falls back to batch ticks when autonomous ticking is disabled" do
    original_runtime = Application.get_env(:mana_chess_online, :game_runtime, [])

    Application.put_env(
      :mana_chess_online,
      :game_runtime,
      Keyword.put(original_runtime, :auto_tick, false)
    )

    on_exit(fn -> Application.put_env(:mana_chess_online, :game_runtime, original_runtime) end)

    refute GameRuntimeConfig.auto_tick?()

    game_id = "lobby_batch_fallback_" <> Integer.to_string(System.unique_integer([:positive]))
    game = %{GameRooms.new_game(game_id, settings()) | status: {:starting, 1_000}}
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    {next_state, changed_game_ids, lobby_update?} =
      GameLobbyTick.run(
        state(game),
        1_000,
        250,
        60_000,
        &GameLobbyView.public_game/2,
        &GameLobbyView.public_lobby/2
      )

    assert next_state.games[game_id].status == :playing
    assert changed_game_ids == [game_id]
    assert lobby_update?
  end
end
