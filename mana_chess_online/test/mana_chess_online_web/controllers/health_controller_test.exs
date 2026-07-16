defmodule ManaChessOnlineWeb.HealthControllerTest do
  use ManaChessOnlineWeb.ConnCase, async: false

  alias ManaChessOnline.{PersistenceTestStore, PersistenceTestWriter}

  setup do
    original_config = Application.get_env(:mana_chess_online, :persistence)
    original_health = Application.get_env(:mana_chess_online, :persistence_test_health)

    on_exit(fn ->
      restore_env(:persistence, original_config)
      restore_env(:persistence_test_health, original_health)
    end)

    :ok
  end

  test "reports memory mode ready when Postgres is not configured", %{conn: conn} do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: false,
      store: PersistenceTestStore,
      writer: PersistenceTestWriter
    )

    response = conn |> get(~p"/health") |> json_response(200)
    assert response["ok"]
    assert response["persistence"]["mode"] == "memory"
    assert response["persistence"]["ready"]
  end

  test "fails readiness without leaking database details", %{conn: conn} do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: PersistenceTestStore,
      writer: PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_health, {:error, :secret_url})

    conn = get(conn, ~p"/health")
    response = json_response(conn, 503)
    refute response["ok"]
    assert response["persistence"]["mode"] == "postgres"
    refute response["persistence"]["ready"]
    refute conn.resp_body =~ "secret_url"
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
