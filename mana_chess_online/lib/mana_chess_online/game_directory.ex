defmodule ManaChessOnline.GameDirectory do
  @moduledoc false

  def public_games(games) do
    games
    |> Enum.reject(fn {_game_id, game} -> not public_game?(game) end)
    |> Enum.sort_by(fn {game_id, _game} -> game_id end)
  end

  def public_game?(%{practice?: true}), do: false
  def public_game?(game), do: not Map.get(game, :private?, false)

  def find_open_slot(games) do
    games
    |> public_games()
    |> Enum.find_value(fn {game_id, game} ->
      cond do
        is_nil(game.players.white) -> {game_id, :white}
        is_nil(game.players.black) -> {game_id, :black}
        true -> nil
      end
    end)
  end

  def empty_waiting_game?(%{practice?: false, status: :waiting, players: players}) do
    is_nil(players.white) and is_nil(players.black)
  end

  def empty_waiting_game?(_game), do: false

  def seated_players(game) do
    game.players
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end
end
