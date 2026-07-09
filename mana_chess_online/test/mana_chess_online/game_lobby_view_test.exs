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

  test "delegates public game and lobby snapshots" do
    game = GameState.new_game("game_1", settings())
    state = %{games: %{"game_1" => game}}

    assert GameLobbyView.public_game(game, 1_000).id == "game_1"
    assert [%{id: "game_1"}] = GameLobbyView.public_lobby(state, 1_000)
  end
end
