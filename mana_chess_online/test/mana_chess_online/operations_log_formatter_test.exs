defmodule ManaChessOnline.Operations.LogFormatterTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.Operations.LogFormatter

  setup do
    original = Application.get_env(:mana_chess_online, :runtime_metadata)

    Application.put_env(:mana_chess_online, :runtime_metadata,
      environment: "staging",
      release: "abc123"
    )

    on_exit(fn -> restore_env(:runtime_metadata, original) end)
  end

  test "renders one-line JSON with safe operational metadata" do
    line =
      LogFormatter.format(
        :error,
        "operational_event",
        {{2026, 7, 17}, {20, 1, 2, 345}},
        event: "database_query_failed",
        component: "postgres",
        code: "connection_failed",
        request_id: "request-1",
        status: nil,
        password: "do-not-log",
        database_url: "postgres://secret"
      )
      |> IO.iodata_to_binary()

    assert String.ends_with?(line, "\n")
    refute String.trim_trailing(line) =~ "\n"

    payload = Jason.decode!(line)
    assert payload["timestamp"] == "2026-07-17T20:01:02.345Z"
    assert payload["environment"] == "staging"
    assert payload["release"] == "abc123"
    assert payload["service"] == "mana_chess_online"
    assert payload["level"] == "error"
    assert payload["event"] == "database_query_failed"
    assert payload["request_id"] == "request-1"
    refute Map.has_key?(payload, "status")
    refute Map.has_key?(payload, "password")
    refute line =~ "do-not-log"
    refute line =~ "postgres://secret"
  end

  test "redacts common credentials from standard OTP messages" do
    ticket = String.duplicate("a1", 64)

    line =
      LogFormatter.format(
        :error,
        "db=postgresql://user:password@host/db token=private ticket=#{ticket}",
        {{2026, 7, 17}, {20, 1, 2, 345}},
        []
      )
      |> IO.iodata_to_binary()

    payload = Jason.decode!(line)
    assert payload["message"] =~ "[REDACTED_URL]"
    assert payload["message"] =~ "token=[REDACTED]"
    assert payload["message"] =~ "ticket=[REDACTED]"
    refute line =~ "user:password"
    refute line =~ "private"
    refute line =~ ticket
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
