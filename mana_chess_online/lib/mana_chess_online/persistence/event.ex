defmodule ManaChessOnline.Persistence.Event do
  @moduledoc false

  @steam_id_pattern ~r/\A[0-9]{16,20}\z/
  @max_app_id 4_294_967_295

  def steam_identity(identity, authenticated_at) when is_map(identity) do
    with steam_id when is_binary(steam_id) <- steam_id(field(identity, :steam_id)),
         owner_steam_id when is_binary(owner_steam_id) <-
           steam_id(field(identity, :owner_steam_id)),
         app_id when is_integer(app_id) and app_id > 0 and app_id <= @max_app_id <-
           integer(field(identity, :app_id)),
         %DateTime{} = authenticated_at <- utc_datetime(authenticated_at) do
      {:ok,
       {:steam_identity,
        %{
          steam_id: steam_id,
          owner_steam_id: owner_steam_id,
          app_id: app_id,
          permanent: boolean(field(identity, :permanent)),
          site_license: boolean(field(identity, :site_license)),
          vac_banned: boolean(field(identity, :vac_banned)),
          time_expires: clean_string(field(identity, :time_expires), 80),
          first_authenticated_at: authenticated_at,
          last_authenticated_at: authenticated_at
        }}}
    else
      _error -> :error
    end
  end

  def steam_identity(_identity, _authenticated_at), do: :error

  def entitlement(attrs, observed_at) when is_map(attrs) do
    with steam_id when is_binary(steam_id) <- steam_id(field(attrs, :steam_id)),
         source when is_binary(source) <- required_string(field(attrs, :source), 40),
         external_id when is_binary(external_id) <-
           required_string(field(attrs, :external_id), 120),
         sku when is_binary(sku) <- required_string(field(attrs, :sku), 120),
         kind when is_binary(kind) <- required_string(field(attrs, :kind), 40),
         status when status in ["active", "revoked"] <-
           clean_string(field(attrs, :status) || "active", 20),
         %DateTime{} = observed_at <- utc_datetime(observed_at) do
      {:ok,
       {:entitlement,
        %{
          steam_id: steam_id,
          source: source,
          external_id: external_id,
          sku: sku,
          kind: kind,
          status: status,
          metadata: json_safe(field(attrs, :metadata) || %{}),
          granted_at: if(status == "active", do: observed_at),
          revoked_at: if(status == "revoked", do: observed_at)
        }}}
    else
      _error -> :error
    end
  end

  def entitlement(_attrs, _observed_at), do: :error

  def system_setting(key, value, version)
      when is_binary(key) and byte_size(key) > 0 and byte_size(key) <= 120 and
             is_integer(version) and version > 0 do
    {:ok, {:system_setting, %{key: key, value: json_safe(value), version: version}}}
  end

  def system_setting(_key, _value, _version), do: :error

  def match_summary(%{status: status} = game, finished_at) do
    with {:ok, result, winner_color} <- terminal_result(status),
         %DateTime{} = finished_at <- utc_datetime(finished_at) do
      {:ok,
       {:match_summary,
        %{
          event_id: Ecto.UUID.generate(),
          game_id: clean_string(Map.get(game, :id), 160),
          mode: game_mode(game),
          white_player_id: player_id(get_in(game, [:players, :white])),
          black_player_id: player_id(get_in(game, [:players, :black])),
          result: result,
          winner_color: winner_color,
          finished_at: finished_at,
          settings: json_safe(Map.get(game, :settings, %{})),
          metadata: %{
            "bot_enabled" => Map.get(game, :bot_enabled?, false) == true,
            "bot_color" => color(Map.get(game, :bot_color)),
            "game_finished_at_ms" => Map.get(game, :finished_at),
            "log_entries" => length(Map.get(game, :log, []))
          }
        }}}
    else
      _error -> :ignore
    end
  end

  def match_summary(_game, _finished_at), do: :ignore

  def json_safe(value) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {key, item} -> {json_key(key), json_safe(item)} end)
  end

  def json_safe(%MapSet{} = value), do: value |> MapSet.to_list() |> Enum.map(&json_safe/1)
  def json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  def json_safe(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.map(&json_safe/1)

  def json_safe(value) when value in [nil, true, false], do: value
  def json_safe(value) when is_atom(value), do: Atom.to_string(value)
  def json_safe(value) when is_binary(value) or is_number(value), do: value
  def json_safe(_value), do: nil

  defp terminal_result({:checkmate, winner, _loser}), do: winner_result(winner)
  defp terminal_result({:winner, winner}), do: winner_result(winner)
  defp terminal_result(:draw), do: {:ok, "draw", nil}
  defp terminal_result(_status), do: :error

  defp winner_result(:white), do: {:ok, "white_win", "white"}
  defp winner_result(:black), do: {:ok, "black_win", "black"}
  defp winner_result(_winner), do: :error

  defp game_mode(%{practice?: true}), do: "practice"
  defp game_mode(%{private?: true}), do: "private"
  defp game_mode(_game), do: "public"

  defp player_id(value) when is_binary(value), do: clean_string(value, 160)
  defp player_id(_value), do: nil

  defp color(value) when value in [:white, :black], do: Atom.to_string(value)
  defp color(_value), do: nil

  defp steam_id(value) do
    value = clean_string(value, 20)
    if Regex.match?(@steam_id_pattern, value), do: value
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) do
    case Integer.parse(String.trim(to_string(value || ""))) do
      {integer, ""} -> integer
      _error -> nil
    end
  end

  defp required_string(value, max_bytes) do
    value = clean_string(value, max_bytes)
    if value == "", do: nil, else: value
  end

  defp clean_string(value, max_bytes) do
    value
    |> to_string()
    |> String.replace(~r/[\x00-\x1f\x7f]/u, "")
    |> String.trim()
    |> String.slice(0, max_bytes)
  end

  defp boolean(value), do: value in [true, 1, "1", "true", "TRUE"]

  defp utc_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp utc_datetime(_datetime), do: nil

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: to_string(key)

  defp field(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
