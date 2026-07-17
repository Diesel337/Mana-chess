defmodule ManaChessOnline.Operations.Telemetry do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.Operations.EventLog

  @handler_id {__MODULE__, :runtime_events}
  @events [
    [:mana_chess_online, :repo, :query],
    [:phoenix, :channel_handled_in],
    [:phoenix, :channel_joined],
    [:phoenix, :router_dispatch, :exception],
    [:phoenix, :router_dispatch, :stop],
    [:phoenix, :socket_connected]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config =
      :mana_chess_online
      |> Application.get_env(:operations, [])
      |> Keyword.merge(opts)
      |> Map.new()
      |> Map.put_new(:reporter, &EventLog.report/3)

    :telemetry.detach(@handler_id)

    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, config) do
      :ok -> {:ok, config}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  def handle_event(
        [:phoenix, :router_dispatch, :exception],
        measurements,
        metadata,
        config
      ) do
    report(config, :error, "web_request_exception", %{
      component: "phoenix",
      duration_ms: duration_ms(measurements[:duration]),
      method: conn_field(metadata, :method),
      reason_class: reason_class(metadata[:reason]),
      route: metadata[:route]
    })
  end

  def handle_event([:phoenix, :router_dispatch, :stop], measurements, metadata, config) do
    duration_ms = duration_ms(measurements[:duration])

    if duration_ms >= threshold(config, :slow_request_ms, 2_000) do
      report(config, :warning, "web_request_slow", %{
        component: "phoenix",
        duration_ms: duration_ms,
        method: conn_field(metadata, :method),
        route: metadata[:route],
        status: conn_field(metadata, :status)
      })
    end
  end

  def handle_event([:phoenix, :socket_connected], measurements, metadata, config) do
    duration_ms = duration_ms(measurements[:duration])

    cond do
      metadata[:result] == :error ->
        report(config, :warning, "socket_connection_refused", %{
          component: "liveview",
          duration_ms: duration_ms
        })

      duration_ms >= threshold(config, :slow_socket_ms, 2_000) ->
        report(config, :warning, "socket_connection_slow", %{
          component: "liveview",
          duration_ms: duration_ms
        })

      true ->
        :ok
    end
  end

  def handle_event([:phoenix, :channel_joined], measurements, metadata, config) do
    duration_ms = duration_ms(measurements[:duration])

    cond do
      metadata[:result] == :error ->
        report(config, :warning, "channel_join_refused", %{
          component: "liveview",
          duration_ms: duration_ms
        })

      duration_ms >= threshold(config, :slow_socket_ms, 2_000) ->
        report(config, :warning, "channel_join_slow", %{
          component: "liveview",
          duration_ms: duration_ms
        })

      true ->
        :ok
    end
  end

  def handle_event([:phoenix, :channel_handled_in], measurements, metadata, config) do
    duration_ms = duration_ms(measurements[:duration])

    if duration_ms >= threshold(config, :slow_socket_ms, 2_000) do
      report(config, :warning, "channel_event_slow", %{
        component: "liveview",
        duration_ms: duration_ms,
        event_type: metadata[:event]
      })
    end
  end

  def handle_event([:mana_chess_online, :repo, :query], measurements, metadata, config) do
    duration_ms = query_duration_ms(measurements)

    cond do
      query_error?(metadata[:result]) ->
        report(config, :error, "database_query_failed", %{
          component: "postgres",
          duration_ms: duration_ms,
          reason_class: reason_class(metadata[:result]),
          source: metadata[:source]
        })

      duration_ms >= threshold(config, :slow_query_ms, 1_000) ->
        report(config, :warning, "database_query_slow", %{
          component: "postgres",
          duration_ms: duration_ms,
          source: metadata[:source]
        })

      true ->
        :ok
    end
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp report(%{reporter: reporter}, level, event, metadata) when is_function(reporter, 3),
    do: reporter.(level, event, metadata)

  defp report(_config, _level, _event, _metadata), do: :ok

  defp conn_field(%{conn: conn}, field) when is_map(conn), do: Map.get(conn, field)
  defp conn_field(_metadata, _field), do: nil

  defp duration_ms(duration) when is_integer(duration) do
    duration
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1_000)
    |> Float.round(2)
  end

  defp duration_ms(_duration), do: 0.0

  defp query_duration_ms(measurements) do
    duration =
      Map.get_lazy(measurements, :total_time, fn ->
        Enum.reduce([:queue_time, :query_time, :decode_time], 0, fn key, total ->
          total + Map.get(measurements, key, 0)
        end)
      end)

    duration_ms(duration)
  end

  defp query_error?({:error, _reason}), do: true
  defp query_error?({:error, _query, _reason}), do: true
  defp query_error?(_result), do: false

  defp reason_class({:error, reason}), do: reason_class(reason)
  defp reason_class({:error, _query, reason}), do: reason_class(reason)
  defp reason_class(%{__struct__: module}) when is_atom(module), do: inspect(module)
  defp reason_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_class({reason, _details}) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_class(_reason), do: "unknown"

  defp threshold(config, key, default) do
    case Map.get(config, key, default) do
      value when is_integer(value) and value > 0 -> value
      _value -> default
    end
  end
end
