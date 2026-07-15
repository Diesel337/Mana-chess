defmodule ManaChessOnlineWeb.SteamAuthController do
  use ManaChessOnlineWeb, :controller

  alias ManaChessOnline.SteamAuth

  def create(conn, %{"ticket" => ticket}) do
    if desktop_request?(conn) do
      case SteamAuth.authenticate(ticket) do
        {:ok, identity} -> authenticated(conn, identity)
        {:error, reason} -> rejected(conn, reason)
      end
    else
      rejected(conn, :desktop_header_required)
    end
  end

  def create(conn, _params), do: rejected(conn, :malformed_ticket)

  defp desktop_request?(conn) do
    conn
    |> get_req_header("x-mana-chess-desktop")
    |> Enum.any?(&(String.trim(&1) == "1"))
  end

  defp authenticated(conn, identity) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(SteamAuth.session_key(), SteamAuth.session_payload(identity))
    |> put_status(:created)
    |> json(%{ok: true, identity: SteamAuth.public_identity(identity)})
  end

  defp rejected(conn, reason) do
    {status, code} =
      case reason do
        :desktop_header_required -> {:bad_request, "desktop_header_required"}
        :malformed_ticket -> {:bad_request, "malformed_ticket"}
        :invalid_ticket -> {:forbidden, "invalid_ticket"}
        :ownership_required -> {:forbidden, "ownership_required"}
        :publisher_banned -> {:forbidden, "publisher_banned"}
        :not_configured -> {:service_unavailable, "steam_auth_not_configured"}
        :upstream_unavailable -> {:service_unavailable, "steam_unavailable"}
        _reason -> {:service_unavailable, "steam_unavailable"}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> json(%{ok: false, error: code})
  end
end
