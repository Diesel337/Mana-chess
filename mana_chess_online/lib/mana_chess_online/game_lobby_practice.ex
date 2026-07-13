defmodule ManaChessOnline.GameLobbyPractice do
  @moduledoc false

  alias ManaChessOnline.{
    GameBot,
    GameChat,
    GameControl,
    GameLobbyRooms,
    GameLobbyServers,
    GamePlayers,
    GameRooms
  }

  def start_practice(state, player_id, now) do
    game_id = GameRooms.practice_game_id(player_id)

    state
    |> GameLobbyRooms.remove_player(player_id)
    |> put_in(
      [:games, game_id],
      replace_game_state(
        GameLobbyRooms.practice_game(game_id, player_id, state.global_settings, now)
      )
    )
    |> put_in([:players, player_id], %{game_id: game_id, color: :practice})
  end

  def toggle_bot(state, player_id, now) do
    with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
         %{practice?: true} = game <- game_snapshot(game_id, state) do
      game =
        update_game_state(game, fn game ->
          enabled? = not game.bot_enabled?

          %{
            game
            | bot_enabled?: enabled?,
              bot_ready_at:
                if(enabled?, do: now + GameBot.move_delay_ms(game.settings), else: nil),
              log: [GameChat.bot_toggle_message(enabled?, GameControl.bot_color(game)) | game.log]
          }
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  def toggle_side(state, player_id, now) do
    with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
         %{practice?: true} = game <- game_snapshot(game_id, state) do
      game =
        update_game_state(game, fn game ->
          next_bot_color = game |> GameControl.bot_color() |> GameControl.opposite_color()
          chat = Map.get(game, :chat, [])

          GameLobbyRooms.practice_game(game_id, player_id, game.settings, now, next_bot_color)
          |> GameRooms.preserve_practice_bot_state(game)
          |> Map.put(:chat, chat)
          |> update_in(
            [:log],
            &[
              "Ahora juegas #{GameChat.label(GameControl.opposite_color(next_bot_color))}; BOT controla #{GameChat.label(next_bot_color)}."
              | &1
            ]
          )
        end)

      put_in(state.games[game_id], game)
    else
      _ -> state
    end
  end

  defp game_snapshot(game_id, state), do: GameLobbyServers.game_snapshot(game_id, state.games)
  defp update_game_state(game, fun), do: GameLobbyServers.update_state(game, fun)
  defp replace_game_state(game), do: GameLobbyServers.replace_game_state(game)
end
