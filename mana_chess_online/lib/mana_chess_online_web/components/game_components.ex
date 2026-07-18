defmodule ManaChessOnlineWeb.GameComponents do
  @moduledoc false
  use ManaChessOnlineWeb, :html

  alias ManaChessOnlineWeb.GameText

  @files ~w(a b c d e f g h)

  attr :symbols, :map, required: true
  attr :class, :string, required: true
  attr :aria_label, :string, required: true

  def cosmetic_shop(assigns) do
    ~H"""
    <section class={@class} aria-label={@aria_label}>
      <div class="mc-skins-head">
        <div>
          <h2>Tienda</h2>
          <span>Cosmeticos visuales</span>
        </div>
        <small data-cosmetic-local-count>Local primero</small>
      </div>

      <div class="mc-cosmetic-groups">
        <div class="mc-cosmetic-group mc-board-group">
          <span class="mc-cosmetic-group-label">Tableros</span>
          <div class="mc-skin-options">
            <button
              type="button"
              class="mc-skin-option"
              data-board-skin-choice="classic"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-classic" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Clasico B/N</strong>
              <small data-cosmetic-status data-cosmetic-state="included">Incluido</small>
            </button>
            <button
              type="button"
              class="mc-skin-option"
              data-board-skin-choice="gilded"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-gilded" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Dorado</strong>
              <small data-cosmetic-status data-cosmetic-state="included">Incluido</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-board-skin-choice="arcane"
              data-cosmetic-premium="board:arcane"
              data-sound-action="skin"
              title="Probar y desbloquear localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-arcane" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Arcano oscuro</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-board-skin-choice="crystal"
              data-cosmetic-premium="board:crystal"
              data-sound-action="skin"
              title="Probar y desbloquear Cristal localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-crystal" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Prisma de cristal</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-board-skin-choice="elemental"
              data-cosmetic-premium="board:elemental"
              data-sound-action="skin"
              title="Probar y desbloquear Elemental localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-elemental" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Forja elemental</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-board-skin-choice="custom"
              data-cosmetic-premium="board:custom"
              data-sound-action="skin"
              title="Probar y desbloquear paleta localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-skin-preview mc-skin-preview-custom" aria-hidden="true">
                <i></i><i></i><i></i><i></i>
              </span>
              <strong>Paleta</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
          </div>
        </div>

        <div class="mc-cosmetic-group mc-piece-group">
          <span class="mc-cosmetic-group-label">Piezas</span>
          <div class="mc-skin-options">
            <button
              type="button"
              class="mc-skin-option"
              data-piece-skin-choice="classic"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-classic" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black">{@symbols["q"]}</b>
              </span>
              <strong>Clasicas</strong>
              <small data-cosmetic-status data-cosmetic-state="included">Incluido</small>
            </button>
            <button
              type="button"
              class="mc-skin-option"
              data-piece-skin-choice="runes"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-runes" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black">{@symbols["q"]}</b>
              </span>
              <strong>Runas de mana</strong>
              <small data-cosmetic-status data-cosmetic-state="included">Incluido</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-piece-skin-choice="arcane"
              data-cosmetic-premium="piece:arcane"
              data-sound-action="skin"
              title="Probar y desbloquear piezas Arcanas localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-arcane" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white mc-piece-king">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black mc-piece-queen">{@symbols["q"]}</b>
              </span>
              <strong>Orden arcana</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-piece-skin-choice="crystal"
              data-cosmetic-premium="piece:crystal"
              data-sound-action="skin"
              title="Probar y desbloquear localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-crystal" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white mc-piece-king">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black mc-piece-queen">{@symbols["q"]}</b>
              </span>
              <strong>Cristal boreal</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-piece-skin-choice="elemental"
              data-cosmetic-premium="piece:elemental"
              data-sound-action="skin"
              title="Probar y desbloquear piezas Elementales localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-elemental" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white mc-piece-king">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black mc-piece-queen">{@symbols["q"]}</b>
              </span>
              <strong>Guardianes elementales</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-skin-locked"
              data-piece-skin-choice="custom"
              data-cosmetic-premium="piece:custom"
              data-sound-action="skin"
              title="Probar y desbloquear paleta localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <span class="mc-piece-skin-preview mc-piece-skin-preview-custom" aria-hidden="true">
                <b class="mc-piece-sample mc-piece-sample-white">{@symbols["K"]}</b>
                <b class="mc-piece-sample mc-piece-sample-black">{@symbols["q"]}</b>
              </span>
              <strong>Paleta</strong>
              <small data-cosmetic-status data-cosmetic-state="premium">Probar local</small>
            </button>
          </div>
        </div>

        <div class="mc-cosmetic-group mc-pack-group">
          <span class="mc-cosmetic-group-label">Conjuntos</span>
          <div class="mc-pack-options" aria-label="Conjuntos visuales">
            <button
              type="button"
              class="mc-skin-option mc-pack-option"
              data-cosmetic-pack="classic"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <.pack_preview symbols={@symbols} />
              <strong>Base</strong>
              <small data-cosmetic-status data-cosmetic-pack-status data-cosmetic-state="included">
                Incluido
              </small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-pack-option"
              data-cosmetic-pack="mana"
              data-sound-action="skin"
              aria-pressed="false"
            >
              <.pack_preview symbols={@symbols} class="mc-pack-preview-mana" />
              <strong>Mana</strong>
              <small data-cosmetic-status data-cosmetic-pack-status data-cosmetic-state="included">
                Incluido
              </small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-pack-option mc-skin-locked"
              data-cosmetic-pack="arcane"
              data-cosmetic-premium="pack:arcane"
              data-sound-action="skin"
              title="Probar y desbloquear conjunto localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <.pack_preview symbols={@symbols} class="mc-pack-preview-arcane" />
              <strong>Arcano</strong>
              <small data-cosmetic-status data-cosmetic-pack-status data-cosmetic-state="premium">
                Probar local
              </small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-pack-option mc-skin-locked"
              data-cosmetic-pack="crystal"
              data-cosmetic-premium="pack:crystal"
              data-sound-action="skin"
              title="Probar y desbloquear conjunto localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <.pack_preview symbols={@symbols} class="mc-pack-preview-crystal" />
              <strong>Cristal</strong>
              <small data-cosmetic-status data-cosmetic-pack-status data-cosmetic-state="premium">
                Probar local
              </small>
            </button>
            <button
              type="button"
              class="mc-skin-option mc-pack-option mc-skin-locked"
              data-cosmetic-pack="elemental"
              data-cosmetic-premium="pack:elemental"
              data-sound-action="skin"
              title="Probar y desbloquear conjunto localmente"
              aria-disabled="false"
              aria-pressed="false"
            >
              <.pack_preview symbols={@symbols} class="mc-pack-preview-elemental" />
              <strong>Elemental</strong>
              <small data-cosmetic-status data-cosmetic-pack-status data-cosmetic-state="premium">
                Probar local
              </small>
            </button>
          </div>
        </div>

        <div class="mc-cosmetic-group mc-preset-group">
          <span class="mc-cosmetic-group-label">Paletas</span>
          <div class="mc-palette-presets mc-conjunto-options" aria-label="Paletas de color">
            <button type="button" data-palette-reset data-sound-action="skin" aria-pressed="false">
              Base
            </button>
            <button
              type="button"
              data-palette-preset="midnight"
              data-sound-action="skin"
              aria-pressed="false"
            >
              Noche
            </button>
            <button
              type="button"
              data-palette-preset="emerald"
              data-sound-action="skin"
              aria-pressed="false"
            >
              Jade
            </button>
            <button
              type="button"
              data-palette-preset="frost"
              data-sound-action="skin"
              aria-pressed="false"
            >
              Hielo
            </button>
            <button
              type="button"
              data-palette-preset="solar"
              data-sound-action="skin"
              aria-pressed="false"
            >
              Solar
            </button>
            <button
              type="button"
              data-palette-preset="ruby"
              data-sound-action="skin"
              aria-pressed="false"
            >
              Rubi
            </button>
          </div>
        </div>

        <div class="mc-cosmetic-group mc-palette-group">
          <span class="mc-cosmetic-group-label">Paleta</span>
          <div class="mc-palette-editor" data-palette-editor>
            <button
              type="button"
              class="mc-palette-unlock mc-skin-locked"
              data-palette-unlock
              data-sound-action="skin"
              aria-disabled="false"
            >
              <span class="mc-palette-preview" aria-hidden="true"><i></i><i></i><i></i><i></i></span>
              <strong>Custom premium</strong>
              <small data-palette-status data-palette-state="premium">Probar local</small>
            </button>
            <div class="mc-palette-fields">
              <label>
                <span>Claro</span>
                <input
                  type="color"
                  value="#d9c58f"
                  data-palette-color="boardLight"
                  aria-label="Color claro del tablero"
                />
              </label>
              <label>
                <span>Oscuro</span>
                <input
                  type="color"
                  value="#243a31"
                  data-palette-color="boardDark"
                  aria-label="Color oscuro del tablero"
                />
              </label>
              <label>
                <span>Blancas</span>
                <input
                  type="color"
                  value="#f6f1df"
                  data-palette-color="pieceWhite"
                  aria-label="Color de piezas blancas"
                />
              </label>
              <label>
                <span>Negras</span>
                <input
                  type="color"
                  value="#241745"
                  data-palette-color="pieceBlack"
                  aria-label="Color de piezas negras"
                />
              </label>
            </div>

            <div
              class="mc-palette-live-preview"
              data-palette-live-preview
              aria-label="Preview de paleta"
            >
              <div class="mc-palette-board-preview" aria-hidden="true">
                <i></i><i></i><i></i><i></i> <i></i><i></i><i></i><i></i> <i></i><i></i><i></i><i></i>
                <i></i><i></i><i></i><i></i> <b class="mc-palette-piece-white">{@symbols["K"]}</b>
                <b class="mc-palette-piece-black">{@symbols["q"]}</b>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :symbols, :map, required: true
  attr :class, :string, default: nil

  defp pack_preview(assigns) do
    ~H"""
    <span class={["mc-pack-preview", @class]} aria-hidden="true">
      <i :for={_square <- 1..16}></i>
      <b class="mc-pack-piece-black mc-piece-queen">{@symbols["q"]}</b>
      <b class="mc-pack-piece-white mc-piece-king">{@symbols["K"]}</b>
    </span>
    """
  end

  attr :game, :any, default: nil
  attr :player_id, :string, required: true
  attr :chat_draft, :string, default: ""
  attr :chat_error, :string, default: nil

  def side_panel(assigns) do
    ~H"""
    <% queue = queued_actions(@game) %> <% log_entries = panel_log(@game) %>
    <% chat_entries = chat_messages(@game) %>
    <aside class={["mc-panel", @game && "mc-panel-game"]}>
      <section
        class={[
          "mc-panel-section mc-queue-panel",
          panel_empty?(queue) && "mc-panel-section-empty",
          panel_empty?(queue) && "mc-queue-panel-compact",
          !panel_empty?(queue) && "mc-panel-section-active"
        ]}
        data-panel-state={panel_state(queue)}
      >
        <div class="mc-panel-heading">
          <h2>En proceso</h2>
          <span>{queue_count_text(queue)}</span>
        </div>

        <ol class="mc-queue-list" aria-live="polite">
          <li
            :for={{action, index} <- Enum.with_index(queue, 1)}
            class={["mc-queue-item", index == 1 && "mc-queue-next"]}
          >
            <i class={["mc-queue-index", event_color_class(action.color)]}>{index}</i>
            <span>
              <strong>{color_label(action.color)}</strong>
              <small>{square_name(action.from)} -> {square_name(action.to)}</small>
            </span>
          </li>

          <li :if={queue == []} class="mc-panel-empty">Sin movimientos por procesar</li>
        </ol>
      </section>

      <section
        class={[
          "mc-panel-section mc-log-panel",
          panel_empty?(log_entries) && "mc-panel-section-empty",
          !panel_empty?(log_entries) && "mc-panel-section-active"
        ]}
        data-panel-state={panel_state(log_entries)}
      >
        <div class="mc-panel-heading">
          <h2>Bitacora</h2>
          <span>{panel_log_count_text(log_entries)}</span>
        </div>

        <ul class="mc-log-list" aria-live="polite">
          <li
            :for={{entry, index} <- Enum.with_index(log_entries)}
            class={["mc-log-entry", GameText.log_entry_class(entry), index == 0 && "mc-log-latest"]}
          >
            <small>{GameText.log_entry_tag(entry)}</small>
            <span>{GameText.log_entry_text(entry)}</span>
          </li>

          <li :if={log_entries == []} class="mc-panel-empty">Los eventos apareceran aqui</li>
        </ul>
      </section>

      <section
        class={[
          "mc-panel-section mc-chat-panel",
          panel_empty?(chat_entries) && "mc-panel-section-empty",
          !panel_empty?(chat_entries) && "mc-panel-section-active"
        ]}
        data-panel-state={panel_state(chat_entries)}
      >
        <div class="mc-panel-heading">
          <h2>Chat</h2>
          <span>{chat_count_text(@game)}</span>
        </div>

        <ul class="mc-chat-list" data-chat-list aria-live="polite" aria-label="Chat de sala">
          <li
            :for={{entry, index} <- Enum.with_index(chat_entries)}
            class={[
              "mc-chat-entry",
              chat_entry_class(entry, @player_id),
              latest_chat_entry?(chat_entries, index) && "mc-chat-latest"
            ]}
          >
            <small>
              <strong>{chat_entry_name(entry, @player_id)}</strong>
              <span>{chat_entry_role(entry)}</span>
              <span
                :if={chat_entry_time(entry)}
                class="mc-chat-time"
                data-chat-time={chat_entry_time(entry)}
              >
                --:--
              </span>
            </small>
            <p>{entry.text}</p>
          </li>

          <li :if={chat_entries == []} class="mc-panel-empty">
            <span>Mensajes de sala apareceran aqui</span> <small>Saluda sin pausar la partida</small>
          </li>
        </ul>

        <form
          :if={@game}
          class={["mc-chat-form", !chat_send_disabled?(@chat_draft) && "mc-chat-form-ready"]}
          phx-change="chat_change"
          phx-submit="send_chat"
          data-chat-form
        >
          <label class={["mc-chat-field", chat_draft_near_limit?(@chat_draft) && "mc-chat-field-hot"]}>
            <input
              name="message"
              value={@chat_draft}
              maxlength="180"
              autocomplete="off"
              autocapitalize="sentences"
              placeholder={chat_placeholder(chat_entries)}
              aria-label="Mensaje de chat"
              data-chat-input
            /> <small>{chat_draft_length(@chat_draft)}/180</small>
          </label>
          <button
            type="submit"
            disabled={chat_send_disabled?(@chat_draft)}
            phx-disable-with="Enviando"
          >
            Enviar
          </button>
        </form>

        <p :if={@chat_error} class="mc-chat-error" role="status">{@chat_error}</p>
      </section>
    </aside>
    """
  end

  defp queued_actions(%{queue: queue}) when is_list(queue), do: queue
  defp queued_actions(_game), do: []

  defp panel_log(%{log: log}) when is_list(log), do: log
  defp panel_log(_game), do: []

  defp chat_messages(%{chat: chat}) when is_list(chat), do: Enum.reverse(chat)
  defp chat_messages(_game), do: []

  defp panel_empty?(items), do: items == []
  defp panel_state([]), do: "empty"
  defp panel_state(_items), do: "active"

  defp chat_count_text(game) do
    case chat_messages(game) do
      [] -> "Sin chat"
      [_one] -> "1 mensaje"
      messages -> "#{length(messages)} mensajes"
    end
  end

  defp chat_entry_class(%{player_id: player_id}, player_id), do: "mc-chat-mine"
  defp chat_entry_class(_entry, _player_id), do: nil
  defp latest_chat_entry?(entries, index), do: entries != [] and index == length(entries) - 1
  defp chat_send_disabled?(draft), do: String.trim(draft || "") == ""
  defp chat_placeholder([]), do: "Primer mensaje"
  defp chat_placeholder(_entries), do: "Responder en sala"

  defp chat_entry_name(%{player_id: player_id, name: name}, player_id) when is_binary(name),
    do: "Tu " <> short_chat_name(name)

  defp chat_entry_name(%{name: name}, _player_id) when is_binary(name) and name != "", do: name
  defp chat_entry_name(_entry, _player_id), do: "Jugador"
  defp chat_entry_role(%{role: role}) when is_binary(role), do: role
  defp chat_entry_role(_entry), do: "Sala"
  defp chat_entry_time(%{sent_at: sent_at}) when is_integer(sent_at), do: sent_at
  defp chat_entry_time(_entry), do: nil

  defp short_chat_name("Jugador " <> tag), do: "J-" <> tag
  defp short_chat_name(name), do: name
  defp chat_draft_length(draft), do: draft |> to_string() |> String.length()
  defp chat_draft_near_limit?(draft), do: chat_draft_length(draft) >= 150

  defp queue_count_text(actions) do
    case length(actions) do
      0 -> "Libre"
      1 -> "1 pendiente"
      count -> "#{count} pendientes"
    end
  end

  defp panel_log_count_text(entries) do
    case entries do
      [] -> "Sin eventos"
      [_one] -> "1 evento"
      entries -> "#{length(entries)} eventos"
    end
  end

  defp square_name({row, col}) when row in 0..7 and col in 0..7 do
    "#{Enum.at(@files, col)}#{8 - row}"
  end

  defp square_name(square), do: inspect(square)

  defp event_color_class(:white), do: "mc-event-white"
  defp event_color_class(:black), do: "mc-event-black"
  defp event_color_class(_color), do: "mc-event-neutral"

  defp color_label(:white), do: "Blancas"
  defp color_label(:black), do: "Negras"
  defp color_label(:practice), do: "Practica"
  defp color_label(_), do: "Espectador"
end
