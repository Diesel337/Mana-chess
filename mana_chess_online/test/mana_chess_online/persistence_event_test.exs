defmodule ManaChessOnline.Persistence.EventTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Persistence.Event

  @now ~U[2026-07-16 12:30:00.123456Z]
  @steam_id "76561198000000001"
  @owner_steam_id "76561198000000002"

  test "normalizes verified Steam identity without accepting ticket material" do
    identity = %{
      steam_id: @steam_id,
      owner_steam_id: @owner_steam_id,
      app_id: 123_456,
      permanent: true,
      site_license: false,
      vac_banned: false,
      time_expires: "never",
      ticket: "must-not-persist"
    }

    assert {:ok, {:steam_identity, attrs}} = Event.steam_identity(identity, @now)
    assert attrs.steam_id == @steam_id
    assert attrs.owner_steam_id == @owner_steam_id
    assert attrs.app_id == 123_456
    assert attrs.first_authenticated_at == @now
    refute Map.has_key?(attrs, :ticket)

    assert :error = Event.steam_identity(%{identity | steam_id: "bad"}, @now)
  end

  test "builds JSON-safe terminal match summaries" do
    game = %{
      id: "private_event_test",
      private?: true,
      practice?: false,
      status: {:checkmate, :white, :black},
      players: %{white: "steam_#{@steam_id}", black: "steam_#{@owner_steam_id}"},
      bot_enabled?: false,
      bot_color: nil,
      finished_at: 42_000,
      settings: %{cooldown_enabled: true, costs: %{queen: 6.0}},
      log: ["mate", "move"]
    }

    assert {:ok, {:match_summary, attrs}} = Event.match_summary(game, @now)
    assert Ecto.UUID.cast(attrs.event_id) == {:ok, attrs.event_id}
    assert attrs.mode == "private"
    assert attrs.result == "white_win"
    assert attrs.winner_color == "white"
    assert attrs.settings == %{"cooldown_enabled" => true, "costs" => %{"queen" => 6.0}}
    assert attrs.metadata["game_finished_at_ms"] == 42_000
    assert attrs.metadata["log_entries"] == 2

    assert :ignore = Event.match_summary(%{game | status: :playing}, @now)
  end

  test "normalizes active and revoked Steam entitlements" do
    attrs = %{
      steam_id: @steam_id,
      source: "steam_\rdlc",
      external_id: "222222",
      sku: "founder_board_pack",
      kind: "cosmetic_pack",
      metadata: %{palette: :founder}
    }

    assert {:ok, {:entitlement, active}} = Event.entitlement(attrs, @now)
    assert active.status == "active"
    assert active.source == "steam_dlc"
    assert active.granted_at == @now
    assert active.revoked_at == nil
    assert active.metadata == %{"palette" => "founder"}

    assert {:ok, {:entitlement, revoked}} =
             Event.entitlement(Map.put(attrs, :status, "revoked"), @now)

    assert revoked.granted_at == nil
    assert revoked.revoked_at == @now
  end
end
