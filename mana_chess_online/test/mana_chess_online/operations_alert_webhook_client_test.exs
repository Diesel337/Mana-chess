defmodule ManaChessOnline.Operations.AlertWebhookClientTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Operations.AlertWebhookClient

  setup {Req.Test, :verify_on_exit!}

  test "delivers the sanitized payload with optional bearer authorization" do
    payload = %{
      schema: "mana_chess.operational_alert.v1",
      event: "database_query_failed",
      metadata: %{code: "query_failed"}
    }

    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/alerts"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer alert-token"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["event"] == "database_query_failed"
      assert decoded["metadata"] == %{"code" => "query_failed"}

      Plug.Conn.send_resp(conn, 202, "")
    end)

    assert :ok =
             AlertWebhookClient.deliver(
               "https://alerts.example.test/v1/alerts",
               "alert-token",
               payload,
               plug: {Req.Test, __MODULE__}
             )
  end

  test "collapses provider errors without returning response bodies" do
    Req.Test.expect(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 503, "provider-secret-response")
    end)

    assert {:error, "http_5xx"} =
             AlertWebhookClient.deliver(
               "https://alerts.example.test/v1/alerts",
               "",
               %{event: "test"},
               plug: {Req.Test, __MODULE__}
             )
  end

  test "marks timeout and rate-limit status codes as retryable" do
    Req.Test.expect(__MODULE__, fn conn ->
      Plug.Conn.send_resp(conn, 429, "provider-rate-limit-details")
    end)

    assert {:error, "http_retryable"} =
             AlertWebhookClient.deliver(
               "https://alerts.example.test/v1/alerts",
               "",
               %{event: "test"},
               plug: {Req.Test, __MODULE__}
             )
  end

  test "collapses transport exceptions" do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :timeout))

    assert {:error, "network_error"} =
             AlertWebhookClient.deliver(
               "https://alerts.example.test/v1/alerts",
               "",
               %{event: "test"},
               plug: {Req.Test, __MODULE__}
             )
  end
end
