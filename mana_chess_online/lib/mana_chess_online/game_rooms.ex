defmodule ManaChessOnline.GameRooms do
  @moduledoc false

  alias ManaChessOnline.{GameDirectory, GameState}

  def practice_game_id(player_id),
    do: "practice_" <> Integer.to_string(:erlang.phash2(player_id))

  def new_game(id, settings), do: GameState.new_game(id, settings)

  def practice_game(id, player_id, settings, now, bot_delay_ms, bot_color \\ :black) do
    GameState.practice_game(id, player_id, settings, now, bot_delay_ms, bot_color)
  end

  def private_game(id, settings), do: GameState.private_game(id, settings)

  def private_game_id?("private_" <> rest), do: byte_size(rest) >= 6
  def private_game_id?(_game_id), do: false

  def empty_private_game?(%{private?: true, players: %{white: nil, black: nil}}), do: true
  def empty_private_game?(_game), do: false

  def public_lobby_game?(%{practice?: false} = game), do: !Map.get(game, :private?, false)
  def public_lobby_game?(_game), do: false

  def reset_ready?(game, player_id) do
    seated_players = GameDirectory.seated_players(game)
    MapSet.size(MapSet.put(game.reset_requests, player_id)) >= length(seated_players)
  end

  def can_clear_room?(%{game_id: game_id, color: color}, player_id, game_id, game)
      when color in [:white, :black] do
    player_id in GameDirectory.seated_players(game)
  end

  def can_clear_room?(_assignment, _player_id, _game_id, _game), do: false

  def cleared_game_state(game_id, %{private?: true, settings: settings}),
    do: GameState.private_game(game_id, settings)

  def cleared_game_state(game_id, %{settings: settings}),
    do: GameState.new_game(game_id, settings)

  def reset_room_state(game_id, %{private?: true, settings: settings}),
    do: GameState.private_game(game_id, settings)

  def reset_room_state(game_id, %{settings: settings}), do: GameState.new_game(game_id, settings)

  def preserve_practice_bot_state(next_game, %{bot_enabled?: false}) do
    %{next_game | bot_enabled?: false, bot_ready_at: nil}
  end

  def preserve_practice_bot_state(next_game, _previous_game), do: next_game

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
