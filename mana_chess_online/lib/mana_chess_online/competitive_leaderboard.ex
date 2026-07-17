defmodule ManaChessOnline.CompetitiveLeaderboard do
  @moduledoc """
  Builds the public competitive leaderboard without exposing player identifiers.
  """

  alias ManaChessOnline.CompetitiveRating

  @maximum_entries 10

  def default do
    %{
      available?: false,
      entries: [],
      current: nil,
      total_players: 0
    }
  end

  def normalize(payload, current_player_id) when is_map(payload) do
    entries =
      payload
      |> field(:entries)
      |> normalize_entries(current_player_id)

    current =
      payload
      |> field(:current)
      |> normalize_entry(current_player_id)

    %{
      available?: true,
      entries: entries,
      current: current,
      total_players: normalize_total(field(payload, :total_players), length(entries))
    }
  end

  def normalize(_payload, _current_player_id), do: default()

  def alias_for(player_id, secret \\ alias_secret())

  def alias_for(player_id, secret) when is_binary(player_id) do
    suffix =
      :crypto.mac(:hmac, :sha256, normalize_secret(secret), player_id)
      |> binary_part(0, 4)
      |> Base.encode16(case: :upper)

    "Jugador " <> suffix
  end

  defp normalize_entries(entries, current_player_id) when is_list(entries) do
    entries
    |> Enum.map(&normalize_entry(&1, current_player_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.rank)
    |> Enum.uniq_by(& &1.rank)
    |> Enum.take(@maximum_entries)
  end

  defp normalize_entries(_entries, _current_player_id), do: []

  defp normalize_entry(entry, current_player_id) when is_map(entry) do
    player_id = field(entry, :player_id)
    rank = positive_integer(field(entry, :rank))

    if valid_player_id?(player_id) and is_integer(rank) do
      profile = CompetitiveRating.normalize_profile(entry, player_id)
      current? = player_id == current_player_id

      %{
        rank: rank,
        name: if(current?, do: "Tu", else: alias_for(player_id)),
        rating: profile.rating,
        games_played: profile.games_played,
        wins: profile.wins,
        losses: profile.losses,
        draws: profile.draws,
        provisional?: profile.games_played < 10,
        current?: current?
      }
    end
  end

  defp normalize_entry(_entry, _current_player_id), do: nil

  defp normalize_total(value, minimum) do
    case non_negative_integer(value) do
      total when is_integer(total) -> max(total, minimum)
      nil -> minimum
    end
  end

  defp positive_integer(value) do
    case non_negative_integer(value) do
      integer when is_integer(integer) and integer > 0 -> integer
      _value -> nil
    end
  end

  defp non_negative_integer(value) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _error -> nil
    end
  end

  defp non_negative_integer(_value), do: nil

  defp valid_player_id?(player_id),
    do: is_binary(player_id) and byte_size(player_id) > 0 and byte_size(player_id) <= 160

  defp alias_secret do
    Application.get_env(:mana_chess_online, :leaderboard_alias_secret)
  end

  defp normalize_secret(secret) do
    case secret |> to_string() |> String.trim() do
      "" -> "mana-chess-local-leaderboard-v1"
      normalized -> normalized
    end
  end

  defp field(nil, _key), do: nil

  defp field(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
