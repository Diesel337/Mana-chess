defmodule ManaChessOnline.RateLimiterTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.RateLimiter

  test "allows hits until the configured window is full" do
    assert {:ok, buckets} = RateLimiter.hit(%{}, {:chat, "player-1"}, 1_000, 2, 1_000)
    assert {:ok, buckets} = RateLimiter.hit(buckets, {:chat, "player-1"}, 1_100, 2, 1_000)

    assert {{:error, :rate_limited}, buckets} =
             RateLimiter.hit(buckets, {:chat, "player-1"}, 1_200, 2, 1_000)

    assert {:ok, _buckets} = RateLimiter.hit(buckets, {:chat, "player-1"}, 2_100, 2, 1_000)
  end

  test "prunes old buckets" do
    buckets = %{
      {:chat, "old"} => [1_000],
      {:chat, "fresh"} => [1_900]
    }

    assert RateLimiter.prune(buckets, 2_000, 500) == %{{:chat, "fresh"} => [1_900]}
  end
end
