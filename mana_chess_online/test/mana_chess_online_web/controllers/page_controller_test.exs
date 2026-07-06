defmodule ManaChessOnlineWeb.PageControllerTest do
  use ManaChessOnlineWeb.ConnCase

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

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Mana Chess"
    assert response =~ "cosmetics-module-20260706"
    assert response =~ "layout-module-20260706"
    assert response =~ "local-stats-module-20260706"
    assert response =~ "sound-module-20260706"
    assert response =~ "chat-module-20260706"
  end

  test "GET /admin", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert html_response(conn, 200) =~ "Admin"
  end

  test "GET /game/game_1", %{conn: conn} do
    conn = get(conn, ~p"/game/game_1")
    response = html_response(conn, 200)
    assert response =~ "Partida"
    assert response =~ "game_1"
  end

  test "GET /game/game_4", %{conn: conn} do
    conn = get(conn, ~p"/game/game_4")
    response = html_response(conn, 200)
    assert response =~ "Partida"
    assert response =~ "game_4"
  end

  test "steam launch access mode blocks public game routes", %{conn: conn} do
    Application.put_env(:mana_chess_online, :launch_access,
      mode: "steam_required",
      qa_bypass_key: "qa-secret"
    )

    conn = get(conn, ~p"/")
    response = html_response(conn, 403)

    assert response =~ "requires Steam access"
    assert response =~ "protected bypass"
  end

  test "steam launch access mode leaves admin login reachable", %{conn: conn} do
    Application.put_env(:mana_chess_online, :launch_access,
      mode: "steam_required",
      qa_bypass_key: "qa-secret"
    )

    conn = get(conn, ~p"/admin")
    assert html_response(conn, 200) =~ "Admin"
  end

  test "steam launch access mode allows explicit QA bypass key", %{conn: conn} do
    Application.put_env(:mana_chess_online, :launch_access,
      mode: "steam_required",
      qa_bypass_key: "qa-secret"
    )

    conn = get(conn, ~p"/?qa_key=qa-secret")
    assert html_response(conn, 200) =~ "Mana Chess"

    conn = get(conn, ~p"/game/game_1")
    assert html_response(conn, 200) =~ "game_1"
  end

  test "steam launch access mode rejects wrong QA bypass key", %{conn: conn} do
    Application.put_env(:mana_chess_online, :launch_access,
      mode: "steam_required",
      qa_bypass_key: "qa-secret"
    )

    conn = get(conn, ~p"/?qa_key=wrong")
    assert html_response(conn, 403) =~ "requires Steam access"
  end
end
