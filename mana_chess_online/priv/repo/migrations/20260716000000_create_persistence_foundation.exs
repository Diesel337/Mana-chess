defmodule ManaChessOnline.Repo.Migrations.CreatePersistenceFoundation do
  use Ecto.Migration

  def change do
    create table(:steam_users) do
      add(:steam_id, :string, null: false)
      add(:owner_steam_id, :string, null: false)
      add(:app_id, :bigint, null: false)
      add(:permanent, :boolean, null: false, default: false)
      add(:site_license, :boolean, null: false, default: false)
      add(:vac_banned, :boolean, null: false, default: false)
      add(:time_expires, :string)
      add(:first_authenticated_at, :utc_datetime_usec, null: false)
      add(:last_authenticated_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:steam_users, [:steam_id]))
    create(index(:steam_users, [:owner_steam_id]))
    create(index(:steam_users, [:last_authenticated_at]))

    create(
      constraint(:steam_users, :steam_users_app_id_valid,
        check: "app_id > 0 AND app_id <= 4294967295"
      )
    )

    create table(:steam_entitlements) do
      add(:steam_user_id, references(:steam_users, on_delete: :delete_all, type: :bigint),
        null: false
      )

      add(:source, :string, null: false)
      add(:external_id, :string, null: false)
      add(:sku, :string, null: false)
      add(:kind, :string, null: false)
      add(:status, :string, null: false, default: "active")
      add(:metadata, :map, null: false, default: %{})
      add(:granted_at, :utc_datetime_usec)
      add(:revoked_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:steam_entitlements, [:steam_user_id, :source, :external_id]))
    create(index(:steam_entitlements, [:sku, :status]))

    create(
      constraint(:steam_entitlements, :steam_entitlements_status_valid,
        check: "status IN ('active', 'revoked')"
      )
    )

    create(
      constraint(:steam_entitlements, :steam_entitlements_lifecycle_valid,
        check:
          "(status = 'active' AND granted_at IS NOT NULL AND revoked_at IS NULL) OR " <>
            "(status = 'revoked' AND revoked_at IS NOT NULL)"
      )
    )

    create table(:match_summaries) do
      add(:event_id, :uuid, null: false)
      add(:game_id, :string, null: false)
      add(:mode, :string, null: false)
      add(:white_player_id, :string)
      add(:black_player_id, :string)
      add(:result, :string, null: false)
      add(:winner_color, :string)
      add(:finished_at, :utc_datetime_usec, null: false)
      add(:settings, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:match_summaries, [:event_id]))
    create(index(:match_summaries, [:finished_at]))
    create(index(:match_summaries, [:mode, :result]))
    create(index(:match_summaries, [:white_player_id]))
    create(index(:match_summaries, [:black_player_id]))

    create(
      constraint(:match_summaries, :match_summaries_mode_valid,
        check: "mode IN ('public', 'private', 'practice')"
      )
    )

    create(
      constraint(:match_summaries, :match_summaries_result_valid,
        check: "result IN ('white_win', 'black_win', 'draw')"
      )
    )

    create(
      constraint(:match_summaries, :match_summaries_winner_valid,
        check:
          "(result = 'draw' AND winner_color IS NULL) OR " <>
            "(result = 'white_win' AND winner_color = 'white') OR " <>
            "(result = 'black_win' AND winner_color = 'black')"
      )
    )

    create table(:system_settings, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:value, :map, null: false, default: %{})
      add(:version, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    create(constraint(:system_settings, :system_settings_version_valid, check: "version > 0"))
  end
end
