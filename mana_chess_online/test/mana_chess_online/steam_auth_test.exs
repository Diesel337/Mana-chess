defmodule ManaChessOnline.SteamAuthTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.{SteamAuth, SteamAuthTestClient}

  @app_id 111_111
  @steam_id "76561198000000001"
  @owner_steam_id "76561198000000002"
  @ticket String.duplicate("ab", 64)

  setup do
    original_config = Application.get_env(:mana_chess_online, :steam_auth)

    Application.put_env(:mana_chess_online, :steam_auth,
      app_id: @app_id,
      publisher_key: "publisher-secret",
      ticket_identity: "mana-chess-desktop-v1",
      session_ttl_seconds: 86_400,
      client: SteamAuthTestClient
    )

    SteamAuthTestClient.clear_response()

    on_exit(fn ->
      SteamAuthTestClient.clear_response()

      if original_config do
        Application.put_env(:mana_chess_online, :steam_auth, original_config)
      else
        Application.delete_env(:mana_chess_online, :steam_auth)
      end
    end)

    :ok
  end

  test "authenticates and normalizes a verified owned identity" do
    SteamAuthTestClient.put_response({:ok, verified_identity()})

    assert {:ok, identity} = SteamAuth.authenticate(String.upcase(@ticket))
    assert identity.steam_id == @steam_id
    assert identity.owner_steam_id == @owner_steam_id
    assert identity.app_id == @app_id
    assert identity.owns_app
    assert identity.permanent == false
    assert identity.site_license == false

    assert_receive {SteamAuthTestClient, :called, @ticket, config}
    assert config.app_id == @app_id
    assert config.ticket_identity == "mana-chess-desktop-v1"
  end

  test "exposes only the sanitized versioned desktop configuration" do
    assert SteamAuth.public_configuration() == %{
             protocol_version: 1,
             configured: true,
             app_id: @app_id,
             ticket_identity: "mana-chess-desktop-v1"
           }

    Application.put_env(:mana_chess_online, :steam_auth,
      app_id: @app_id,
      publisher_key: "",
      ticket_identity: "mana-chess-desktop-v1",
      client: SteamAuthTestClient
    )

    assert SteamAuth.public_configuration() == %{
             protocol_version: 1,
             configured: false,
             app_id: @app_id,
             ticket_identity: "mana-chess-desktop-v1"
           }
  end

  test "rejects malformed tickets before calling the upstream client" do
    assert {:error, :malformed_ticket} = SteamAuth.authenticate("not-a-ticket")
    refute_receive {SteamAuthTestClient, :called, _ticket, _config}
  end

  test "rejects mismatched AppID and missing ownership defensively" do
    SteamAuthTestClient.put_response({:ok, %{verified_identity() | app_id: @app_id + 1}})

    assert {:error, :invalid_ticket} = SteamAuth.authenticate(@ticket)

    SteamAuthTestClient.put_response({:ok, %{verified_identity() | owns_app: false}})

    assert {:error, :ownership_required} = SteamAuth.authenticate(@ticket)
  end

  test "issues expiring sessions and stable Steam player IDs" do
    payload = SteamAuth.session_payload(verified_identity(), 1_000)

    assert SteamAuth.valid_session?(payload, 1_001)
    assert {:ok, "steam_" <> @steam_id} = SteamAuth.player_id(payload, 1_001)
    refute SteamAuth.valid_session?(payload, 1_000 + 86_401)
    assert :error = SteamAuth.player_id(%{"steam_id" => @steam_id})
  end

  test "does not accept legacy truthy Steam session markers" do
    refute SteamAuth.valid_session?(true)
    refute SteamAuth.valid_session?("steam")
    refute SteamAuth.valid_session?(%{"steam_verified" => true})
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
end
