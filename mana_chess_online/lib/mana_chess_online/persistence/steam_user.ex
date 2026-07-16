defmodule ManaChessOnline.Persistence.SteamUser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "steam_users" do
    field(:steam_id, :string)
    field(:owner_steam_id, :string)
    field(:app_id, :integer)
    field(:permanent, :boolean, default: false)
    field(:site_license, :boolean, default: false)
    field(:vac_banned, :boolean, default: false)
    field(:time_expires, :string)
    field(:first_authenticated_at, :utc_datetime_usec)
    field(:last_authenticated_at, :utc_datetime_usec)

    has_many(:entitlements, ManaChessOnline.Persistence.Entitlement)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :steam_id,
      :owner_steam_id,
      :app_id,
      :permanent,
      :site_license,
      :vac_banned,
      :time_expires,
      :first_authenticated_at,
      :last_authenticated_at
    ])
    |> validate_required([
      :steam_id,
      :owner_steam_id,
      :app_id,
      :first_authenticated_at,
      :last_authenticated_at
    ])
    |> validate_format(:steam_id, ~r/\A[0-9]{16,20}\z/)
    |> validate_format(:owner_steam_id, ~r/\A[0-9]{16,20}\z/)
    |> validate_number(:app_id, greater_than: 0, less_than_or_equal_to: 4_294_967_295)
    |> validate_length(:time_expires, max: 80)
    |> check_constraint(:app_id, name: :steam_users_app_id_valid)
    |> unique_constraint(:steam_id)
  end
end
