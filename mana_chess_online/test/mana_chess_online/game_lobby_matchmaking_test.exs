defmodule ManaChessOnline.GameLobbyMatchmakingTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{GameLobbyMatchmaking, GameLobbyServers, GameRooms, GameSupervisor}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  defp state(game) do
    %{global_settings: settings(), games: %{game.id => game}, players: %{}, rate_limits: %{}}
  end

  test "sits a player in a requested open seat" do
    game_id = "matchmaking_sit_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert {:ok, state} =
             game
             |> state()
             |> GameLobbyMatchmaking.sit("white-player", game_id, :white, 1_000)

    assert state.players["white-player"] == %{game_id: game_id, color: :white}
    assert state.games[game_id].players.white == "white-player"
  end

  test "sits anywhere using the live open-slot directory" do
    game_id = "000_matchmaking_open_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert {:ok, state} =
             game
             |> state()
             |> GameLobbyMatchmaking.sit_anywhere("open-player", 1_000)

    assert state.players["open-player"] == %{game_id: game_id, color: :white}
    assert state.games[game_id].players.white == "open-player"
    assert state.player_ratings["open-player"] == 1_200
  end

  test "creates and seats the owner in a private room" do
    state = %{global_settings: settings(), games: %{}, players: %{}, rate_limits: %{}}

    assert {:ok, state, game_id} =
             GameLobbyMatchmaking.create_private(state, "private-owner", 1_000)

    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    assert String.starts_with?(game_id, "private_")
    assert state.players["private-owner"] == %{game_id: game_id, color: :white}
    assert state.games[game_id].private?
    assert GameLobbyServers.game_snapshot(game_id, state.games).players.white == "private-owner"
  end

  test "owns the seat request rate limit" do
    game_id = "matchmaking_rate_" <> Integer.to_string(System.unique_integer([:positive]))
    game = GameRooms.new_game(game_id, settings())
    on_exit(fn -> GameSupervisor.stop_game(game_id) end)

    state =
      Enum.reduce(1..30, state(game), fn now, state ->
        assert {:ok, state} =
                 GameLobbyMatchmaking.sit(state, "rate-player", game_id, :white, now)

        state
      end)

    assert {:error, :rate_limited, state} =
             GameLobbyMatchmaking.sit(state, "rate-player", game_id, :white, 31)

    assert length(state.rate_limits[{:seat, "rate-player"}]) == 30
  end
end
