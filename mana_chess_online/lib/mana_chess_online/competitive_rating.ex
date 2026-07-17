defmodule ManaChessOnline.CompetitiveRating do
  @moduledoc false

  @default_rating 1_200
  @minimum_rating 100
  @maximum_rating 4_000
  @provisional_games 10
  @provisional_k 40
  @established_k 24

  def default_rating, do: @default_rating

  def default_profile(player_id) do
    %{
      player_id: player_id,
      rating: @default_rating,
      games_played: 0,
      wins: 0,
      losses: 0,
      draws: 0,
      provisional?: true
    }
  end

  def normalize_profile(profile, player_id \\ nil) when is_map(profile) do
    wins = non_negative(field(profile, :wins))
    losses = non_negative(field(profile, :losses))
    draws = non_negative(field(profile, :draws))
    games_played = max(non_negative(field(profile, :games_played)), wins + losses + draws)

    %{
      player_id: field(profile, :player_id) || player_id,
      rating: clamp(integer(field(profile, :rating), @default_rating)),
      games_played: games_played,
      wins: wins,
      losses: losses,
      draws: draws,
      provisional?: games_played < @provisional_games
    }
  end

  def rate_pair(white_profile, black_profile, result)
      when result in ["white_win", "black_win", "draw"] do
    white = normalize_profile(white_profile)
    black = normalize_profile(black_profile)
    white_score = white_score(result)
    expected = expected_score(white.rating, black.rating)
    k_factor = k_factor(white, black)
    raw_delta = round(k_factor * (white_score - expected))
    delta = decisive_delta(raw_delta, result)
    white_rating = clamp(white.rating + delta)
    black_rating = clamp(black.rating - delta)

    %{
      white: update_record(white, white_rating, result, :white),
      black: update_record(black, black_rating, result, :black),
      white_before: white.rating,
      black_before: black.rating,
      white_change: white_rating - white.rating,
      black_change: black_rating - black.rating
    }
  end

  def eligible_match?(%{
        mode: "public",
        white_player_id: white_player_id,
        black_player_id: black_player_id,
        result: result
      }) do
    valid_player_id?(white_player_id) and valid_player_id?(black_player_id) and
      white_player_id != black_player_id and result in ["white_win", "black_win", "draw"]
  end

  def eligible_match?(_summary), do: false

  defp update_record(profile, rating, result, color) do
    profile
    |> Map.put(:rating, rating)
    |> Map.update!(:games_played, &(&1 + 1))
    |> increment_outcome(result, color)
    |> Map.put(:provisional?, profile.games_played + 1 < @provisional_games)
  end

  defp increment_outcome(profile, "draw", _color), do: Map.update!(profile, :draws, &(&1 + 1))

  defp increment_outcome(profile, "white_win", :white),
    do: Map.update!(profile, :wins, &(&1 + 1))

  defp increment_outcome(profile, "black_win", :black),
    do: Map.update!(profile, :wins, &(&1 + 1))

  defp increment_outcome(profile, _result, _color),
    do: Map.update!(profile, :losses, &(&1 + 1))

  defp expected_score(rating, opponent_rating) do
    1.0 / (1.0 + :math.pow(10.0, (opponent_rating - rating) / 400.0))
  end

  defp k_factor(white, black) do
    if min(white.games_played, black.games_played) < @provisional_games,
      do: @provisional_k,
      else: @established_k
  end

  defp decisive_delta(0, "white_win"), do: 1
  defp decisive_delta(0, "black_win"), do: -1
  defp decisive_delta(delta, _result), do: delta

  defp white_score("white_win"), do: 1.0
  defp white_score("black_win"), do: 0.0
  defp white_score("draw"), do: 0.5

  defp valid_player_id?(player_id),
    do: is_binary(player_id) and byte_size(player_id) > 0 and byte_size(player_id) <= 160

  defp clamp(rating), do: rating |> max(@minimum_rating) |> min(@maximum_rating)

  defp non_negative(value), do: max(integer(value, 0), 0)

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} -> integer
      _error -> default
    end
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
