defmodule ManaChessOnline.GameBroadcast do
  @moduledoc false

  def game_update_needed?(previous_public_game, next_public_game, next_game) do
    previous_public_game != next_public_game or countdown_visible?(next_game) or
      cooldowns_visible?(next_game)
  end

  def lobby_update_needed?(previous_public_lobby, next_public_lobby, next_games) do
    previous_public_lobby != next_public_lobby or
      Enum.any?(next_games, fn {_game_id, game} -> countdown_visible?(game) end)
  end

  def countdown_visible?(%{status: {:starting, _starts_at}}), do: true
  def countdown_visible?(_game), do: false

  def cooldowns_visible?(%{status: :playing, cooldowns: cooldowns}), do: map_size(cooldowns) > 0
  def cooldowns_visible?(_game), do: false
end
