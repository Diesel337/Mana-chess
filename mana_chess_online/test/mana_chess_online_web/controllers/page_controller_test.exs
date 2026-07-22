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
    assert response =~ "app.css?v=cosmetic-mastery-20260717"
    assert response =~ "premium_cosmetics.css?v=premium-cosmetics-celestial-20260718"
    assert response =~ "game_effects.css?v=game-effects-20260718c"
    assert response =~ "cosmetic_browser.css?v=cosmetic-gallery-20260722b"
    assert response =~ "flat_pieces.css?v=flat-pieces-20260722e"
    assert response =~ "game_effects.js?v=game-effects-20260718c"
    assert response =~ "cosmetic-catalog-celestial-20260718"
    assert response =~ "cosmetic-progression-20260717"
    assert response =~ "cosmetics-gallery-20260722"
    assert response =~ "cosmetic-actions-mastery-20260717"
    assert response =~ "app.js?v=game-effects-20260718c"
    assert response =~ "cosmetic-fallback-mastery-20260717"
    assert response =~ "cosmetic-session-mastery-20260717"
    assert response =~ "lobby-p0-20260717b"
    assert response =~ "p0_lobby.css?v=lobby-p0-20260717"
    assert response =~ "competitive.css?v=competitive-leaderboard-20260717"
    assert response =~ "realtime-client-20260717b"
    assert response =~ "local-stats-module-20260706"
    assert response =~ "local-stats-events-mastery-20260717"
    assert response =~ "local-stats-lifecycle-module-20260707"
    assert response =~ "result-recording-module-20260707"
    assert response =~ "stats-session-module-20260707"
    assert response =~ "local-stats-hook-mastery-20260717"
    assert response =~ "sound-premium-20260717"
    assert response =~ "sound-state-module-20260707"
    assert response =~ "sound-session-module-20260707"
    assert response =~ "chat-module-20260706"
    assert response =~ "view-session-module-20260707"
    assert response =~ "navigation-module-20260707"
    assert response =~ "desktop-bridge-module-20260707"
    assert response =~ "desktop-session-module-20260707"
    assert response =~ "invite-clipboard-module-20260707"
    assert response =~ "board-drag-module-20260707"
    assert response =~ "board-drag-hook-module-20260707"
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

  test "premium cosmetic catalog and artwork are served", %{conn: conn} do
    catalog = conn |> get("/assets/js/cosmetic_catalog.js") |> response(200)
    progression = build_conn() |> get("/assets/js/cosmetic_progression.js") |> response(200)
    stylesheet = build_conn() |> get("/assets/css/premium_cosmetics.css") |> response(200)

    assert catalog =~ "mastery"
    assert progression =~ "syncUnlocks"
    assert progression =~ "Maestria"

    for family <- ~w(arcane crystal elemental celestial) do
      assert catalog =~ family
      assert stylesheet =~ "/images/cosmetics/#{family}/king.svg"

      for piece <- ~w(pawn knight bishop rook queen king) do
        svg = build_conn() |> get("/images/cosmetics/#{family}/#{piece}.svg") |> response(200)
        assert svg =~ ~s(viewBox="0 0 100 120")
      end

      frame = build_conn() |> get("/images/cosmetics/#{family}/frame.svg") |> response(200)
      assert frame =~ ~s(viewBox="0 0 1000 1000")
    end
  end

  test "game presentation assets are served", %{conn: conn} do
    javascript = conn |> get("/assets/js/game_effects.js") |> response(200)
    stylesheet = build_conn() |> get("/assets/css/game_effects.css") |> response(200)

    assert javascript =~ "ManaChessGameEffectsHook"
    assert javascript =~ "mana-chess:cosmetic-unlocked"
    assert stylesheet =~ "mc-effect-capture"
    assert stylesheet =~ "prefers-reduced-motion"
  end

  test "cosmetic browser assets are served", %{conn: conn} do
    javascript = conn |> get("/assets/js/cosmetics.js") |> response(200)
    stylesheet = build_conn() |> get("/assets/css/cosmetic_browser.css") |> response(200)
    flat_pieces = build_conn() |> get("/assets/css/flat_pieces.css") |> response(200)

    assert javascript =~ "previewSelection"
    assert javascript =~ "equipPreview"
    assert javascript =~ "openCosmeticGallery"
    assert javascript =~ "closeCosmeticGallery"
    assert stylesheet =~ "mc-lobby-tabs"
    assert stylesheet =~ "mc-cosmetic-preview-stage"
    assert stylesheet =~ "mc-cosmetic-gallery-board"
    assert flat_pieces =~ "--mc-flat-piece-mask"
    assert flat_pieces =~ "/images/pieces/flat/king.svg"

    for piece <- ~w(pawn knight bishop rook queen king) do
      svg = build_conn() |> get("/images/pieces/flat/#{piece}.svg") |> response(200)
      assert svg =~ ~s(viewBox="0 0 100 120")
      assert svg =~ "<path"
    end
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
