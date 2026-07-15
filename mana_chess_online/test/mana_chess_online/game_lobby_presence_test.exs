defmodule ManaChessOnline.GameLobbyPresenceTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyPresence, GameLobbyServers, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp empty_state do
    %{global_settings: settings(), games: %{}, players: %{}, rate_limits: %{}}
  end

  test "softly rate limits repeated lobby joins" do
    state =
      Enum.reduce(1..121, empty_state(), fn now, state ->
        GameLobbyPresence.join(state, "join-player", now)
      end)

    assert length(state.rate_limits[{:join, "join-player"}]) == 120
  end

  test "creates a private room lazily for a spectator" do
    game_id = "private_presence_" <> Integer.to_string(System.unique_integer([:positive]))
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = GameLobbyPresence.watch(empty_state(), "spectator", game_id, 1_000)

    assert state.games[game_id].private?
    assert GameLobbyServers.game_snapshot(game_id, state.games).id == game_id
  end

  test "leaves using live server state and reports public lobby changes" do
    game_id = "presence_leave_" <> Integer.to_string(System.unique_integer([:positive]))
    player_id = "leaving-player"

    live_game =
      game_id
      |> GameRooms.new_game(settings())
      |> Map.put(:players, %{white: player_id, black: nil})

    stale_game = %{live_game | players: %{white: "stale-player", black: nil}}
    assert {:ok, pid} = GameSupervisor.upsert_game(live_game)
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state = %{
      global_settings: settings(),
      games: %{game_id => stale_game},
      players: %{player_id => %{game_id: game_id, color: :white}},
      rate_limits: %{}
    }

    assert {state, true} = GameLobbyPresence.leave(state, player_id)

    refute Map.has_key?(state.players, player_id)
    assert state.games[game_id].players.white == nil
    assert GameLobbyServers.game_snapshot(game_id, state.games).players.white == nil
    assert Process.alive?(pid)
  end
end
