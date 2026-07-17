defmodule ManaChessOnlineWeb.HealthController do
  use ManaChessOnlineWeb, :controller

  alias ManaChessOnline.Persistence
  alias ManaChessOnline.Operations.{AlertDispatcher, EventLog}

  def show(conn, _params) do
    case Persistence.health() do
      {:ok, persistence} ->
        json(conn, health_payload(true, persistence))

      {:error, persistence} ->
        conn
        |> put_status(:service_unavailable)
        |> json(health_payload(false, persistence))
    end
  end

  defp health_payload(ok, persistence) do
    %{
      ok: ok,
      service: "mana_chess_online",
      persistence: persistence,
      operations:
        EventLog.snapshot()
        |> Map.put(:alerting, AlertDispatcher.snapshot())
    }
  end
end
