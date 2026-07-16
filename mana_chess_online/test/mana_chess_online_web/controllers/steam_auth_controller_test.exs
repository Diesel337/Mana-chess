defmodule ManaChessOnlineWeb.SteamAuthControllerTest do
  use ManaChessOnlineWeb.ConnCase, async: false

  alias ManaChessOnline.{
    PersistenceTestStore,
    PersistenceTestWriter,
    SteamAuth,
    SteamAuthTestClient
  }

  @app_id 111_111
  @steam_id "76561198000000001"
  @owner_steam_id "76561198000000002"
  @ticket String.duplicate("cd", 64)

  setup do
    original_steam_config = Application.get_env(:mana_chess_online, :steam_auth)
    original_launch_config = Application.get_env(:mana_chess_online, :launch_access)
    original_persistence_config = Application.get_env(:mana_chess_online, :persistence)
    original_persistence_pid = Application.get_env(:mana_chess_online, :persistence_test_pid)

    original_entitlements =
      Application.get_env(:mana_chess_online, :persistence_test_entitlements)

    Application.put_env(:mana_chess_online, :steam_auth,
      app_id: @app_id,
      publisher_key: "publisher-secret",
      ticket_identity: "mana-chess-desktop-v1",
      session_ttl_seconds: 86_400,
      client: SteamAuthTestClient
    )

    Application.put_env(:mana_chess_online, :launch_access,
      mode: "steam_required",
      qa_bypass_key: ""
    )

    SteamAuthTestClient.clear_response()

    on_exit(fn ->
      SteamAuthTestClient.clear_response()
      restore_env(:steam_auth, original_steam_config)
      restore_env(:launch_access, original_launch_config)
      restore_env(:persistence, original_persistence_config)
      restore_env(:persistence_test_pid, original_persistence_pid)
      restore_env(:persistence_test_entitlements, original_entitlements)
    end)

    :ok
  end

  test "creates a renewed verified session and binds player identity", %{conn: conn} do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: false,
      store: PersistenceTestStore,
      writer: PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_pid, self())
    SteamAuthTestClient.put_response({:ok, verified_identity()})

    conn =
      conn
      |> put_req_header("x-mana-chess-desktop", "1")
      |> post(~p"/auth/steam", %{ticket: @ticket})

    response = json_response(conn, 201)
    assert response["ok"]
    assert response["identity"]["steam_id"] == @steam_id
    assert response["identity"]["owner_steam_id"] == @owner_steam_id
    refute inspect(response) =~ @ticket

    assert_receive {:persistence_writer_event, {:steam_identity, persisted_identity}}
    assert persisted_identity.steam_id == @steam_id
    assert persisted_identity.owner_steam_id == @owner_steam_id

    session = get_session(conn, SteamAuth.session_key())
    assert session["steam_id"] == @steam_id
    assert session["app_id"] == Integer.to_string(@app_id)
    refute get_session(conn, :player_id)

    conn =
      conn
      |> recycle()
      |> get(~p"/")

    assert html_response(conn, 200) =~ "Mana Chess"
    assert get_session(conn, :player_id) == "steam_" <> @steam_id
  end

  test "returns only active persisted entitlements to a verified desktop session", %{conn: conn} do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: PersistenceTestStore,
      writer: PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_entitlements, [
      %{
        source: "steam_dlc",
        external_id: "222222",
        sku: "founder_board_pack",
        kind: "cosmetic_pack",
        status: "active",
        metadata: %{"private" => "not-public"}
      },
      %{
        source: "steam_dlc",
        external_id: "333333",
        sku: "revoked_pack",
        kind: "cosmetic_pack",
        status: "revoked"
      }
    ])

    SteamAuthTestClient.put_response({:ok, verified_identity()})
    conn = steam_post(conn, @ticket)

    conn =
      conn
      |> recycle()
      |> put_req_header("x-mana-chess-desktop", "1")
      |> get(~p"/auth/steam/entitlements")

    assert %{
             "ok" => true,
             "steam_id" => @steam_id,
             "entitlements" => [
               %{
                 "source" => "steam_dlc",
                 "external_id" => "222222",
                 "sku" => "founder_board_pack",
                 "kind" => "cosmetic_pack",
                 "status" => "active"
               }
             ]
           } = json_response(conn, 200)

    refute conn.resp_body =~ "not-public"
    refute conn.resp_body =~ "revoked_pack"
  end

  test "requires a verified session before reading entitlements", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-mana-chess-desktop", "1")
      |> get(~p"/auth/steam/entitlements")

    assert %{"ok" => false, "error" => "steam_session_required"} =
             json_response(conn, 401)
  end

  test "returns sanitized desktop configuration without publisher credentials", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-mana-chess-desktop", "1")
      |> get(~p"/auth/steam/config")

    assert %{
             "ok" => true,
             "launch_required" => true,
             "steam" => %{
               "protocol_version" => 1,
               "configured" => true,
               "app_id" => @app_id,
               "ticket_identity" => "mana-chess-desktop-v1"
             }
           } = json_response(conn, 200)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    refute conn.resp_body =~ "publisher-secret"
  end

  test "protects the desktop configuration contract with the desktop header", %{conn: conn} do
    conn = get(conn, ~p"/auth/steam/config")

    assert %{"ok" => false, "error" => "desktop_header_required"} =
             json_response(conn, 400)
  end

  test "requires the desktop-only request header", %{conn: conn} do
    SteamAuthTestClient.put_response({:ok, verified_identity()})

    conn = post(conn, ~p"/auth/steam", %{ticket: @ticket})

    assert %{"ok" => false, "error" => "desktop_header_required"} =
             json_response(conn, 400)

    refute_receive {SteamAuthTestClient, :called, _ticket, _config}
  end

  test "rejects malformed, invalid, and unowned tickets", %{conn: conn} do
    conn = steam_post(conn, "bad")
    assert json_response(conn, 400)["error"] == "malformed_ticket"

    SteamAuthTestClient.put_response({:error, :invalid_ticket})
    conn = steam_post(recycle(conn), @ticket)
    assert json_response(conn, 403)["error"] == "invalid_ticket"

    SteamAuthTestClient.put_response({:error, :ownership_required})
    conn = steam_post(recycle(conn), @ticket)
    assert json_response(conn, 403)["error"] == "ownership_required"
  end

  test "returns a retryable response when Steam is unavailable", %{conn: conn} do
    SteamAuthTestClient.put_response({:error, :upstream_unavailable})

    conn = steam_post(conn, @ticket)

    assert %{"ok" => false, "error" => "steam_unavailable"} =
             json_response(conn, 503)
  end

  test "fails closed when server credentials are not configured", %{conn: conn} do
    Application.put_env(:mana_chess_online, :steam_auth,
      app_id: "",
      publisher_key: "",
      ticket_identity: "mana-chess-desktop-v1",
      client: SteamAuthTestClient
    )

    conn = steam_post(conn, @ticket)

    assert %{"ok" => false, "error" => "steam_auth_not_configured"} =
             json_response(conn, 503)

    refute_receive {SteamAuthTestClient, :called, _ticket, _config}
  end

  defp steam_post(conn, ticket) do
    conn
    |> put_req_header("x-mana-chess-desktop", "1")
    |> post(~p"/auth/steam", %{ticket: ticket})
  end

  defp verified_identity do
    %{
      steam_id: @steam_id,
      owner_steam_id: @owner_steam_id,
      app_id: @app_id,
      owns_app: true,
      permanent: false,
      site_license: false,
      user_canceled: false,
      time_expires: "never",
      vac_banned: false,
      publisher_banned: false
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
