defmodule ManaChessOnline.Persistence.EctoStore do
  @moduledoc false

  @behaviour ManaChessOnline.Persistence.Store

  import Ecto.Query

  alias ManaChessOnline.Persistence.{Entitlement, MatchSummary, SteamUser, SystemSetting}
  alias ManaChessOnline.Repo

  @steam_replace_fields [
    :owner_steam_id,
    :app_id,
    :permanent,
    :site_license,
    :vac_banned,
    :time_expires,
    :last_authenticated_at,
    :updated_at
  ]

  @impl true
  def persist({:steam_identity, attrs}) do
    %SteamUser{}
    |> SteamUser.changeset(attrs)
    |> Repo.insert(
      conflict_target: :steam_id,
      on_conflict: {:replace, @steam_replace_fields},
      returning: true
    )
  end

  def persist({:entitlement, %{steam_id: steam_id} = attrs}) do
    Repo.transaction(fn ->
      case Repo.get_by(SteamUser, steam_id: steam_id) do
        nil ->
          Repo.rollback(:steam_user_not_found)

        user ->
          entitlement_attrs = Map.put(Map.delete(attrs, :steam_id), :steam_user_id, user.id)

          case Repo.insert(Entitlement.changeset(%Entitlement{}, entitlement_attrs),
                 conflict_target: [:steam_user_id, :source, :external_id],
                 on_conflict: {:replace, entitlement_replace_fields(attrs.status)},
                 returning: true
               ) do
            {:ok, entitlement} -> entitlement
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  def persist({:match_summary, attrs}) do
    %MatchSummary{}
    |> MatchSummary.changeset(attrs)
    |> Repo.insert(conflict_target: :event_id, on_conflict: :nothing)
  end

  def persist({:system_setting, attrs}) do
    %SystemSetting{}
    |> SystemSetting.changeset(attrs)
    |> Repo.insert(
      conflict_target: :key,
      on_conflict: {:replace, [:value, :version, :updated_at]},
      returning: true
    )
  end

  def persist(_event), do: {:error, :unsupported_event}

  @impl true
  def get_setting(key) do
    case Repo.get(SystemSetting, key) do
      nil -> {:error, :not_found}
      setting -> {:ok, setting.value}
    end
  end

  @impl true
  def entitlements_for(steam_id) do
    entitlements =
      from(entitlement in Entitlement,
        join: user in SteamUser,
        on: entitlement.steam_user_id == user.id,
        where: user.steam_id == ^steam_id and entitlement.status == "active",
        order_by: [asc: entitlement.sku, asc: entitlement.external_id],
        select: %{
          source: entitlement.source,
          external_id: entitlement.external_id,
          sku: entitlement.sku,
          kind: entitlement.kind,
          status: entitlement.status
        }
      )
      |> Repo.all()

    {:ok, entitlements}
  end

  @impl true
  def health do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", [], timeout: 2_000) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp entitlement_replace_fields("revoked") do
    [:sku, :kind, :status, :metadata, :revoked_at, :updated_at]
  end

  defp entitlement_replace_fields(_status) do
    [:sku, :kind, :status, :metadata, :granted_at, :revoked_at, :updated_at]
  end
end
