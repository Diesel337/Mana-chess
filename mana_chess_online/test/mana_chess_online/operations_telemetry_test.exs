defmodule ManaChessOnline.Operations.TelemetryTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Operations.Telemetry

  test "reports Phoenix exceptions without exception messages or request data" do
    reporter = reporter(self())
    duration = System.convert_time_unit(12, :millisecond, :native)

    Telemetry.handle_event(
      [:phoenix, :router_dispatch, :exception],
      %{duration: duration},
      %{
        conn: %{method: "POST", status: 500},
        route: "/game/:game_id",
        reason: %RuntimeError{message: "private request payload"}
      },
      %{reporter: reporter}
    )

    assert_receive {:reported, :error, "web_request_exception", metadata}
    assert metadata.component == "phoenix"
    assert metadata.method == "POST"
    assert metadata.route == "/game/:game_id"
    assert metadata.reason_class == "RuntimeError"
    refute inspect(metadata) =~ "private request payload"
  end

  test "reports only requests and channel events above configured thresholds" do
    reporter = reporter(self())
    fast = System.convert_time_unit(20, :millisecond, :native)
    slow = System.convert_time_unit(250, :millisecond, :native)
    config = %{reporter: reporter, slow_request_ms: 100, slow_socket_ms: 100}

    Telemetry.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: fast},
      %{conn: %{method: "GET", status: 200}, route: "/health"},
      config
    )

    refute_receive {:reported, _, _, _}

    Telemetry.handle_event(
      [:phoenix, :router_dispatch, :stop],
      %{duration: slow},
      %{conn: %{method: "GET", status: 200}, route: "/game/:game_id"},
      config
    )

    Telemetry.handle_event(
      [:phoenix, :channel_handled_in],
      %{duration: slow},
      %{event: "move"},
      config
    )

    assert_receive {:reported, :warning, "web_request_slow", %{duration_ms: 250.0}}

    assert_receive {:reported, :warning, "channel_event_slow",
                    %{duration_ms: 250.0, event_type: "move"}}
  end

  test "reports database errors using only source and exception class" do
    reporter = reporter(self())
    duration = System.convert_time_unit(8, :millisecond, :native)

    Telemetry.handle_event(
      [:mana_chess_online, :repo, :query],
      %{total_time: duration},
      %{
        result: {:error, %RuntimeError{message: "postgres://private"}},
        source: "match_summaries",
        params: ["private-player"]
      },
      %{reporter: reporter, slow_query_ms: 1_000}
    )

    assert_receive {:reported, :error, "database_query_failed", metadata}
    assert metadata.component == "postgres"
    assert metadata.source == "match_summaries"
    assert metadata.reason_class == "RuntimeError"
    refute inspect(metadata) =~ "postgres://private"
    refute inspect(metadata) =~ "private-player"
  end

  defp reporter(test_pid) do
    fn level, event, metadata -> send(test_pid, {:reported, level, event, metadata}) end
  end
end
