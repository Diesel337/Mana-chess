defmodule ManaChessOnline.Persistence.EctoStore do
  @moduledoc false

  @behaviour ManaChessOnline.Persistence.Store

  import Ecto.Query

  alias ManaChessOnline.CompetitiveRating

  alias ManaChessOnline.Persistence.{
    Entitlement,
    MatchSummary,
    PlayerRating,
    SteamUser,
    SystemSetting
  }

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
    Repo.transaction(fn ->
      case Repo.insert(MatchSummary.changeset(%MatchSummary{}, attrs)) do
        {:ok, summary} ->
          apply_competitive_rating(summary)

        {:error, changeset} ->
          if duplicate_event?(changeset) do
            Repo.get_by(MatchSummary, event_id: attrs.event_id) || Repo.rollback(changeset)
          else
            Repo.rollback(changeset)
          end
      end
    end)
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
  def competitive_profile(player_id) do
    profile =
      case Repo.get_by(PlayerRating, player_id: player_id) do
        nil -> CompetitiveRating.default_profile(player_id)
        rating -> rating_profile(rating)
      end

    {:ok, profile}
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

  defp apply_competitive_rating(summary) do
    if CompetitiveRating.eligible_match?(summary) do
      white = load_rating(summary.white_player_id)
      black = load_rating(summary.black_player_id)
      result = CompetitiveRating.rate_pair(white, black, summary.result)

      persist_rating(result.white, summary.finished_at)
      persist_rating(result.black, summary.finished_at)

      metadata =
        Map.put(summary.metadata || %{}, "rating", %{
          "white_before" => result.white_before,
          "white_after" => result.white.rating,
          "white_change" => result.white_change,
          "black_before" => result.black_before,
          "black_after" => result.black.rating,
          "black_change" => result.black_change
        })

      summary
      |> Ecto.Changeset.change(metadata: metadata)
      |> persist_or_rollback()
    else
      summary
    end
  end

  defp load_rating(player_id) do
    case Repo.get_by(PlayerRating, player_id: player_id) do
      nil -> CompetitiveRating.default_profile(player_id)
      rating -> rating_profile(rating)
    end
  end

  defp rating_profile(rating) do
    CompetitiveRating.normalize_profile(%{
      player_id: rating.player_id,
      rating: rating.rating,
      games_played: rating.games_played,
      wins: rating.wins,
      losses: rating.losses,
      draws: rating.draws
    })
  end

  defp persist_rating(profile, finished_at) do
    attrs = %{
      player_id: profile.player_id,
      rating: profile.rating,
      games_played: profile.games_played,
      wins: profile.wins,
      losses: profile.losses,
      draws: profile.draws,
      last_match_at: finished_at
    }

    changeset =
      case Repo.get_by(PlayerRating, player_id: profile.player_id) do
        nil -> PlayerRating.changeset(%PlayerRating{}, attrs)
        rating -> PlayerRating.changeset(rating, attrs)
      end

    persist_or_rollback(changeset)
  end

  defp persist_or_rollback(%Ecto.Changeset{} = changeset) do
    changeset
    |> Repo.insert_or_update()
    |> persist_or_rollback()
  end

  defp persist_or_rollback({:ok, value}), do: value
  defp persist_or_rollback({:error, reason}), do: Repo.rollback(reason)

  defp duplicate_event?(changeset) do
    Enum.any?(changeset.errors, fn
      {:event_id, {_message, options}} -> options[:constraint] == :unique
      _error -> false
    end)
  end
end
