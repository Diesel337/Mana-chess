defmodule ManaChessOnline.GameLobbyViewTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.{GameLobbyView, GameState}

  defp settings do
    %{
      max_elixir: 10.0,
      initial_elixir: 5.0,
      cooldown_seconds: 1.0,
      costs: %{pawn: 1.0, knight: 3.0, bishop: 3.0, rook: 4.0, queen: 6.0, king: 3.0}
    }
  end

  test "builds player and spectator views from public payloads" do
    public_game = %{id: "game_1", status: :waiting}
    public_lobby = [%{id: "game_1"}]

    assert GameLobbyView.player_view(
             "player-1",
             %{game_id: "game_1", color: :white},
             public_game,
             public_lobby
           ) == %{
             player_id: "player-1",
             game_id: "game_1",
             color: :white,
             game: public_game,
             lobby: public_lobby
           }

    assert GameLobbyView.spectator_view("watcher", "game_1", nil, public_game, public_lobby).color ==
             nil
  end

  test "builds current player and spectator views from lobby state" do
    state = %{
      players: %{"player-1" => %{game_id: "game_1", color: :white}},
      games: %{}
    }

    public_lobby = [%{id: "game_1"}]
    public_game_snapshot = fn game_id -> %{id: game_id, status: :playing} end

    assert GameLobbyView.current_player_view(
             state,
             "player-1",
             public_game_snapshot,
             public_lobby
           ) == %{
             player_id: "player-1",
             game_id: "game_1",
             color: :white,
             game: %{id: "game_1", status: :playing},
             lobby: public_lobby
           }

    assert GameLobbyView.current_spectator_view(
             state,
             "watcher",
             "game_1",
             public_game_snapshot,
             public_lobby
           ) == %{
             player_id: "watcher",
             game_id: "game_1",
             color: nil,
             game: %{id: "game_1", status: :playing},
             lobby: public_lobby
           }
  end

  test "delegates public game and lobby snapshots" do
    game = GameState.new_game("game_1", settings())
    state = %{games: %{"game_1" => game}}

    assert GameLobbyView.public_game(game, 1_000).id == "game_1"
    assert [%{id: "game_1"}] = GameLobbyView.public_lobby(state, 1_000)
  end
end
