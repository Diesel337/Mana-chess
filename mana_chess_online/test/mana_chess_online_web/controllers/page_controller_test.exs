defmodule ManaChessOnlineWeb.PageControllerTest do
  use ManaChessOnlineWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Mana Chess Online"
  end

  test "GET /admin", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert html_response(conn, 200) =~ "Admin"
  end

  test "GET /game/game_1", %{conn: conn} do
    conn = get(conn, ~p"/game/game_1")
    assert html_response(conn, 200) =~ "Partida game_1"
  end

  test "GET /game/game_4", %{conn: conn} do
    conn = get(conn, ~p"/game/game_4")
    assert html_response(conn, 200) =~ "Partida game_4"
  end
end
