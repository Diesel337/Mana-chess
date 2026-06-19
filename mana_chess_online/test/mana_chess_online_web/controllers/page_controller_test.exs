defmodule ManaChessOnlineWeb.PageControllerTest do
  use ManaChessOnlineWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Mana Chess"
    assert response =~ "brand-fit47-20260619"
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
end
