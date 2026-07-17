defmodule ManaChessOnline.Operations.AlertDispatcherTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Operations.AlertDispatcher

  test "delivers configured levels with a bounded sanitized payload" do
    test_pid = self()

    dispatcher =
      start_dispatcher(fn payload ->
        send(test_pid, {:delivered, payload})
        :ok
      end)

    AlertDispatcher.notify(dispatcher, :warning, "slow_request", %{component: "phoenix"})
    refute_receive {:delivered, _payload}, 25

    AlertDispatcher.notify(dispatcher, :error, "database_query_failed", %{
      code: "query_failed",
      component: "postgres",
      database_url: "postgres://private",
      player_id: "private-player"
    })

    assert_receive {:delivered, payload}
    assert payload.schema == "mana_chess.operational_alert.v1"
    assert payload.environment == "test"
    assert payload.release == "local"
    assert payload.level == "error"
    assert payload.event == "database_query_failed"
    assert payload.metadata == %{code: "query_failed", component: "postgres"}
    refute inspect(payload) =~ "private"

    assert eventually(fn -> AlertDispatcher.snapshot(dispatcher).delivered_count == 1 end)

    assert %{
             enabled: true,
             failed_count: 0,
             dropped_count: 0,
             queued_count: 0,
             in_flight: false
           } = AlertDispatcher.snapshot(dispatcher)
  end

  test "retries transient delivery failures and records one success" do
    test_pid = self()
    counter = start_supervised!({Agent, fn -> 0 end})

    dispatcher =
      start_dispatcher(
        fn _payload ->
          attempt = Agent.get_and_update(counter, fn value -> {value + 1, value + 1} end)
          send(test_pid, {:attempt, attempt})
          if attempt == 1, do: {:error, "network_error"}, else: :ok
        end,
        alert_max_attempts: 2,
        alert_retry_delay_ms: 1
      )

    AlertDispatcher.notify(dispatcher, :error, "web_request_exception", %{})

    assert_receive {:attempt, 1}
    assert_receive {:attempt, 2}
    assert eventually(fn -> AlertDispatcher.snapshot(dispatcher).delivered_count == 1 end)

    snapshot = AlertDispatcher.snapshot(dispatcher)
    assert snapshot.failed_count == 0
    assert snapshot.last_delivery_at == "2026-07-17T21:00:00Z"
  end

  test "bounds its queue and drops excess alerts without blocking callers" do
    test_pid = self()

    dispatcher =
      start_dispatcher(
        fn payload ->
          send(test_pid, {:started, payload.event, self()})

          receive do
            :release -> :ok
          after
            1_000 -> {:error, "test_timeout"}
          end
        end,
        alert_queue_limit: 1,
        alert_max_attempts: 1
      )

    AlertDispatcher.notify(dispatcher, :error, "first", %{})
    assert_receive {:started, "first", first_task}

    AlertDispatcher.notify(dispatcher, :error, "second", %{})
    AlertDispatcher.notify(dispatcher, :error, "third", %{})

    assert eventually(fn ->
             snapshot = AlertDispatcher.snapshot(dispatcher)
             snapshot.queued_count == 1 and snapshot.dropped_count == 1
           end)

    send(first_task, :release)
    assert_receive {:started, "second", second_task}
    send(second_task, :release)

    assert eventually(fn -> AlertDispatcher.snapshot(dispatcher).delivered_count == 2 end)
  end

  test "records only stable failure codes after exhausting retries" do
    dispatcher =
      start_dispatcher(
        fn _payload -> {:error, "postgres://private-provider-detail"} end,
        alert_max_attempts: 2,
        alert_retry_delay_ms: 1
      )

    AlertDispatcher.notify(dispatcher, :error, "database_query_failed", %{})

    assert eventually(fn -> AlertDispatcher.snapshot(dispatcher).failed_count == 1 end)

    assert %{
             delivered_count: 0,
             failed_count: 1,
             last_failure_code: "delivery_failed",
             last_failure_at: "2026-07-17T21:00:00Z"
           } = AlertDispatcher.snapshot(dispatcher)

    refute inspect(AlertDispatcher.snapshot(dispatcher)) =~ "private-provider"
  end

  defp start_dispatcher(sender, opts \\ []) do
    task_supervisor = start_supervised!({Task.Supervisor, name: nil})

    defaults = [
      name: nil,
      alert_enabled: true,
      alert_webhook_url: "https://alerts.example.test/v1/alerts",
      alert_levels: [:error],
      alert_sender: sender,
      alert_event_log: nil,
      alert_task_supervisor: task_supervisor,
      alert_timestamp: fn -> "2026-07-17T21:00:00Z" end
    ]

    start_supervised!({AlertDispatcher, Keyword.merge(defaults, opts)})
  end

  defp eventually(predicate, attempts \\ 50)

  defp eventually(predicate, attempts) when attempts > 0 do
    if predicate.() do
      true
    else
      Process.sleep(10)
      eventually(predicate, attempts - 1)
    end
  end

  defp eventually(_predicate, 0), do: false
end
