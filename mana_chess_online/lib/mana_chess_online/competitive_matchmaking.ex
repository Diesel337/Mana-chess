defmodule ManaChessOnline.CompetitiveMatchmaking do
  @moduledoc false

  alias ManaChessOnline.{CompetitiveRating, GameDirectory}

  def find_open_slot(games, player_ratings, seeker_rating) do
    games
    |> GameDirectory.public_games()
    |> Enum.flat_map(&open_slots/1)
    |> Enum.min_by(&candidate_key(&1, player_ratings, seeker_rating), fn -> nil end)
    |> case do
      nil -> nil
      %{game_id: game_id, color: color} -> {game_id, color}
    end
  end

  defp open_slots({game_id, %{status: :waiting, players: players}}) do
    [
      open_slot(game_id, :white, players.white, players.black),
      open_slot(game_id, :black, players.black, players.white)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp open_slots(_game), do: []

  defp open_slot(game_id, color, nil, opponent_id) do
    %{game_id: game_id, color: color, opponent_id: opponent_id}
  end

  defp open_slot(_game_id, _color, _player_id, _opponent_id), do: nil

  defp candidate_key(candidate, player_ratings, seeker_rating) do
    opponent_id = candidate.opponent_id
    occupied_priority = if is_binary(opponent_id), do: 0, else: 1
    opponent_rating = rating_for(player_ratings, opponent_id)
    distance = if occupied_priority == 0, do: abs(seeker_rating - opponent_rating), else: 0
    color_priority = if candidate.color == :white, do: 0, else: 1

    {occupied_priority, distance, candidate.game_id, color_priority}
  end

  defp rating_for(_player_ratings, nil), do: CompetitiveRating.default_rating()

  defp rating_for(player_ratings, player_id) do
    case Map.get(player_ratings, player_id) do
      rating when is_integer(rating) -> rating
      %{rating: rating} when is_integer(rating) -> rating
      _rating -> CompetitiveRating.default_rating()
    end
  end
end
