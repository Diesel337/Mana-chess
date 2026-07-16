defmodule ManaChessOnline.Persistence.SystemSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  schema "system_settings" do
    field(:value, :map, default: %{})
    field(:version, :integer, default: 1)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :version])
    |> validate_required([:key, :value, :version])
    |> validate_length(:key, max: 120)
    |> validate_number(:version, greater_than: 0)
    |> check_constraint(:version, name: :system_settings_version_valid)
  end
end
