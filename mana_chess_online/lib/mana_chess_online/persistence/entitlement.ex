defmodule ManaChessOnline.Persistence.Entitlement do
  use Ecto.Schema
  import Ecto.Changeset

  schema "steam_entitlements" do
    field(:source, :string)
    field(:external_id, :string)
    field(:sku, :string)
    field(:kind, :string)
    field(:status, :string, default: "active")
    field(:metadata, :map, default: %{})
    field(:granted_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)

    belongs_to(:steam_user, ManaChessOnline.Persistence.SteamUser)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entitlement, attrs) do
    entitlement
    |> cast(attrs, [
      :steam_user_id,
      :source,
      :external_id,
      :sku,
      :kind,
      :status,
      :metadata,
      :granted_at,
      :revoked_at
    ])
    |> validate_required([:steam_user_id, :source, :external_id, :sku, :kind, :status])
    |> validate_inclusion(:status, ["active", "revoked"])
    |> validate_length(:source, max: 40)
    |> validate_length(:external_id, max: 120)
    |> validate_length(:sku, max: 120)
    |> validate_length(:kind, max: 40)
    |> validate_lifecycle()
    |> check_constraint(:status, name: :steam_entitlements_status_valid)
    |> check_constraint(:status, name: :steam_entitlements_lifecycle_valid)
    |> unique_constraint([:steam_user_id, :source, :external_id])
  end

  defp validate_lifecycle(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :granted_at),
          get_field(changeset, :revoked_at)} do
      {"active", %DateTime{}, nil} ->
        changeset

      {"active", nil, _revoked_at} ->
        add_error(changeset, :granted_at, "is required when active")

      {"active", _granted_at, %DateTime{}} ->
        add_error(changeset, :revoked_at, "must be empty when active")

      {"revoked", _granted_at, %DateTime{}} ->
        changeset

      {"revoked", _granted_at, nil} ->
        add_error(changeset, :revoked_at, "is required when revoked")

      {_status, _granted_at, _revoked_at} ->
        changeset
    end
  end
end
