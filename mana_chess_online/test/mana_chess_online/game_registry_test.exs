defmodule ManaChessOnline.GameRegistryTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameRegistry

  test "returns nil and error for missing game ids" do
    game_id = "missing_" <> Integer.to_string(System.unique_integer([:positive]))

    assert GameRegistry.lookup(game_id) == :error
    assert GameRegistry.whereis(game_id) == nil
    refute GameRegistry.registered?(game_id)
  end

  test "builds stable via tuples for game ids" do
    assert GameRegistry.via("game_1") == {:via, Registry, {GameRegistry, "game_1"}}
  end
end
