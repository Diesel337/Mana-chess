defmodule ManaChessOnline.GameRooms do
  @moduledoc false

  alias ManaChessOnline.{GameBot, GameControl, GameDirectory, GameState, GameTick}

  def practice_game_id(player_id),
    do: "practice_" <> Integer.to_string(:erlang.phash2(player_id))

  def new_game(id, settings), do: GameState.new_game(id, settings)

  def practice_game(id, player_id, settings, now, bot_delay_ms, bot_color \\ :black) do
    GameState.practice_game(id, player_id, settings, now, bot_delay_ms, bot_color)
  end

  def practice_game_for_player(id, player_id, settings, now, bot_color \\ :black) do
    practice_game(id, player_id, settings, now, GameBot.move_delay_ms(settings), bot_color)
  end

  def private_game(id, settings), do: GameState.private_game(id, settings)

  def private_game_id?("private_" <> rest), do: byte_size(rest) >= 6
  def private_game_id?(_game_id), do: false

  def empty_private_game?(%{private?: true, players: %{white: nil, black: nil}}), do: true
  def empty_private_game?(_game), do: false

  def public_lobby_game?(%{practice?: false} = game), do: !Map.get(game, :private?, false)
  def public_lobby_game?(_game), do: false

  def empty_waiting_game?(game), do: GameDirectory.empty_waiting_game?(game)

  def seated_players(game), do: GameDirectory.seated_players(game)

  def find_open_slot(games), do: GameDirectory.find_open_slot(games)

  def reset_ready?(game, player_id) do
    seated_players = seated_players(game)
    MapSet.size(MapSet.put(game.reset_requests, player_id)) >= length(seated_players)
  end

  def refresh_status(%{players: %{white: white, black: black}} = game)
      when is_binary(white) and is_binary(black),
      do: %{game | status: :ready, queue: [], log: ["Ambos jugadores sentados." | game.log]}

  def refresh_status(game), do: game

  def maybe_start_when_everyone_ready(%{status: {:starting, _starts_at}} = game) do
    GameTick.start_when_ready(game, seated_players(game))
  end

  def maybe_start_when_everyone_ready(game), do: game

  def can_clear_room?(%{game_id: game_id, color: color}, player_id, game_id, game)
      when color in [:white, :black] do
    player_id in seated_players(game)
  end

  def can_clear_room?(_assignment, _player_id, _game_id, _game), do: false

  def cleared_game_state(game_id, %{private?: true, settings: settings}),
    do: GameState.private_game(game_id, settings)

  def cleared_game_state(game_id, %{settings: settings}),
    do: GameState.new_game(game_id, settings)

  def reset_room_state(game_id, %{private?: true, settings: settings}),
    do: GameState.private_game(game_id, settings)

  def reset_room_state(game_id, %{settings: settings}), do: GameState.new_game(game_id, settings)

  def reset_practice_room_state(game_id, old_game, now) do
    player_id = old_game.players.white

    game_id
    |> practice_game_for_player(
      player_id,
      old_game.settings,
      now,
      GameControl.bot_color(old_game)
    )
    |> preserve_practice_bot_state(old_game)
    |> preserve_chat(old_game)
    |> prepend_log("Practica reiniciada.")
  end

  def reset_seated_room_state(game_id, old_game) do
    game_id
    |> reset_room_state(old_game)
    |> put_in([:players, :white], old_game.players.white)
    |> put_in([:players, :black], old_game.players.black)
    |> preserve_chat(old_game)
    |> refresh_status()
    |> prepend_log("Partida reiniciada por acuerdo.")
  end

  def preserve_practice_bot_state(next_game, %{bot_enabled?: false}) do
    %{next_game | bot_enabled?: false, bot_ready_at: nil}
  end

  def preserve_practice_bot_state(next_game, _previous_game), do: next_game

  def preserve_chat(next_game, previous_game) do
    Map.put(next_game, :chat, Map.get(previous_game, :chat, []))
  end

  def prepend_log(game, message), do: update_in(game.log, &[message | &1])

  def unique_private_game_id(games) do
    game_id = "private_" <> random_private_token()

    if Map.has_key?(games, game_id), do: unique_private_game_id(games), else: game_id
  end

  defp random_private_token do
    6
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
