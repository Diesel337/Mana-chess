defmodule ManaChessOnline.GameLobbyMatchmaking do
  @moduledoc false

  alias ManaChessOnline.{
    CompetitiveMatchmaking,
    CompetitiveRating,
    GameCapacity,
    GameLobbyRooms,
    GameLobbyServers,
    GameRooms,
    RateLimiter
  }

  @seat_rate_limit {30, 10_000}
  @private_room_rate_limit {3, 60_000}

  def sit(state, player_id, game_id, color, now) do
    case RateLimiter.take_state(state, {:seat, player_id}, @seat_rate_limit, now) do
      {:ok, state} ->
        state =
          state
          |> GameLobbyRooms.remove_player(player_id)
          |> GameLobbyRooms.assign_player(player_id, game_id, color)

        {:ok, state}

      {:error, :rate_limited, state} ->
        {:error, :rate_limited, state}
    end
  end

  def sit_anywhere(state, player_id, now),
    do: sit_anywhere(state, player_id, CompetitiveRating.default_rating(), now)

  def sit_anywhere(state, player_id, rating, now) do
    case RateLimiter.take_state(state, {:seat, player_id}, @seat_rate_limit, now) do
      {:ok, state} ->
        state = put_player_rating(state, player_id, rating)

        state =
          case CompetitiveMatchmaking.find_open_slot(
                 GameLobbyServers.server_backed_games(state.games),
                 Map.get(state, :player_ratings, %{}),
                 rating
               ) do
            {game_id, color} ->
              state
              |> GameLobbyRooms.remove_player(player_id)
              |> GameLobbyRooms.assign_player(player_id, game_id, color)

            nil ->
              state
          end

        {:ok, state}

      {:error, :rate_limited, state} ->
        {:error, :rate_limited, state}
    end
  end

  def create_private(state, player_id, now) do
    if GameCapacity.available_after_leaving?(state, player_id) do
      case RateLimiter.take_state(
             state,
             {:private_room, player_id},
             @private_room_rate_limit,
             now
           ) do
        {:ok, state} ->
          game_id =
            GameRooms.unique_private_game_id(GameLobbyServers.server_backed_games(state.games))

          game =
            game_id
            |> GameRooms.private_game(state.global_settings)
            |> GameLobbyServers.replace_game_state()

          state =
            state
            |> GameLobbyRooms.remove_player(player_id)
            |> put_in([:games, game_id], game)
            |> GameLobbyRooms.assign_player(player_id, game_id, :white)

          {:ok, state, game_id}

        {:error, :rate_limited, state} ->
          {:error, :rate_limited, state}
      end
    else
      {:error, :capacity, GameCapacity.record_rejection(state)}
    end
  end

  defp put_player_rating(state, player_id, rating) do
    rating = CompetitiveRating.normalize_profile(%{rating: rating}).rating

    Map.update(state, :player_ratings, %{player_id => rating}, &Map.put(&1, player_id, rating))
  end
end
