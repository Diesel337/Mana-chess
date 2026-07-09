defmodule ManaChessOnline.GameChat do
  @moduledoc false

  def sanitize_message(message) do
    text =
      message
      |> to_string()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, 180)

    if text == "", do: {:error, :empty}, else: {:ok, text}
  end

  def put_entry(game, entry) do
    chat =
      [entry | Map.get(game, :chat, [])]
      |> Enum.take(24)

    Map.put(game, :chat, chat)
  end

  def role(%{practice?: true}, player_id) when is_binary(player_id), do: "Practica"
  def role(%{players: %{white: player_id}}, player_id), do: "Blancas"
  def role(%{players: %{black: player_id}}, player_id), do: "Negras"
  def role(_game, _player_id), do: "Espectador"

  def player_name(player_id) when is_binary(player_id) do
    tag =
      player_id
      |> :erlang.phash2(36 * 36 * 36 * 36)
      |> Integer.to_string(36)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "Jugador " <> tag
  end

  def player_name(_player_id), do: "Jugador"

  def bot_toggle_message(true, color), do: "Bot activado: controla #{label(color)}."
  def bot_toggle_message(false, _color), do: "Bot desactivado."

  def label(:white), do: "Blancas"
  def label(:black), do: "Negras"
  def label(:practice), do: "Practica"
end
