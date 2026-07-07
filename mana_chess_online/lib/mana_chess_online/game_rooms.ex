defmodule ManaChessOnline.GameRooms do
  @moduledoc false

  def practice_game_id(player_id),
    do: "practice_" <> Integer.to_string(:erlang.phash2(player_id))

  def private_game_id?("private_" <> rest), do: byte_size(rest) >= 6
  def private_game_id?(_game_id), do: false

  def empty_private_game?(%{private?: true, players: %{white: nil, black: nil}}), do: true
  def empty_private_game?(_game), do: false

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
