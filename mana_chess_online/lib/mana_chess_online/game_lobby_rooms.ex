defmodule ManaChessOnline.GameLobbyRooms do
  @moduledoc false

  alias ManaChessOnline.{GameCapacity, GameLobbyServers, GamePlayers, GameRooms}

  def assign_player(state, player_id, game_id, color) do
    case game_snapshot(game_id, state) do
      %{players: players} = game when color in [:white, :black] ->
        if is_nil(players[color]) do
          state = GamePlayers.assign(state, player_id, game_id, color)

          game =
            update_game_state(game, fn game ->
              game
              |> put_in([:players, color], player_id)
              |> GameRooms.refresh_status()
            end)

          put_in(state.games[game_id], game)
        else
          state
        end

      _ ->
        state
    end
  end

  def remove_player(state, player_id) do
    case GamePlayers.assignment(state, player_id) do
      %{game_id: game_id, color: color} when is_binary(game_id) ->
        case game_snapshot(game_id, state) do
          %{practice?: true} ->
            GameLobbyServers.stop_game_server(game_id)

            state
            |> GamePlayers.remove(player_id)
            |> update_in([:games], &GameRooms.drop_game(&1, game_id))

          nil ->
            GamePlayers.remove(state, player_id)

          game ->
            state = GamePlayers.remove(state, player_id)

            game = update_game_state(game, &GameRooms.leave_seat_state(&1, color))

            state
            |> put_in([:games, game_id], game)
            |> maybe_drop_empty_ephemeral_game(game_id, game)
        end

      _ ->
        GamePlayers.remove(state, player_id)
    end
  end

  def reset_game(state, game_id, old_game, now) do
    {state, reset_game} =
      if old_game.practice? do
        player_id = old_game.players.white

        {
          GamePlayers.assign(state, player_id, game_id, :practice),
          GameRooms.reset_practice_room_state(game_id, old_game, now)
        }
      else
        state =
          state
          |> GamePlayers.keep_assignment_if_present(old_game.players.white, game_id, :white)
          |> GamePlayers.keep_assignment_if_present(old_game.players.black, game_id, :black)

        {state, GameRooms.reset_seated_room_state(game_id, old_game)}
      end

    put_in(state.games[game_id], replace_game_state(reset_game))
  end

  def clear_room_state(state, game_id, game) do
    player_ids = GameRooms.seated_players(game)

    state
    |> GamePlayers.remove_many(player_ids)
    |> put_in([:games, game_id], replace_game_state(GameRooms.cleared_game_state(game_id, game)))
  end

  def clear_room(state, player_id, game_id) do
    case game_snapshot(game_id, state) do
      %{practice?: false} = game when game.status in [:waiting, :ready] ->
        if GameRooms.can_clear_room?(
             GamePlayers.assignment(state, player_id),
             player_id,
             game_id,
             game
           ) do
          {:ok, clear_room_state(state, game_id, game)}
        else
          {:error, :forbidden, state}
        end

      _ ->
        {:error, :not_clearable, state}
    end
  end

  def force_clear_room(state, game_id) do
    case game_snapshot(game_id, state) do
      %{practice?: false} = game when game.status in [:waiting, :ready] ->
        clear_room_state(state, game_id, game)

      _ ->
        state
    end
  end

  def ensure_private_game(state, game_id) do
    if GameRooms.private_game_id?(game_id) do
      case game_snapshot(game_id, state) do
        nil ->
          if GameCapacity.available?(state) do
            game = replace_game_state(GameRooms.private_game(game_id, state.global_settings))
            put_in(state.games[game_id], game)
          else
            GameCapacity.record_rejection(state)
          end

        game ->
          game = replace_game_state(game)
          put_in(state.games[game_id], game)
      end
    else
      state
    end
  end

  def practice_game(id, player_id, settings, now, bot_color \\ :black) do
    GameRooms.practice_game_for_player(id, player_id, settings, now, bot_color)
  end

  defp maybe_drop_empty_ephemeral_game(state, game_id, game) do
    if GameRooms.drop_empty_private_game?(game) or GameRooms.empty_matchmaking_game?(game) do
      GameLobbyServers.stop_game_server(game_id)
      update_in(state.games, &GameRooms.drop_game(&1, game_id))
    else
      state
    end
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)
  defp replace_game_state(game), do: GameLobbyServers.replace_game_state(game)
end
