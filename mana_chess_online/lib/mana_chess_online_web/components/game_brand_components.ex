defmodule ManaChessOnlineWeb.GameBrandComponents do
  @moduledoc false
  use ManaChessOnlineWeb, :html

  attr :title, :string, required: true
  attr :kicker, :string, default: "Mana Chess"
  attr :detail, :string, default: nil
  attr :class, :string, default: "mc-brand-block"
  attr :logo_class, :string, default: "mc-brand-mark"
  attr :logo_alt, :string, default: ""
  attr :show_mark?, :boolean, default: true

  def brand_lockup(assigns) do
    ~H"""
    <div class={@class}>
      <img :if={@show_mark?} src={~p"/images/logo.svg"} alt={@logo_alt} class={@logo_class} />
      <div>
        <p class="mc-kicker">{@kicker}</p>
        <h1>{@title}</h1>
        <p :if={@detail} class="mc-game-id">{@detail}</p>
      </div>
    </div>
    """
  end
end
