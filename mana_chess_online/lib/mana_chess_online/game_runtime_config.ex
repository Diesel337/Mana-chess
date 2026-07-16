defmodule ManaChessOnline.GameRuntimeConfig do
  @moduledoc false

  @defaults %{
    tick_ms: 250,
    auto_tick: true,
    max_dynamic_games: 250,
    dynamic_idle_ttl_ms: 900_000,
    lifecycle_interval_ms: 5_000,
    heartbeat_interval_ms: 30_000
  }

  def tick_ms, do: positive(:tick_ms)
  def auto_tick?, do: value(:auto_tick) == true
  def max_dynamic_games, do: positive(:max_dynamic_games)
  def dynamic_idle_ttl_ms, do: positive(:dynamic_idle_ttl_ms)
  def lifecycle_interval_ms, do: positive(:lifecycle_interval_ms)
  def heartbeat_interval_ms, do: positive(:heartbeat_interval_ms)

  def initial_tick_delay_ms(game_id, tick_ms \\ tick_ms()) do
    1 + :erlang.phash2(game_id, max(tick_ms, 1))
  end

  defp positive(key) do
    case value(key) do
      value when is_integer(value) and value > 0 -> value
      _value -> Map.fetch!(@defaults, key)
    end
  end

  defp value(key) do
    :mana_chess_online
    |> Application.get_env(:game_runtime, [])
    |> Keyword.get(key, Map.fetch!(@defaults, key))
  end
end
