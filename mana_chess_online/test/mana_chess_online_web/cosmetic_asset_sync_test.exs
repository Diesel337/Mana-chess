defmodule ManaChessOnlineWeb.CosmeticAssetSyncTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @assets ~w(
    cosmetic_actions.js
    cosmetic_catalog.js
    cosmetic_fallback.js
    cosmetic_progression.js
    cosmetic_session.js
    cosmetics.js
    local_stats_events.js
    local_stats_hook.js
  )

  test "cosmetic source modules match their served static copies" do
    for asset <- @assets do
      source = File.read!(Path.join([@root, "assets", "js", asset]))
      served = File.read!(Path.join([@root, "priv", "static", "assets", "js", asset]))

      assert served == source, "#{asset} must be copied to priv/static after editing"
    end
  end
end
