defmodule ManaChessOnlineWeb.GameText do
  @moduledoc false

  def friendly_alert("casilla invalida."), do: "Suelta la pieza dentro del tablero."
  def friendly_alert("la partida no esta jugando."), do: "La partida todavia no esta jugando."
  def friendly_alert("hay una promocion pendiente."), do: "Primero termina la promocion."
  def friendly_alert("pieza sin color."), do: "Esa pieza no se puede mover ahora."
  def friendly_alert("BOT controla Negras."), do: "El BOT controla Negras."
  def friendly_alert("Blancas deben abrir."), do: "Blancas abren: mueve una pieza blanca primero."
  def friendly_alert("la pieza ya no esta ahi."), do: "La pieza ya no esta ahi."
  def friendly_alert("pieza en cooldown."), do: "Cooldown activo: esa pieza aun no puede moverse."
  def friendly_alert("ya no es valido."), do: "Ese movimiento ya no es valido."

  def friendly_alert(message) do
    cond do
      String.starts_with?(message, "no hay pieza en origen") -> "No hay pieza en esa casilla."
      String.starts_with?(message, "no controlas") -> "Esa pieza no es tuya; elige una de tu lado."
      String.contains?(message, "no es legal") -> "Ese destino no es legal para esa pieza."
      true -> sentence_case(message)
    end
  end

  def sentence_case(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  def sentence_case(message), do: message

  def log_entry_class(entry), do: "mc-log-" <> log_entry_kind(entry)

  def log_entry_tag(entry) do
    case log_entry_kind(entry) do
      "alert" -> "Alerta"
      "capture" -> "Captura"
      "move" -> "Mov"
      "bot" -> "BOT"
      "reset" -> "Reset"
      _kind -> "Info"
    end
  end

  def log_entry_text(entry) do
    cond do
      String.starts_with?(entry, "Movimiento rechazado: ") ->
        entry |> String.replace_prefix("Movimiento rechazado: ", "") |> friendly_alert()

      String.starts_with?(entry, "Movimiento descartado: ") ->
        entry |> String.replace_prefix("Movimiento descartado: ", "") |> friendly_alert()

      String.starts_with?(entry, "BOT ") ->
        entry |> String.replace_prefix("BOT ", "") |> sentence_case()

      String.starts_with?(entry, "Bot ") ->
        entry |> String.replace_prefix("Bot ", "") |> sentence_case()

      true ->
        entry
    end
  end

  def log_entry_kind(entry) do
    cond do
      String.starts_with?(entry, "Movimiento rechazado: ") -> "alert"
      String.starts_with?(entry, "Movimiento descartado: ") -> "alert"
      String.starts_with?(entry, "Sin elixir") -> "alert"
      String.contains?(entry, "capturo") -> "capture"
      String.contains?(entry, "movio") -> "move"
      String.contains?(entry, "Bot") or String.contains?(entry, "BOT") -> "bot"
      String.contains?(entry, "reinici") -> "reset"
      true -> "info"
    end
  end
end
