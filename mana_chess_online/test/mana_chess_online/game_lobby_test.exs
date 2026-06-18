defmodule ManaChessOnline.GameLobbyTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.GameLobby

  test "stores sanitized room chat messages" do
    player_id = "chat-player-" <> Integer.to_string(System.unique_integer([:positive]))
    view = GameLobby.start_practice(player_id)

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "  hola\n   mana   ")

    game = GameLobby.snapshot(view.game_id)
    assert [%{player_id: ^player_id, role: "Practica", text: "hola mana"} | _rest] = game.chat
  end

  test "rejects blank chat messages" do
    player_id = "chat-blank-" <> Integer.to_string(System.unique_integer([:positive]))
    view = GameLobby.start_practice(player_id)

    assert {:error, :empty} = GameLobby.send_chat(player_id, view.game_id, "   ")
    assert GameLobby.snapshot(view.game_id).chat == []
  end
end
