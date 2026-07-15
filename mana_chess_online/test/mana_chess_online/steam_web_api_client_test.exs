defmodule ManaChessOnline.SteamWebApiClientTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.SteamWebApiClient

  @steam_id "76561198000000000"
  @owner_steam_id "76561198000000001"
  @ticket String.duplicate("ab", 64)

  setup {Req.Test, :verify_on_exit!}

  test "authenticates a ticket and verifies its active app license" do
    Req.Test.expect(__MODULE__, 2, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/ISteamUserAuth/AuthenticateUserTicket/v1/" ->
          assert conn.query_params == %{
                   "appid" => "111111",
                   "identity" => "mana-chess-desktop-v1",
                   "key" => "publisher-key",
                   "ticket" => @ticket
                 }

          Req.Test.json(conn, %{
            response: %{
              params: %{
                result: "OK",
                steamid: @steam_id,
                ownersteamid: @owner_steam_id,
                vacbanned: false,
                publisherbanned: false
              }
            }
          })

        "/ISteamUser/CheckAppOwnership/v4/" ->
          assert conn.query_params == %{
                   "appid" => "111111",
                   "key" => "publisher-key",
                   "steamid" => @steam_id
                 }

          Req.Test.json(conn, %{
            appownership: %{
              ownsapp: true,
              permanent: false,
              ownersteamid: @owner_steam_id,
              sitelicense: false,
              timeexpires: "2030-01-01T00:00:00Z",
              usercanceled: false
            }
          })
      end
    end)

    assert {:ok, identity} = SteamWebApiClient.authenticate_and_check(@ticket, config())
    assert identity.steam_id == @steam_id
    assert identity.owner_steam_id == @owner_steam_id
    assert identity.app_id == 111_111
    assert identity.owns_app
    refute identity.permanent
  end

  test "rejects publisher-banned tickets before checking ownership" do
    Req.Test.expect(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        response: %{
          params: %{
            result: "OK",
            steamid: @steam_id,
            ownersteamid: @steam_id,
            publisherbanned: true
          }
        }
      })
    end)

    assert {:error, :publisher_banned} =
             SteamWebApiClient.authenticate_and_check(@ticket, config())
  end

  test "rejects inactive ownership" do
    Req.Test.expect(__MODULE__, 2, fn conn ->
      case conn.request_path do
        "/ISteamUserAuth/AuthenticateUserTicket/v1/" ->
          Req.Test.json(conn, %{
            response: %{params: %{result: "OK", steamid: @steam_id}}
          })

        "/ISteamUser/CheckAppOwnership/v4/" ->
          Req.Test.json(conn, %{
            appownership: %{ownsapp: false, usercanceled: true}
          })
      end
    end)

    assert {:error, :ownership_required} =
             SteamWebApiClient.authenticate_and_check(@ticket, config())
  end

  test "sanitizes upstream transport failures" do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :timeout))

    assert {:error, :upstream_unavailable} =
             SteamWebApiClient.authenticate_and_check(@ticket, config())
  end

  defp config do
    %{
      app_id: 111_111,
      publisher_key: "publisher-key",
      ticket_identity: "mana-chess-desktop-v1",
      request_options: [plug: {Req.Test, __MODULE__}]
    }
  end
end
