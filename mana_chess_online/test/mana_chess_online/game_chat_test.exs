defmodule ManaChessOnline.GameChatTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.GameChat

  test "sanitizes chat messages" do
    assert GameChat.sanitize_message("  hola\n   mana   ") == {:ok, "hola mana"}
    assert GameChat.sanitize_message("   ") == {:error, :empty}

    long_text = String.duplicate("a", 220)
    assert {:ok, trimmed} = GameChat.sanitize_message(long_text)
    assert String.length(trimmed) == 180
  end

  test "builds stable player names" do
    name = GameChat.player_name("player-1")

    assert name == GameChat.player_name("player-1")
    assert String.starts_with?(name, "Jugador ")
    assert String.length(name) >= 12
    assert GameChat.player_name(nil) == "Jugador"
  end

  test "labels chat roles and bot toggles" do
    game = %{practice?: false, players: %{white: "white-id", black: "black-id"}}

    assert GameChat.role(%{practice?: true}, "any") == "Practica"
    assert GameChat.role(game, "white-id") == "Blancas"
    assert GameChat.role(game, "black-id") == "Negras"
    assert GameChat.role(game, "watcher") == "Espectador"
    assert GameChat.bot_toggle_message(true, :black) == "Bot activado: controla Negras."
    assert GameChat.bot_toggle_message(false, :white) == "Bot desactivado."
  end
end
