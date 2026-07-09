defmodule ManaChessOnline.RateLimiter do
  @moduledoc false

  def hit(buckets, key, now_ms, max_hits, window_ms)
      when is_integer(now_ms) and is_integer(max_hits) and is_integer(window_ms) and max_hits > 0 and
             window_ms > 0 do
    hits =
      buckets
      |> Map.get(key, [])
      |> recent_hits(now_ms, window_ms)

    if length(hits) >= max_hits do
      {{:error, :rate_limited}, Map.put(buckets, key, hits)}
    else
      {:ok, Map.put(buckets, key, [now_ms | hits])}
    end
  end

  def prune(buckets, now_ms, max_window_ms) do
    buckets
    |> Enum.reduce(%{}, fn {key, hits}, pruned ->
      hits = recent_hits(hits, now_ms, max_window_ms)

      if hits == [] do
        pruned
      else
        Map.put(pruned, key, hits)
      end
    end)
  end

  def take_state(state, key, {max_hits, window_ms}, now_ms) do
    case hit(state.rate_limits, key, now_ms, max_hits, window_ms) do
      {:ok, rate_limits} ->
        {:ok, %{state | rate_limits: rate_limits}}

      {{:error, :rate_limited}, rate_limits} ->
        {:error, :rate_limited, %{state | rate_limits: rate_limits}}
    end
  end

  defp recent_hits(hits, now_ms, window_ms) do
    cutoff = now_ms - window_ms
    Enum.filter(hits, &(&1 > cutoff))
  end
end
