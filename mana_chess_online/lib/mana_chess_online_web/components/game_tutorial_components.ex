defmodule ManaChessOnlineWeb.GameTutorialComponents do
  @moduledoc false

  use ManaChessOnlineWeb, :html

  alias ManaChessOnline.GameTutorial

  attr :game, :map, required: true

  def tutorial_panel(assigns) do
    stage = GameTutorial.stage(assigns.game)
    settings = assigns.game.settings
    pawn_cost = piece_cost(settings, :pawn, 1.0)
    refund = pawn_cost * setting(settings, :capture_refund_percent, 40) / 100
    cooldown_remaining_ms = GameTutorial.cooldown_remaining_ms(assigns.game)

    assigns =
      assigns
      |> assign(:stage, stage)
      |> assign(:progress, progress(stage))
      |> assign(:title, title(stage))
      |> assign(
        :instruction,
        instruction(stage, settings, pawn_cost, refund, cooldown_remaining_ms)
      )
      |> assign(:cooldown_remaining_ms, cooldown_remaining_ms)
      |> assign(:metrics, metrics(settings))
      |> assign(:piece_costs, piece_costs(settings))

    ~H"""
    <section
      class="mc-tutorial-lesson"
      data-tutorial-lesson
      data-tutorial-stage={@stage}
      aria-labelledby="mc-tutorial-title"
    >
      <header class="mc-tutorial-lesson-head">
        <div>
          <span>Leccion interactiva</span>
          <strong id="mc-tutorial-title">{@title}</strong>
          <p>{@instruction}</p>
        </div>
        <small>{progress_label(@stage)}</small>
      </header>

      <div class="mc-tutorial-progress" aria-hidden="true">
        <i :for={step <- 1..3} class={step <= @progress && "is-complete"}></i>
      </div>

      <dl class="mc-tutorial-rules" aria-label="Reglas de mana de esta partida">
        <div :for={metric <- @metrics}>
          <dt>{metric.label}</dt>
          <dd>{metric.value}</dd>
          <small>{metric.note}</small>
        </div>
      </dl>

      <ol class="mc-tutorial-steps">
        <li :for={step <- tutorial_steps(@stage)} class={step.class}>
          <span>{step.number}</span>
          <div><strong>{step.title}</strong><small>{step.detail}</small></div>
        </li>
      </ol>

      <div class="mc-tutorial-costs">
        <span>Coste por movimiento</span>
        <dl>
          <div :for={piece <- @piece_costs}>
            <dt>{piece.label}</dt>
            <dd>{piece.value}</dd>
          </div>
        </dl>
      </div>

      <div :if={@stage == :cooldown} class="mc-tutorial-continue">
        <button
          type="button"
          class="mc-action-primary"
          phx-click="continue_tutorial"
          disabled={@cooldown_remaining_ms > 0}
          data-sound-action="mode"
        >
          {continue_label(@cooldown_remaining_ms)}
        </button>
        <small>La leccion no avanza hasta que confirmes.</small>
      </div>

      <div :if={@stage == :complete} class="mc-tutorial-finish">
        <button
          type="button"
          class="mc-action-primary"
          phx-click="finish_tutorial"
          data-sound-action="mode"
        >
          Jugar contra Aprendiz
        </button>
        <button
          type="button"
          class="mc-action-secondary"
          phx-click="start_tutorial"
          data-sound-action="reset"
        >
          Repetir leccion
        </button>
      </div>
    </section>
    """
  end

  defp title(:move), do: "1. Gasta mana"
  defp title(:cooldown), do: "2. Mira el ritmo"
  defp title(:capture), do: "3. Recupera al capturar"
  defp title(:complete), do: "Leccion completada"

  defp instruction(:move, _settings, pawn_cost, _refund, _remaining_ms) do
    "Busca la columna d y la fila 2: selecciona el peon marcado en d2. Muevelo una casilla a d3. La jugada cuesta #{number(pawn_cost)} de mana."
  end

  defp instruction(:cooldown, settings, _pawn_cost, _refund, remaining_ms) do
    regen = number(setting(settings, :regen_per_second, 1.0))

    if remaining_ms > 0 do
      "El anillo bloquea temporalmente al peon. Mientras esperas, tu mana vuelve a +#{regen} por segundo."
    else
      "El anillo termino y tu mana siguio regenerando +#{regen}/s. Confirma cuando hayas visto ambos indicadores."
    end
  end

  defp instruction(:capture, settings, pawn_cost, refund, _remaining_ms) do
    percent = number(setting(settings, :capture_refund_percent, 40))
    net = max(pawn_cost - refund, 0)

    "Desde d3, mueve el peon en diagonal a e4 para capturar: pagas #{number(pawn_cost)}, recuperas #{number(refund)} (#{percent}%) y el gasto neto es #{number(net)}."
  end

  defp instruction(:complete, settings, pawn_cost, refund, _remaining_ms) do
    regen = number(setting(settings, :regen_per_second, 1.0))

    "Ya gastaste #{number(pawn_cost)}, esperaste el cooldown y recuperaste #{number(refund)} al capturar. Tu mana sigue regenerando +#{regen}/s."
  end

  defp progress(:move), do: 0
  defp progress(:cooldown), do: 1
  defp progress(:capture), do: 2
  defp progress(:complete), do: 3

  defp progress_label(:complete), do: "3 de 3"
  defp progress_label(stage), do: "Paso #{progress(stage) + 1} de 3"

  defp continue_label(remaining_ms) when remaining_ms > 0,
    do: "Espera #{max(ceil(remaining_ms / 1000), 1)} s"

  defp continue_label(_remaining_ms), do: "Continuar a la captura"

  defp tutorial_steps(stage) do
    current = progress(stage) + if(stage == :complete, do: 0, else: 1)

    [
      tutorial_step(1, "Gasta mana", "Columna d: de la fila 2 a la 3.", current, stage),
      tutorial_step(2, "Espera y regenera", "Observa barra y cooldown.", current, stage),
      tutorial_step(3, "Captura y recupera", "Desde d3, captura en e4.", current, stage)
    ]
  end

  defp tutorial_step(number, title, detail, current, stage) do
    class =
      cond do
        stage == :complete or number < current -> "is-done"
        number == current -> "is-active"
        true -> "is-pending"
      end

    %{number: number, title: title, detail: detail, class: class}
  end

  defp metrics(settings) do
    max_elixir = setting(settings, :max_elixir, 10.0)
    initial_elixir = min(setting(settings, :initial_elixir, max_elixir), max_elixir)
    regen = setting(settings, :regen_per_second, 1.0)
    refund = setting(settings, :capture_refund_percent, 40)

    cooldown =
      if Map.get(settings, :cooldown_enabled, true) do
        "#{number(setting(settings, :cooldown_seconds, 1.0))} s"
      else
        "Desactivado"
      end

    [
      %{
        label: "Mana inicial",
        value: "#{number(initial_elixir)} / #{number(max_elixir)}",
        note: "Antes de abrir"
      },
      %{label: "Regeneracion", value: "+#{number(regen)} / s", note: "Tras la primera jugada"},
      %{label: "Captura", value: "#{number(refund)}%", note: "Del coste capturado"},
      %{label: "Cooldown", value: cooldown, note: "Por pieza movida"}
    ]
  end

  defp piece_costs(settings) do
    [
      {:pawn, "Peon", 1.0},
      {:knight, "Caballo", 3.0},
      {:bishop, "Alfil", 3.0},
      {:rook, "Torre", 4.0},
      {:queen, "Dama", 6.0},
      {:king, "Rey", 3.0}
    ]
    |> Enum.map(fn {piece, label, fallback} ->
      %{label: label, value: number(piece_cost(settings, piece, fallback))}
    end)
  end

  defp piece_cost(settings, piece, fallback) do
    settings
    |> Map.get(:costs, %{})
    |> Map.get(piece, fallback)
  end

  defp setting(settings, key, fallback), do: Map.get(settings, key, fallback)

  defp number(value) when is_integer(value), do: Integer.to_string(value)

  defp number(value) when is_float(value) do
    value
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp number(value), do: to_string(value)
end
