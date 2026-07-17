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
  @matchmaking_countdown_ms 5_000

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

  def sit_anywhere(state, player_id, rating, now),
    do: sit_anywhere(state, player_id, rating, now, @matchmaking_countdown_ms)

  def sit_anywhere(state, player_id, rating, now, countdown_ms) do
    case RateLimiter.take_state(state, {:seat, player_id}, @seat_rate_limit, now) do
      {:ok, state} ->
        rating = normalize_rating(rating)
        live_games = GameLobbyServers.server_backed_games(state.games)

        case CompetitiveMatchmaking.find_open_slot(
               live_games,
               Map.get(state, :player_ratings, %{}),
               rating,
               player_id
             ) do
          {game_id, color} ->
            state =
              state
              |> seat_player(player_id, game_id, color, rating)
              |> maybe_start_countdown(game_id, now + countdown_ms)

            {:ok, state}

          nil ->
            keep_or_create_matchmaking_game(state, player_id, rating)
        end

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

  def create_matchmaking(state, player_id, rating) do
    rating = normalize_rating(rating)

    if GameCapacity.available_after_leaving?(state, player_id) do
      state = GameLobbyRooms.remove_player(state, player_id)
      games = GameLobbyServers.server_backed_games(state.games)
      game_id = GameRooms.unique_matchmaking_game_id(games)

      game =
        game_id
        |> GameRooms.matchmaking_game(state.global_settings)
        |> GameLobbyServers.replace_game_state()

      state =
        state
        |> put_in([:games, game_id], game)
        |> GameLobbyRooms.assign_player(player_id, game_id, :white)
        |> put_player_rating(player_id, rating)

      {:ok, state, game_id}
    else
      {:error, :capacity, GameCapacity.record_rejection(state)}
    end
  end

  defp put_player_rating(state, player_id, rating) do
    Map.update(state, :player_ratings, %{player_id => rating}, &Map.put(&1, player_id, rating))
  end

  defp normalize_rating(rating) do
    CompetitiveRating.normalize_profile(%{rating: rating}).rating
  end

  defp seat_player(state, player_id, game_id, color, rating) do
    state =
      state
      |> GameLobbyRooms.remove_player(player_id)
      |> GameLobbyRooms.assign_player(player_id, game_id, color)

    case get_in(state, [:players, player_id]) do
      %{game_id: ^game_id, color: ^color} -> put_player_rating(state, player_id, rating)
      _assignment -> state
    end
  end

  defp maybe_start_countdown(state, game_id, starts_at) do
    case GameLobbyServers.game_snapshot(game_id, state.games) do
      %{status: :ready} = game ->
        game = GameLobbyServers.update_state(game, &GameRooms.start_countdown(&1, starts_at))
        put_in(state.games[game_id], game)

      _game ->
        state
    end
  end

  defp keep_or_create_matchmaking_game(state, player_id, rating) do
    if waiting_in_matchmaking_game?(state, player_id) do
      {:ok, put_player_rating(state, player_id, rating)}
    else
      case create_matchmaking(state, player_id, rating) do
        {:ok, state, _game_id} -> {:ok, state}
        {:error, :capacity, state} -> {:error, :capacity, state}
      end
    end
  end

  defp waiting_in_matchmaking_game?(state, player_id) do
    with %{game_id: game_id} <- get_in(state, [:players, player_id]),
         %{matchmaking?: true, status: :waiting} = game <-
           GameLobbyServers.game_snapshot(game_id, state.games) do
      GameRooms.seated_players(game) == [player_id]
    else
      _assignment -> false
    end
  end
end
