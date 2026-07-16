defmodule ManaChessOnlineWeb.HealthController do
  use ManaChessOnlineWeb, :controller

  alias ManaChessOnline.Persistence

  def show(conn, _params) do
    case Persistence.health() do
      {:ok, persistence} ->
        json(conn, %{ok: true, service: "mana_chess_online", persistence: persistence})

      {:error, persistence} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{ok: false, service: "mana_chess_online", persistence: persistence})
    end
  end
end
