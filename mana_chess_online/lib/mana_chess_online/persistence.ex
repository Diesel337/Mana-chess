defmodule ManaChessOnline.Persistence do
  @moduledoc """
  Optional persistence boundary for Steam identity, commerce, settings, and match history.

  Gameplay and authentication enqueue writes through a supervised writer. When no
  database is configured, reads report `:disabled` and writes are safely skipped.
  """

  alias ManaChessOnline.CompetitiveRating
  alias ManaChessOnline.Persistence.{EctoStore, Event, Writer}

  @steam_id_pattern ~r/\A[0-9]{16,20}\z/

  def children do
    repo_children = if enabled?(), do: [ManaChessOnline.Repo], else: []

    repo_children ++
      [
        {Writer, enabled: enabled?(), store: store_module()}
      ]
  end

  def enabled?, do: Keyword.get(config(), :enabled, false) == true

  def record_steam_identity(identity, authenticated_at \\ DateTime.utc_now()) do
    case Event.steam_identity(identity, authenticated_at) do
      {:ok, event} -> record_event(event)
      :error -> :ok
    end
  end

  def record_match(game, finished_at \\ DateTime.utc_now()) do
    case Event.match_summary(game, finished_at) do
      {:ok, event} -> record_event(event)
      :ignore -> :ok
    end
  end

  def record_entitlement(attrs, observed_at \\ DateTime.utc_now()) do
    case Event.entitlement(attrs, observed_at) do
      {:ok, event} -> record_event(event)
      :error -> :ok
    end
  end

  def put_setting(key, value, version \\ 1) do
    case Event.system_setting(key, value, version) do
      {:ok, event} -> record_event(event)
      :error -> :ok
    end
  end

  def get_setting(key) when is_binary(key) do
    if enabled?(), do: safe_store_call(:get_setting, [key]), else: {:error, :disabled}
  end

  def get_setting(_key), do: {:error, :invalid_key}

  def entitlements_for(steam_id) when is_binary(steam_id) do
    cond do
      not enabled?() -> {:error, :disabled}
      not Regex.match?(@steam_id_pattern, steam_id) -> {:error, :invalid_steam_id}
      true -> safe_store_call(:entitlements_for, [steam_id])
    end
  end

  def entitlements_for(_steam_id), do: {:error, :invalid_steam_id}

  def competitive_profile(player_id) when is_binary(player_id) and byte_size(player_id) > 0 do
    profile =
      if enabled?() do
        case safe_store_call(:competitive_profile, [player_id]) do
          {:ok, profile} when is_map(profile) ->
            profile
            |> CompetitiveRating.normalize_profile(player_id)
            |> Map.put(:available?, true)

          _error ->
            default_competitive_profile(player_id)
        end
      else
        default_competitive_profile(player_id)
      end

    Map.put(profile, :provisional?, profile.games_played < 10)
  end

  def competitive_profile(player_id), do: default_competitive_profile(player_id)

  def health do
    if enabled?() do
      case safe_store_call(:health, []) do
        :ok -> {:ok, health_payload(true, true)}
        {:ok, _value} -> {:ok, health_payload(true, true)}
        _error -> {:error, health_payload(true, false)}
      end
    else
      {:ok, health_payload(false, true)}
    end
  end

  def writer_status do
    try do
      Writer.status()
    catch
      :exit, _reason -> %{running: false}
    end
  end

  def public_entitlements(entitlements) when is_list(entitlements) do
    entitlements
    |> Enum.filter(&(map_field(&1, :status) == "active"))
    |> Enum.map(fn entitlement ->
      %{
        source: map_field(entitlement, :source),
        external_id: map_field(entitlement, :external_id),
        sku: map_field(entitlement, :sku),
        kind: map_field(entitlement, :kind),
        status: map_field(entitlement, :status)
      }
    end)
  end

  defp record_event(event) do
    writer = Keyword.get(config(), :writer, Writer)

    try do
      writer.record(event)
    rescue
      _error -> :ok
    catch
      _kind, _reason -> :ok
    end

    :ok
  end

  defp safe_store_call(function, arguments) do
    store = store_module()

    try do
      if Code.ensure_loaded?(store) and function_exported?(store, function, length(arguments)) do
        apply(store, function, arguments)
      else
        {:error, :store_unavailable}
      end
    rescue
      _error -> {:error, :store_unavailable}
    catch
      _kind, _reason -> {:error, :store_unavailable}
    end
  end

  defp health_payload(enabled, ready) do
    %{
      enabled: enabled,
      ready: ready,
      mode: if(enabled, do: "postgres", else: "memory"),
      writer: writer_status()
    }
  end

  defp default_competitive_profile(player_id) do
    player_id
    |> CompetitiveRating.default_profile()
    |> Map.put(:available?, false)
  end

  defp store_module, do: Keyword.get(config(), :store, EctoStore)
  defp config, do: Application.get_env(:mana_chess_online, :persistence, [])

  defp map_field(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || ""
  end
end
