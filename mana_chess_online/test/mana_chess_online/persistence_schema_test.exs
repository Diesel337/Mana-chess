defmodule ManaChessOnline.Persistence.SchemaTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Persistence.{Entitlement, MatchSummary, SteamUser, SystemSetting}

  @now ~U[2026-07-16 12:30:00.123456Z]

  test "validates Steam users and ownership fields" do
    changeset =
      SteamUser.changeset(%SteamUser{}, %{
        steam_id: "76561198000000001",
        owner_steam_id: "76561198000000002",
        app_id: 123_456,
        first_authenticated_at: @now,
        last_authenticated_at: @now
      })

    assert changeset.valid?
    refute SteamUser.changeset(%SteamUser{}, %{}).valid?
  end

  test "validates entitlements, match summaries, and versioned settings" do
    entitlement =
      Entitlement.changeset(%Entitlement{}, %{
        steam_user_id: 1,
        source: "steam_dlc",
        external_id: "222222",
        sku: "founder_pack",
        kind: "cosmetic_pack",
        status: "active",
        granted_at: @now
      })

    summary =
      MatchSummary.changeset(%MatchSummary{}, %{
        event_id: Ecto.UUID.generate(),
        game_id: "game_1",
        mode: "public",
        result: "draw",
        finished_at: @now
      })

    setting =
      SystemSetting.changeset(%SystemSetting{}, %{
        key: "global_game_settings",
        value: %{"max_elixir" => 10},
        version: 2
      })

    assert entitlement.valid?
    assert summary.valid?
    assert setting.valid?

    refute Entitlement.changeset(%Entitlement{}, %{
             steam_user_id: 1,
             source: "steam_dlc",
             external_id: "333333",
             sku: "founder_pack",
             kind: "cosmetic_pack",
             status: "revoked"
           }).valid?

    refute MatchSummary.changeset(%MatchSummary{}, %{
             event_id: Ecto.UUID.generate(),
             game_id: "game_2",
             mode: "public",
             result: "white_win",
             winner_color: "black",
             finished_at: @now
           }).valid?
  end
end
