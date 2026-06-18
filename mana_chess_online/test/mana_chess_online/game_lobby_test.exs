defmodule ManaChessOnline.GameLobbyTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.GameLobby

  test "stores sanitized room chat messages" do
    player_id = "chat-player-" <> Integer.to_string(System.unique_integer([:positive]))
    view = GameLobby.start_practice(player_id)

    assert :ok = GameLobby.send_chat(player_id, view.game_id, "  hola\n   mana   ")

    game = GameLobby.snapshot(view.game_id)
    assert [%{player_id: ^player_id, name: name, role: "Practica", sent_at: sent_at, text: "hola mana"} | _rest] = game.chat
    assert String.starts_with?(name, "Jugador ")
    assert is_integer(sent_at)
  end

  test "rejects blank chat messages" do
    player_id = "chat-blank-" <> Integer.to_string(System.unique_integer([:positive]))
    view = GameLobby.start_practice(player_id)

    assert {:error, :empty} = GameLobby.send_chat(player_id, view.game_id, "   ")
    assert GameLobby.snapshot(view.game_id).chat == []
  end

  test "rejects moving a piece while it is on cooldown" do
    player_id = "cooldown-player-" <> Integer.to_string(System.unique_integer([:positive]))
    view = GameLobby.start_practice(player_id)

    assert :ok = GameLobby.enqueue(player_id, {6, 4}, {5, 4})
    assert :ok = GameLobby.enqueue(player_id, {5, 4}, {4, 4})

    game = GameLobby.snapshot(view.game_id)
    assert hd(game.log) == "Movimiento rechazado: pieza en cooldown."
    assert Enum.at(Enum.at(game.board, 5), 4) == "P"
    assert Enum.at(Enum.at(game.board, 4), 4) == "."
  end
end
