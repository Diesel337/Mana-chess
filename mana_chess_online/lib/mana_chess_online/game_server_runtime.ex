defmodule ManaChessOnline.GameServerRuntime do
  @moduledoc false

  alias ManaChessOnline.{GameBroadcast, GameLobbyView}

  def after_tick(previous_game, next_game, now_ms) do
    if GameBroadcast.game_update_needed?(
         previous_game,
         next_game,
         now_ms,
         &GameLobbyView.public_game/2
       ),
       do: GameBroadcast.game_update_for(next_game, now_ms)
  end
end
