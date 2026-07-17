defmodule ManaChessOnlineWeb.GameLiveTest do
  use ManaChessOnlineWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ManaChessOnline.{GameLobby, GameSupervisor}

  setup do
    original_config = Application.get_env(:mana_chess_online, :launch_access)

    on_exit(fn ->
      if original_config do
        Application.put_env(:mana_chess_online, :launch_access, original_config)
      else
        Application.delete_env(:mana_chess_online, :launch_access)
      end
    end)

    Application.put_env(:mana_chess_online, :launch_access, mode: "open", qa_bypass_key: "")

    :ok
  end

  test "forged clear room events cannot clear rooms for unseated players", %{conn: conn} do
    owner_id = "live-clear-owner"
    intruder_id = "live-clear-intruder"
    game_id = "game_4"

    on_exit(fn ->
      GameLobby.force_clear_room(game_id)
    end)

    GameLobby.force_clear_room(game_id)
    assert %{game_id: ^game_id} = GameLobby.sit(owner_id, game_id, :white)
    before_game = GameLobby.snapshot(game_id)

    conn = Plug.Test.init_test_session(conn, player_id: intruder_id)
    {:ok, view, _html} = live(conn, ~p"/")

    refute render(view) =~ ~s(phx-click="clear_room")
    render_click(view, "clear_room", %{"game" => game_id})

    after_game = GameLobby.snapshot(game_id)

    assert after_game.players == before_game.players
    assert after_game.status == before_game.status
    assert {:ok, _pid} = GameSupervisor.lookup_game(game_id)
  end

  test "lobby keeps play choices ahead of inline cosmetics", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    {offline_position, _} = :binary.match(html, ~s(class="mc-offline"))
    {lobby_position, _} = :binary.match(html, ~s(class="mc-lobby"))
    {cosmetics_position, _} = :binary.match(html, ~s(class="mc-skins mc-skins-inline"))

    assert offline_position < lobby_position
    assert lobby_position < cosmetics_position
  end

  test "lobby renders the competitive profile and rated quick match action", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ ~s(data-competitive-rating)
    assert html =~ "Prov. 0/10"
    assert html =~ "Buscar rival"
    assert html =~ "Cerca de 1200"
  end
end
