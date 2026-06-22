defmodule ManaChessOnlineWeb.GameMatchComponents do
  @moduledoc false
  use ManaChessOnlineWeb, :html

  attr :phase, :map, required: true
  attr :phase_class, :string, required: true
  attr :role, :string, required: true
  attr :hint, :string, required: true

  def match_status(assigns) do
    ~H"""
    <section class={["mc-match-status", @phase_class]}>
      <div>
        <span>{@role}</span>
        <strong>{@phase.title}</strong>
      </div>
      <p>{@phase.detail}</p>
      <small>{@hint}</small>
    </section>
    """
  end

  attr :check_message, :string, default: nil
  attr :starting?, :boolean, default: false
  attr :countdown_seconds, :integer, default: nil
  attr :first_move_message, :string, default: nil
  attr :alert_message, :string, default: nil
  attr :alert_kind, :string, default: "alert"
  attr :reset_message, :string, default: nil

  def match_feedback(assigns) do
    ~H"""
    <div class="mc-feedback-zone" data-alert-kind={@alert_kind}>
      <div :if={@check_message} class="mc-check-message" role="status">
        {@check_message}
      </div>

      <div :if={@starting?} class="mc-countdown" role="timer">
        Inicia en {@countdown_seconds}
      </div>

      <div :if={@first_move_message} class="mc-turn-message" role="status">
        {@first_move_message}
      </div>

      <div :if={@alert_message} class="mc-alert-message" data-alert-kind={@alert_kind} role="status">
        <span>{@alert_message}</span>
      </div>

      <div :if={@reset_message} class="mc-reset-message" role="status">
        {@reset_message}
      </div>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :invite_path, :string, required: true
  attr :title, :string, required: true
  attr :hint, :string, required: true
  attr :copy_label, :string, required: true
  attr :copy_success_label, :string, required: true
  attr :badge, :string, default: nil
  attr :arrived_by_link?, :boolean, default: false

  def invite_strip(assigns) do
    ~H"""
    <div class={[
      "mc-invite-strip",
      @game.private? && "mc-invite-strip-private",
      @arrived_by_link? && "mc-invite-strip-arrival"
    ]}>
      <div>
        <div class="mc-invite-title-row">
          <strong>{@title}</strong>
          <span :if={@badge} class="mc-invite-badge">{@badge}</span>
        </div>
        <span :if={@arrived_by_link?} class="mc-invite-arrival-note">
          Entraste por invitacion privada
        </span>
        <span>{@hint}</span>
        <code>{@invite_path}</code>
      </div>
      <div class="mc-invite-actions">
        <button
          class="mc-copy-invite-main"
          type="button"
          data-copy-invite={@invite_path}
          data-copy-success={@copy_success_label}
          aria-label={@copy_label}
        >
          {@copy_label}
        </button>
        <a class="mc-open-invite-link" href={@invite_path}>Abrir link</a>
      </div>
    </div>
    """
  end

  attr :pending, :map, default: nil
  attr :player_id, :string, required: true

  def promotion_panel(assigns) do
    ~H"""
    <%= if @pending && @pending.player_id == @player_id do %>
      <div class="mc-promotion">
        <strong>Promocionar peon</strong>
        <button phx-click="promote" phx-value-piece="Q" data-sound-action="mode">Reina</button>
        <button phx-click="promote" phx-value-piece="R" data-sound-action="mode">Torre</button>
        <button phx-click="promote" phx-value-piece="B" data-sound-action="mode">Alfil</button>
        <button phx-click="promote" phx-value-piece="N" data-sound-action="mode">Caballo</button>
      </div>
    <% else %>
      <div :if={@pending} class="mc-check-message mc-promotion-wait" role="status">
        Esperando promocion del rival
      </div>
    <% end %>
    """
  end
end
