defmodule ManaChessOnline.Operations.EventLogTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Operations.{AlertDispatcher, EventLog}

  test "stores bounded safe diagnostics and strips unknown metadata" do
    test_pid = self()

    {:ok, event_log} =
      start_supervised(
        {EventLog,
         name: nil,
         timestamp: fn -> "2026-07-17T20:00:00Z" end,
         logger: fn level, message, metadata ->
           send(test_pid, {:logged, level, message, Map.new(metadata)})
         end}
      )

    EventLog.report(event_log, :error, "database_query_failed", %{
      code: "connection_failed",
      component: "postgres",
      database_url: "postgres://secret",
      player_id: "private-player"
    })

    assert %{
             running: true,
             environment: "test",
             release: "local",
             error_count: 1,
             logged_count: 1,
             last_event: "database_query_failed",
             last_level: "error"
           } = EventLog.snapshot(event_log)

    assert_receive {:logged, :error, "operational_event", metadata}
    assert metadata.event == "database_query_failed"
    assert metadata.code == "connection_failed"
    assert metadata.component == "postgres"
    refute Map.has_key?(metadata, :database_url)
    refute Map.has_key?(metadata, :player_id)

    assert [recent] = EventLog.recent(event_log, 5)
    refute inspect(recent) =~ "secret"
    refute inspect(recent) =~ "private-player"
  end

  test "deduplicates repeated events while preserving counters" do
    test_pid = self()

    {:ok, event_log} =
      start_supervised(
        {EventLog,
         name: nil,
         dedupe_window_ms: 60_000,
         timestamp: fn -> "2026-07-17T20:00:00Z" end,
         logger: fn level, message, metadata ->
           send(test_pid, {:logged, level, message, metadata})
         end}
      )

    metadata = %{code: "write_failed", component: "persistence_writer"}
    EventLog.report(event_log, :warning, "persistence_write_failed", metadata)
    EventLog.report(event_log, :warning, "persistence_write_failed", metadata)

    assert %{
             warning_count: 2,
             logged_count: 1,
             suppressed_count: 1
           } = EventLog.snapshot(event_log)

    assert_receive {:logged, :warning, "operational_event", _metadata}
    refute_receive {:logged, :warning, "operational_event", _metadata}, 25
  end

  test "survives a failing log sink" do
    {:ok, event_log} =
      start_supervised(
        {EventLog,
         name: nil, logger: fn _level, _message, _metadata -> raise "sink unavailable" end}
      )

    EventLog.report(event_log, :error, "sink_test", %{component: "test"})

    assert %{running: true, error_count: 1, logged_count: 1} =
             EventLog.snapshot(event_log)

    assert Process.alive?(event_log)
  end

  test "dispatches only emitted events after log deduplication" do
    test_pid = self()
    task_supervisor = start_supervised!({Task.Supervisor, name: nil})

    dispatcher =
      start_supervised!(
        {AlertDispatcher,
         name: nil,
         alert_enabled: true,
         alert_webhook_url: "https://alerts.example.test/v1/alerts",
         alert_levels: [:error],
         alert_sender: fn payload ->
           send(test_pid, {:alert, payload})
           :ok
         end,
         alert_event_log: nil,
         alert_task_supervisor: task_supervisor,
         alert_retry_delay_ms: 1}
      )

    event_log =
      start_supervised!(
        {EventLog,
         name: nil,
         alert_dispatcher: dispatcher,
         dedupe_window_ms: 60_000,
         logger: fn _level, _message, _metadata -> :ok end}
      )

    metadata = %{code: "connection_failed", component: "postgres"}
    EventLog.report(event_log, :error, "database_query_failed", metadata)
    EventLog.report(event_log, :error, "database_query_failed", metadata)

    assert_receive {:alert, %{event: "database_query_failed"}}
    refute_receive {:alert, _payload}, 50

    assert %{error_count: 2, logged_count: 1, suppressed_count: 1} =
             EventLog.snapshot(event_log)
  end
end
