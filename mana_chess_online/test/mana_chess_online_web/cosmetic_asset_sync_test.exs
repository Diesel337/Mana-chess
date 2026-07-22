defmodule ManaChessOnlineWeb.CosmeticAssetSyncTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  @js_assets ~w(
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
    for asset <- @js_assets do
      source = File.read!(Path.join([@root, "assets", "js", asset]))
      served = File.read!(Path.join([@root, "priv", "static", "assets", "js", asset]))

      assert served == source, "#{asset} must be copied to priv/static after editing"
    end
  end

  test "premium cosmetic stylesheet matches its served static copy" do
    source = File.read!(Path.join([@root, "assets", "css", "premium_cosmetics.css"]))
    served = File.read!(Path.join([@root, "priv", "static", "assets", "css", "premium_cosmetics.css"]))

    assert served == source
  end

  test "cosmetic browser stylesheet matches its served static copy" do
    source = File.read!(Path.join([@root, "assets", "css", "cosmetic_browser.css"]))

    served =
      File.read!(Path.join([@root, "priv", "static", "assets", "css", "cosmetic_browser.css"]))

    assert served == source
  end

  test "flat piece stylesheet matches its served static copy" do
    source = File.read!(Path.join([@root, "assets", "css", "flat_pieces.css"]))
    served = File.read!(Path.join([@root, "priv", "static", "assets", "css", "flat_pieces.css"]))

    assert served == source
  end
end
