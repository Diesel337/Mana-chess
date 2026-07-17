defmodule ManaChessOnline.Operations.EventLog do
  @moduledoc """
  Bounded, privacy-safe operational event buffer with log deduplication.

  Callers may only attach fields from the explicit allowlist below. This keeps
  credentials, player identities, request payloads, and database URLs out of
  both the in-memory diagnostics and production logs.
  """

  use GenServer

  require Logger

  alias ManaChessOnline.Operations.AlertDispatcher

  @levels [:info, :warning, :error]
  @allowed_fields [
    :code,
    :component,
    :count,
    :duration_ms,
    :event_type,
    :method,
    :reason_class,
    :route,
    :source,
    :status
  ]
  @fingerprint_fields [:code, :component, :route, :source]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    start_opts = if is_nil(name), do: [], else: [name: name]
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def report(level, event, metadata \\ %{}),
    do: report(__MODULE__, level, event, metadata)

  def report(server, level, event, metadata)
      when level in @levels and (is_atom(event) or is_binary(event)) and
             (is_map(metadata) or is_list(metadata)) do
    GenServer.cast(server, {:report, level, event, metadata})
  end

  def report(_server, _level, _event, _metadata), do: :ok

  def snapshot(server \\ __MODULE__) do
    GenServer.call(server, :snapshot, 250)
  catch
    :exit, _reason -> unavailable_snapshot()
  end

  def recent(limit \\ 20), do: recent(__MODULE__, limit)

  def recent(server, limit) when is_integer(limit) do
    GenServer.call(server, {:recent, max(limit, 0)})
  catch
    :exit, _reason -> []
  end

  @impl true
  def init(opts) do
    config =
      :mana_chess_online
      |> Application.get_env(:operations, [])
      |> Keyword.merge(opts)

    timestamp = Keyword.get(config, :timestamp, &utc_timestamp/0)

    {:ok,
     %{
       clock: Keyword.get(config, :clock, fn -> System.monotonic_time(:millisecond) end),
       alert_dispatcher: Keyword.get(config, :alert_dispatcher, AlertDispatcher),
       counts: %{error: 0, info: 0, warning: 0},
       dedupe: %{},
       dedupe_window_ms: positive_option(config, :dedupe_window_ms, 60_000),
       events: [],
       last_event: nil,
       last_event_at: nil,
       last_level: nil,
       logged_count: 0,
       logger: Keyword.get(config, :logger),
       max_events: positive_option(config, :max_events, 100),
       started_at: timestamp.(),
       suppressed_count: 0,
       timestamp: timestamp
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, public_snapshot(state), state}

  def handle_call({:recent, limit}, _from, state) do
    {:reply, Enum.take(state.events, min(limit, state.max_events)), state}
  end

  @impl true
  def handle_cast({:report, level, event, metadata}, state) do
    now_ms = state.clock.()
    event = sanitize_event(event)
    metadata = sanitize_metadata(metadata)
    fingerprint = fingerprint(level, event, metadata)
    previous = Map.get(state.dedupe, fingerprint)

    state =
      state
      |> increment(level)
      |> Map.put(:last_event, event)
      |> Map.put(:last_event_at, state.timestamp.())
      |> Map.put(:last_level, Atom.to_string(level))

    if duplicate?(previous, now_ms, state.dedupe_window_ms) do
      dedupe =
        Map.put(state.dedupe, fingerprint, %{
          previous
          | suppressed: previous.suppressed + 1
        })

      {:noreply, %{state | dedupe: dedupe, suppressed_count: state.suppressed_count + 1}}
    else
      suppressed = if previous, do: previous.suppressed, else: 0

      payload =
        metadata
        |> Map.put(:event, event)
        |> Map.put(:event_at, state.timestamp.())
        |> Map.put(:level, Atom.to_string(level))
        |> maybe_put(:suppressed_since_last, suppressed)

      safe_emit(state.logger, level, payload)
      dispatch_alert(state.alert_dispatcher, level, event, payload)

      dedupe =
        state.dedupe
        |> Map.put(fingerprint, %{last_logged_ms: now_ms, suppressed: 0})
        |> prune_dedupe(now_ms, state.dedupe_window_ms)

      {:noreply,
       %{
         state
         | dedupe: dedupe,
           events: Enum.take([payload | state.events], state.max_events),
           logged_count: state.logged_count + 1
       }}
    end
  end

  defp emit(nil, level, payload) do
    Logger.log(level, "operational_event", Map.to_list(payload))
  end

  defp emit(logger, level, payload) when is_function(logger, 3) do
    logger.(level, "operational_event", Map.to_list(payload))
  end

  defp safe_emit(logger, level, payload) do
    emit(logger, level, payload)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp dispatch_alert(nil, _level, _event, _payload), do: :ok

  defp dispatch_alert(dispatcher, level, event, payload) do
    AlertDispatcher.notify(dispatcher, level, event, payload)
  catch
    :exit, _reason -> :ok
  end

  defp increment(state, level) do
    update_in(state, [:counts, level], &(&1 + 1))
  end

  defp public_snapshot(state) do
    Map.merge(runtime_metadata(), %{
      running: true,
      started_at: normalize_timestamp(state.started_at),
      info_count: state.counts.info,
      warning_count: state.counts.warning,
      error_count: state.counts.error,
      logged_count: state.logged_count,
      suppressed_count: state.suppressed_count,
      last_event: state.last_event,
      last_level: state.last_level,
      last_event_at: normalize_timestamp(state.last_event_at)
    })
  end

  defp unavailable_snapshot do
    Map.merge(runtime_metadata(), %{
      running: false,
      started_at: nil,
      info_count: 0,
      warning_count: 0,
      error_count: 0,
      logged_count: 0,
      suppressed_count: 0,
      last_event: nil,
      last_level: nil,
      last_event_at: nil
    })
  end

  defp sanitize_metadata(metadata) when is_list(metadata) do
    if Keyword.keyword?(metadata), do: sanitize_metadata(Map.new(metadata)), else: %{}
  end

  defp sanitize_metadata(metadata) when is_map(metadata) do
    Enum.reduce(@allowed_fields, %{}, fn field, sanitized ->
      case sanitize_value(Map.get(metadata, field)) do
        nil -> sanitized
        value -> Map.put(sanitized, field, value)
      end
    end)
  end

  defp sanitize_event(event) when is_atom(event),
    do: event |> Atom.to_string() |> sanitize_event()

  defp sanitize_event(event) when is_binary(event) do
    event
    |> String.replace(["\r", "\n", "\t", " "], "_")
    |> String.slice(0, 80)
  end

  defp sanitize_value(value) when is_binary(value) do
    value
    |> String.replace(["\r", "\n", "\t"], " ")
    |> String.slice(0, 120)
  end

  defp sanitize_value(nil), do: nil
  defp sanitize_value(value) when is_atom(value), do: Atom.to_string(value)

  defp sanitize_value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: value

  defp sanitize_value(_value), do: nil

  defp fingerprint(level, event, metadata) do
    {level, event, Map.take(metadata, @fingerprint_fields)}
  end

  defp duplicate?(nil, _now_ms, _window_ms), do: false

  defp duplicate?(previous, now_ms, window_ms),
    do: now_ms - previous.last_logged_ms < window_ms

  defp prune_dedupe(dedupe, now_ms, window_ms) do
    cutoff = now_ms - window_ms * 2

    dedupe
    |> Enum.reject(fn {_fingerprint, entry} -> entry.last_logged_ms < cutoff end)
    |> Map.new()
  end

  defp maybe_put(map, _key, 0), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp positive_option(config, key, default) do
    case Keyword.get(config, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end

  defp utc_timestamp, do: DateTime.utc_now() |> DateTime.to_iso8601()
  defp normalize_timestamp(value) when is_binary(value), do: value
  defp normalize_timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_timestamp(_value), do: nil

  defp runtime_metadata do
    runtime = Application.get_env(:mana_chess_online, :runtime_metadata, [])

    %{
      environment: sanitize_value(Keyword.get(runtime, :environment)) || "unknown",
      release: sanitize_value(Keyword.get(runtime, :release)) || "local"
    }
  end
end
