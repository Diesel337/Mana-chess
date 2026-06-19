defmodule ManaChessOnlineWeb.GameSoundComponents do
  @moduledoc false
  use ManaChessOnlineWeb, :html

  alias ManaChessOnlineWeb.GameText

  attr :default_volume, :integer, default: 70

  def sound_control(assigns) do
    ~H"""
    <div class="mc-sound-control" data-sound-control>
      <button
        type="button"
        class="mc-sound-toggle"
        data-sound-toggle
        aria-pressed="false"
        aria-label="Encender sonido"
      >
        <span data-sound-toggle-copy>Sonido</span>
        <strong data-sound-toggle-label>OFF</strong>
      </button>
      <label class="mc-sound-volume">
        <span>Vol</span>
        <strong data-sound-volume-label>{@default_volume}%</strong>
        <input
          type="range"
          min="0"
          max="100"
          step="5"
          value={@default_volume}
          data-sound-volume
          aria-label="Volumen de sonido"
        />
      </label>
    </div>
    """
  end

  def sound_state_attrs(nil, _check_message, _visible_alert, _reset_message) do
    %{
      "data-sound-game-id" => "",
      "data-sound-status" => "",
      "data-sound-log-count" => 0,
      "data-sound-log-kind" => "",
      "data-sound-chat-count" => 0,
      "data-sound-alert" => "",
      "data-sound-alert-kind" => ""
    }
  end

  def sound_state_attrs(game, check_message, visible_alert, reset_message) do
    %{
      "data-sound-game-id" => game.id || "",
      "data-sound-status" => sound_status_key(game),
      "data-sound-log-count" => sound_log_count(game),
      "data-sound-log-kind" => sound_log_kind(game),
      "data-sound-chat-count" => sound_chat_count(game),
      "data-sound-alert" => sound_alert_key(check_message, visible_alert, reset_message),
      "data-sound-alert-kind" => sound_alert_kind(check_message, reset_message)
    }
  end

  defp sound_status_key(%{status: status}), do: inspect(status)
  defp sound_status_key(_game), do: ""

  defp sound_log_count(%{log: log}) when is_list(log), do: length(log)
  defp sound_log_count(_game), do: 0

  defp sound_log_kind(%{log: [latest | _rest]}), do: GameText.log_entry_kind(latest)
  defp sound_log_kind(_game), do: ""

  defp sound_chat_count(%{chat: chat}) when is_list(chat), do: length(chat)
  defp sound_chat_count(_game), do: 0

  defp sound_alert_key(check_message, visible_alert, reset_message) do
    [check_message, visible_alert, reset_message]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" | ")
  end

  defp sound_alert_kind(check_message, reset_message) do
    cond do
      not blank?(check_message) -> "check"
      not blank?(reset_message) -> "reset"
      true -> "alert"
    end
  end

  defp blank?(value), do: is_nil(value) or value == ""
end
