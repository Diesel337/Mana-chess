defmodule ManaChessOnline.GamePlayers do
  @moduledoc false

  def assignment(state, player_id), do: state.players[player_id]

  def assignment_or_empty(state, player_id) do
    assignment(state, player_id) || %{game_id: nil, color: nil}
  end

  def assign(state, player_id, game_id, color) do
    put_in(state.players[player_id], %{game_id: game_id, color: color})
  end

  def remove(state, player_id) do
    update_in(state.players, &Map.delete(&1, player_id))
  end

  def remove_many(state, player_ids) do
    update_in(state.players, &Map.drop(&1, player_ids))
  end

  def keep_assignment_if_present(state, nil, _game_id, _color), do: state

  def keep_assignment_if_present(state, player_id, game_id, color) do
    assign(state, player_id, game_id, color)
  end
end
