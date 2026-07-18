defmodule ManaChessOnlineWeb.GameEffectAssetSyncTest do
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)

  test "game effect assets match their served static copies" do
    for {kind, asset} <- [{"js", "game_effects.js"}, {"css", "game_effects.css"}] do
      source = File.read!(Path.join([@root, "assets", kind, asset]))
      served = File.read!(Path.join([@root, "priv", "static", "assets", kind, asset]))

      assert served == source, "#{asset} must be copied to priv/static after editing"
    end
  end

  test "the served LiveView loader registers the game effect hook" do
    loader = File.read!(Path.join([@root, "priv", "static", "assets", "js", "app.js"]))

    assert loader =~ "GameEffects: window.ManaChessGameEffectsHook"
  end
end
