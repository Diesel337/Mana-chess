defmodule ManaChessOnline.GameLobbyActions do
  @moduledoc false

  alias ManaChessOnline.{
    GameChat,
    GameControl,
    GameEngine,
    GameLobbyRooms,
    GameLobbyServers,
    GamePlayers,
    GamePromotion,
    GameRooms,
    GameRules
  }

  def reset(state, player_id, now) do
    with %{game_id: game_id, color: color} when is_binary(game_id) <-
           GamePlayers.assignment(state, player_id),
         game when not is_nil(game) <- game_snapshot(game_id, state) do
      if GameRooms.reset_ready?(game, player_id) do
        GameLobbyRooms.reset_game(state, game_id, game, now)
      else
        game =
          update_game_state(game, fn game ->
            %{
              game
              | reset_requests: MapSet.put(game.reset_requests, player_id),
                log: ["#{GameChat.label(color)} pidio reiniciar la partida." | game.log]
            }
          end)

        put_in(state.games[game_id], game)
      end
    else
      _ -> state
    end
  end

  def start_game(state, player_id, starts_at) do
    with %{game_id: game_id} when is_binary(game_id) <- GamePlayers.assignment(state, player_id),
         %{status: :ready} = game <- game_snapshot(game_id, state) do
      game =
        update_game_state(game, fn game ->
          %{
            game
            | status: {:starting, starts_at},
              queue: [],
              reset_requests: MapSet.new(),
              start_requests: MapSet.new([player_id]),
              log: ["Cuenta regresiva iniciada." | game.log]
          }
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  def ready_to_start(state, player_id) do
    with %{game_id: game_id} when is_binary(game_id) <- GamePlayers.assignment(state, player_id),
         %{status: {:starting, _starts_at}} = game <- game_snapshot(game_id, state),
         true <- player_id in GameRooms.seated_players(game) do
      game =
        update_game_state(game, fn game ->
          game
          |> update_in([:start_requests], &MapSet.put(&1, player_id))
          |> GameRooms.maybe_start_when_everyone_ready()
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  def promote(state, player_id, choice, now \\ System.monotonic_time(:millisecond)) do
    with %{game_id: game_id, color: player_color} <- GamePlayers.assignment(state, player_id),
         game when not is_nil(game) <- game_snapshot(game_id, state),
         %{player_id: ^player_id, color: color, at: square} <- game.promotion_pending,
         true <- GameControl.controls_color?(player_color, color) do
      game =
        update_game_state(game, fn game ->
          board =
            GameRules.promote(game.board, square, GamePromotion.choice(choice, color), color)

          status = GameEngine.terminal_status(board, game.castling_rights) || :playing

          %{
            game
            | board: board,
              status: status,
              finished_at:
                if(GameEngine.terminal_status?(status), do: now, else: game.finished_at),
              promotion_pending: nil,
              log: ["#{GameChat.label(color)} promociono peon." | game.log]
          }
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)
end
