defmodule ManaChessOnline.Operations.AlertDispatcher do
  @moduledoc """
  Bounded, supervised delivery queue for sanitized operational alerts.

  EventLog owns event deduplication. This process serializes webhook delivery,
  retries transient failures a small number of times, and exposes aggregate
  delivery state without returning its URL, token, or response bodies.
  """

  use GenServer

  alias ManaChessOnline.Operations.{AlertWebhookClient, EventLog}

  @allowed_levels [:warning, :error]
  @ignored_events ["alert_delivery_failed", "alert_queue_overflow"]
  @failure_codes [
    "client_exception",
    "client_exit",
    "delivery_failed",
    "delivery_task_exit",
    "http_4xx",
    "http_5xx",
    "http_retryable",
    "invalid_client_response",
    "network_error",
    "request_exception",
    "request_exit",
    "task_supervisor_unavailable",
    "unexpected_status"
  ]
  @retryable_codes [
    "client_exception",
    "client_exit",
    "http_5xx",
    "http_retryable",
    "network_error",
    "request_exception",
    "request_exit"
  ]
  @metadata_fields [
    :code,
    :component,
    :count,
    :duration_ms,
    :event_type,
    :method,
    :reason_class,
    :route,
    :source,
    :status,
    :suppressed_since_last
  ]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def notify(level, event, metadata \\ %{}),
    do: notify(__MODULE__, level, event, metadata)

  def notify(server, level, event, metadata)
      when level in @allowed_levels and (is_atom(event) or is_binary(event)) and
             (is_map(metadata) or is_list(metadata)) do
    GenServer.cast(server, {:notify, level, event, metadata})
  catch
    :exit, _reason -> :ok
  end

  def notify(_server, _level, _event, _metadata), do: :ok

  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot, 250)
  catch
    :exit, _reason -> unavailable_snapshot()
  end

  @impl true
  def init(opts) do
    config =
      :mana_chess_online
      |> Application.get_env(:operations, [])
      |> Keyword.merge(opts)

    url = normalize_string(Keyword.get(config, :alert_webhook_url, ""), 2_048)
    token = normalize_string(Keyword.get(config, :alert_webhook_token, ""), 4_096)
    enabled = Keyword.get(config, :alert_enabled, url != "") and url != ""
    levels = normalize_levels(Keyword.get(config, :alert_levels, [:error]))
    client = Keyword.get(config, :alert_client, AlertWebhookClient)
    request_options = Keyword.get(config, :alert_request_options, [])

    sender =
      Keyword.get(config, :alert_sender, fn payload ->
        client.deliver(url, token, payload, request_options)
      end)

    {:ok,
     %{
       delivered_count: 0,
       dropped_count: 0,
       enabled: enabled,
       event_log: Keyword.get(config, :alert_event_log, EventLog),
       failed_count: 0,
       in_flight: nil,
       last_delivery_at: nil,
       last_failure_at: nil,
       last_failure_code: nil,
       levels: levels,
       max_attempts: positive_option(config, :alert_max_attempts, 3, 5),
       queue: :queue.new(),
       queue_limit: positive_option(config, :alert_queue_limit, 50, 500),
       queue_size: 0,
       retry_delay_ms: positive_option(config, :alert_retry_delay_ms, 500, 60_000),
       sender: sender,
       task_supervisor:
         Keyword.get(
           config,
           :alert_task_supervisor,
           ManaChessOnline.Operations.AlertTaskSupervisor
         ),
       timestamp: Keyword.get(config, :alert_timestamp, &utc_timestamp/0)
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, public_snapshot(state), state}

  @impl true
  def handle_cast({:notify, level, event, metadata}, state) do
    event = sanitize_event(event)

    cond do
      not state.enabled ->
        {:noreply, state}

      level not in state.levels ->
        {:noreply, state}

      event in @ignored_events ->
        {:noreply, state}

      is_nil(state.in_flight) ->
        {:noreply, start_delivery(state, build_payload(state, level, event, metadata))}

      state.queue_size < state.queue_limit ->
        payload = build_payload(state, level, event, metadata)

        {:noreply,
         %{
           state
           | queue: :queue.in(payload, state.queue),
             queue_size: state.queue_size + 1
         }}

      true ->
        dropped_count = state.dropped_count + 1

        report_internal(state.event_log, :warning, "alert_queue_overflow", %{
          code: "queue_full",
          component: "alert_dispatcher",
          count: dropped_count
        })

        {:noreply, %{state | dropped_count: dropped_count}}
    end
  end

  @impl true
  def handle_info({ref, result}, %{in_flight: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    state =
      state
      |> Map.put(:in_flight, nil)
      |> record_result(result)
      |> start_next()

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{in_flight: ref} = state) do
    state =
      state
      |> Map.put(:in_flight, nil)
      |> record_result({:error, "delivery_task_exit", state.max_attempts})
      |> start_next()

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp start_delivery(state, payload) do
    case safe_start_task(state, payload) do
      {:ok, task} ->
        %{state | in_flight: task.ref}

      {:error, code} ->
        state
        |> record_result({:error, code, 0})
        |> start_next()
    end
  end

  defp safe_start_task(state, payload) do
    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        deliver_with_retry(
          state.sender,
          payload,
          state.max_attempts,
          state.retry_delay_ms
        )
      end)

    {:ok, task}
  rescue
    _error -> {:error, "task_supervisor_unavailable"}
  catch
    _kind, _reason -> {:error, "task_supervisor_unavailable"}
  end

  defp start_next(%{in_flight: nil, queue_size: queue_size} = state) when queue_size > 0 do
    {{:value, payload}, queue} = :queue.out(state.queue)

    state
    |> Map.put(:queue, queue)
    |> Map.put(:queue_size, state.queue_size - 1)
    |> start_delivery(payload)
  end

  defp start_next(state), do: state

  defp deliver_with_retry(sender, payload, max_attempts, retry_delay_ms) do
    Enum.reduce_while(1..max_attempts, {:error, "delivery_failed", 0}, fn attempt, _result ->
      case safe_deliver(sender, payload) do
        :ok ->
          {:halt, {:ok, attempt}}

        {:error, code} when attempt < max_attempts and code in @retryable_codes ->
          Process.sleep(retry_delay_ms * attempt)
          {:cont, {:error, code, attempt}}

        {:error, code} ->
          {:halt, {:error, code, attempt}}
      end
    end)
  end

  defp safe_deliver(sender, payload) do
    case sender.(payload) do
      :ok -> :ok
      {:ok, _value} -> :ok
      {:error, code} -> {:error, sanitize_code(code)}
      _result -> {:error, "invalid_client_response"}
    end
  rescue
    _error -> {:error, "client_exception"}
  catch
    _kind, _reason -> {:error, "client_exit"}
  end

  defp record_result(state, {:ok, _attempts}) do
    %{
      state
      | delivered_count: state.delivered_count + 1,
        last_delivery_at: state.timestamp.()
    }
  end

  defp record_result(state, {:error, code, attempts}) do
    code = sanitize_code(code)

    report_internal(state.event_log, :error, "alert_delivery_failed", %{
      code: code,
      component: "alert_dispatcher",
      count: attempts
    })

    %{
      state
      | failed_count: state.failed_count + 1,
        last_failure_at: state.timestamp.(),
        last_failure_code: code
    }
  end

  defp build_payload(state, level, event, metadata) do
    runtime = Application.get_env(:mana_chess_online, :runtime_metadata, [])

    %{
      schema: "mana_chess.operational_alert.v1",
      service: "mana_chess_online",
      environment: normalize_string(Keyword.get(runtime, :environment, "unknown"), 120),
      release: normalize_string(Keyword.get(runtime, :release, "local"), 120),
      level: Atom.to_string(level),
      event: event,
      occurred_at: state.timestamp.(),
      metadata: sanitize_metadata(metadata)
    }
  end

  defp sanitize_metadata(metadata) when is_list(metadata) do
    if Keyword.keyword?(metadata), do: sanitize_metadata(Map.new(metadata)), else: %{}
  end

  defp sanitize_metadata(metadata) when is_map(metadata) do
    Enum.reduce(@metadata_fields, %{}, fn field, sanitized ->
      case sanitize_value(Map.get(metadata, field)) do
        nil -> sanitized
        value -> Map.put(sanitized, field, value)
      end
    end)
  end

  defp public_snapshot(state) do
    %{
      running: true,
      enabled: state.enabled,
      levels: Enum.map(state.levels, &Atom.to_string/1),
      queue_limit: state.queue_limit,
      queued_count: state.queue_size,
      in_flight: not is_nil(state.in_flight),
      delivered_count: state.delivered_count,
      failed_count: state.failed_count,
      dropped_count: state.dropped_count,
      last_delivery_at: normalize_timestamp(state.last_delivery_at),
      last_failure_at: normalize_timestamp(state.last_failure_at),
      last_failure_code: state.last_failure_code
    }
  end

  defp unavailable_snapshot do
    %{
      running: false,
      enabled: false,
      levels: [],
      queue_limit: 0,
      queued_count: 0,
      in_flight: false,
      delivered_count: 0,
      failed_count: 0,
      dropped_count: 0,
      last_delivery_at: nil,
      last_failure_at: nil,
      last_failure_code: nil
    }
  end

  defp report_internal(nil, _level, _event, _metadata), do: :ok

  defp report_internal(event_log, level, event, metadata) do
    EventLog.report(event_log, level, event, metadata)
  catch
    :exit, _reason -> :ok
  end

  defp normalize_levels(levels) when is_list(levels) do
    levels
    |> Enum.filter(&(&1 in @allowed_levels))
    |> Enum.uniq()
    |> case do
      [] -> [:error]
      normalized -> normalized
    end
  end

  defp normalize_levels(_levels), do: [:error]

  defp sanitize_event(event) when is_atom(event),
    do: event |> Atom.to_string() |> sanitize_event()

  defp sanitize_event(event) when is_binary(event) do
    event
    |> String.replace(["\r", "\n", "\t", " "], "_")
    |> String.slice(0, 80)
  end

  defp sanitize_value(value) when is_binary(value), do: normalize_string(value, 120)
  defp sanitize_value(nil), do: nil

  defp sanitize_value(value) when is_atom(value),
    do: value |> Atom.to_string() |> sanitize_value()

  defp sanitize_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: value

  defp sanitize_value(_value), do: nil

  defp sanitize_code(code) when is_atom(code), do: code |> Atom.to_string() |> sanitize_code()

  defp sanitize_code(code) when code in @failure_codes, do: code
  defp sanitize_code(_code), do: "delivery_failed"

  defp normalize_string(value, limit) when is_binary(value) do
    value
    |> String.replace(["\r", "\n", "\t"], " ")
    |> String.slice(0, limit)
  end

  defp normalize_string(_value, _limit), do: ""

  defp positive_option(config, key, default, maximum) do
    case Keyword.get(config, key, default) do
      value when is_integer(value) and value > 0 -> min(value, maximum)
      _value -> default
    end
  end

  defp utc_timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp normalize_timestamp(value) when is_binary(value), do: value
  defp normalize_timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_timestamp(_value), do: nil
end
