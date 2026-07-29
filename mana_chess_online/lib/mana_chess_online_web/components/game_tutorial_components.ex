defmodule ManaChessOnlineWeb.GameTutorialComponents do
  @moduledoc false

  use ManaChessOnlineWeb, :html

  alias ManaChessOnline.GameTutorial

  @mission_count 5

  attr :game, :map, required: true

  def tutorial_panel(assigns) do
    game = assigns.game
    stage = GameTutorial.stage(game)
    mission = GameTutorial.mission(game)
    objective = objective(game)

    assigns =
      assigns
      |> assign(:stage, stage)
      |> assign(:mission, mission)
      |> assign(:completed, completed_missions(stage, mission))
      |> assign(:mission_count, @mission_count)
      |> assign(:title, title(stage))
      |> assign(:instruction, instruction(game))
      |> assign(:objective, objective)
      |> assign(:metrics, metrics(game))
      |> assign(:piece_costs, piece_costs(game))
      |> assign(:prompt, continue_prompt(game))

    ~H"""
    <section
      class="mc-tutorial-lesson"
      data-tutorial-lesson
      data-tutorial-stage={@stage}
      aria-labelledby="mc-tutorial-title"
    >
      <header class="mc-tutorial-lesson-head">
        <div>
          <span>Campo de entrenamiento</span>
          <strong id="mc-tutorial-title">{@title}</strong>
          <p>{@instruction}</p>
        </div>
        <small>{progress_label(@stage, @mission)}</small>
      </header>

      <div class="mc-tutorial-progress" aria-hidden="true">
        <i
          :for={step <- 1..@mission_count}
          class={[
            step <= @completed && "is-complete",
            step == @mission && @stage != :complete && "is-active"
          ]}
        >
        </i>
      </div>

      <div class="mc-tutorial-objective" data-tutorial-objective>
        <span>Objetivo actual</span>
        <strong>{@objective.title}</strong>
        <small>{@objective.detail}</small>
      </div>

      <dl class="mc-tutorial-rules" aria-label="Reglas de mana de esta partida">
        <div :for={metric <- @metrics}>
          <dt>{metric.label}</dt>
          <dd>{metric.value}</dd>
          <small>{metric.note}</small>
        </div>
      </dl>

      <ol class="mc-tutorial-steps">
        <li :for={step <- tutorial_steps(@stage, @mission)} class={step.class}>
          <span>{step.number}</span>
          <div><strong>{step.title}</strong><small>{step.detail}</small></div>
        </li>
      </ol>

      <div class="mc-tutorial-costs">
        <span>Coste real por movimiento</span>
        <dl>
          <div :for={piece <- @piece_costs} class={piece.active? && "is-active"}>
            <dt>{piece.label}</dt>
            <dd>{piece.value}</dd>
          </div>
        </dl>
      </div>

      <div :if={@prompt} class="mc-tutorial-continue" data-tutorial-continue-panel>
        <button
          type="button"
          class="mc-action-primary"
          phx-click="continue_tutorial"
          disabled={@prompt.disabled?}
          data-sound-action="mode"
        >
          {@prompt.button}
        </button>
        <small>{@prompt.detail}</small>
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
          Repetir entrenamiento
        </button>
      </div>
    </section>
    """
  end

  attr :game, :map, required: true

  def tutorial_board_prompt(assigns) do
    prompt = continue_prompt(assigns.game)

    assigns =
      assigns
      |> assign(:prompt, prompt)
      |> assign(:ready?, prompt && not prompt.disabled?)

    ~H"""
    <div
      :if={@prompt}
      class={["mc-tutorial-board-prompt", @ready? && "is-ready"]}
      data-tutorial-board-prompt
      data-tutorial-prompt-ready={to_string(@ready?)}
      aria-live="polite"
    >
      <span>{@prompt.eyebrow}</span>
      <strong>{@prompt.title}</strong>
      <p>{@prompt.detail}</p>
      <button
        type="button"
        phx-click="continue_tutorial"
        disabled={@prompt.disabled?}
        data-sound-action="mode"
      >
        {@prompt.button}
      </button>
    </div>
    """
  end

  defp title(:move), do: "1. Gasta mana"
  defp title(:cooldown), do: "1. Aprende el cooldown"
  defp title(:capture_knight), do: "2. Roba mana"
  defp title(:capture_knight_result), do: "2. Mira la recompensa"

  defp title(stage) when stage in [:sprint_pawn, :sprint_knight, :sprint_bishop, :sprint_rook],
    do: "3. Encadena costes"

  defp title(:sprint_result), do: "3. Lee la barra"
  defp title(:capture_pawn), do: "4. Captura de poco valor"
  defp title(:capture_pawn_result), do: "4. Guarda la referencia"
  defp title(:capture_queen), do: "5. Captura de alto valor"
  defp title(:complete), do: "Entrenamiento completado"

  defp instruction(game) do
    stage = GameTutorial.stage(game)
    settings = game.settings

    case stage do
      :move ->
        "Mueve el peon marcado de d2 a d3. El numero sobre la pieza es el mana que pagaras."

      :cooldown ->
        "La misma pieza no puede volver a moverse hasta que termine su anillo. Tu barra sigue regenerando +#{number(setting(settings, :regen_per_second, 1.0))} por segundo."

      :capture_knight ->
        "Mueve el peon de d3 a e4. El peon captura en diagonal y puede comerse cualquier tipo de pieza enemiga."

      :capture_knight_result ->
        "La gota muestra el mana que realmente recuperaste al capturar el caballo."

      sprint_stage
      when sprint_stage in [:sprint_pawn, :sprint_knight, :sprint_bishop, :sprint_rook] ->
        sprint = GameTutorial.sprint_progress(game)

        "Haz el movimiento #{sprint.current} de #{sprint.total}. Cada pieza usa su propio coste; no necesitas esperar el cooldown de una para mover otra."

      :sprint_result ->
        plan = GameTutorial.sprint_plan(settings)

        "Pagaste #{number(plan.total)} de mana con piezas distintas. La regeneracion siguio activa entre movimientos, como en una partida real."

      :capture_pawn ->
        "Captura el peon negro de d4 con el peon blanco de c3 y observa la recompensa pequena."

      :capture_pawn_result ->
        "Ya tienes una referencia baja. La siguiente captura usa otro peon, pero el objetivo vale mucho mas."

      :capture_queen ->
        "Captura la dama negra de e4 con el peon blanco de f3. Compara la gota con la captura anterior."

      :complete ->
        "Ya gastaste, esperaste, encadenaste movimientos y comparaste tres recompensas de captura."
    end
  end

  defp objective(game) do
    stage = GameTutorial.stage(game)
    cost = GameTutorial.current_move_cost(game)
    reward = GameTutorial.capture_reward(game)
    source = GameTutorial.source_square(game)
    target = GameTutorial.target_square(game)

    case stage do
      :move ->
        move_objective("Peon d2 -> d3", cost, "Mira cuanto baja la barra amarilla.")

      :cooldown ->
        %{
          title: "Espera el anillo",
          detail: "El boton central se encendera cuando la pieza vuelva a estar lista."
        }

      :capture_knight ->
        capture_objective("Peon d3 x caballo e4", cost, reward)

      :capture_knight_result ->
        reward_result(game, "caballo")

      sprint_stage
      when sprint_stage in [:sprint_pawn, :sprint_knight, :sprint_bishop, :sprint_rook] ->
        move_objective(
          "#{piece_label(GameTutorial.current_piece_type(game))} #{GameTutorial.square_name(source)} -> #{GameTutorial.square_name(target)}",
          cost,
          sprint_detail(game)
        )

      :sprint_result ->
        plan = GameTutorial.sprint_plan(game.settings)
        current = get_in(game, [:elixir, :white]) || 0

        %{
          title: "Gastaste #{number(plan.total)} mana",
          detail:
            "#{length(plan.actions)} piezas movidas; la regeneracion siguio activa y ahora tienes #{number(current)}."
        }

      :capture_pawn ->
        capture_objective("Peon c3 x peon d4", cost, reward)

      :capture_pawn_result ->
        reward_result(game, "peon")

      :capture_queen ->
        capture_objective("Peon f3 x dama e4", cost, reward)

      :complete ->
        %{
          title: "Cinco pruebas superadas",
          detail: "Ya conoces el ciclo central de Mana Chess."
        }
    end
  end

  defp move_objective(title, cost, detail) do
    %{title: title, detail: "Coste #{number(cost)}. #{detail}"}
  end

  defp capture_objective(title, cost, reward) do
    %{
      title: title,
      detail: "Pagas #{number(cost)} y recuperas hasta +#{number(reward)}."
    }
  end

  defp reward_result(game, captured_label) do
    %{
      title: "+#{number(Map.get(game, :last_capture_refund, 0))} mana",
      detail: "Recompensa real por capturar #{captured_label}."
    }
  end

  defp sprint_detail(game) do
    sprint = GameTutorial.sprint_progress(game)

    "Movimiento #{sprint.current} de #{sprint.total}; sigue antes de que la barra regenere demasiado."
  end

  defp completed_missions(:complete, _mission), do: @mission_count
  defp completed_missions(_stage, mission), do: mission - 1

  defp progress_label(:complete, _mission), do: "#{@mission_count} de #{@mission_count}"
  defp progress_label(_stage, mission), do: "Prueba #{mission} de #{@mission_count}"

  defp tutorial_steps(stage, mission) do
    [
      tutorial_step(1, "Gasta y espera", "Coste, regeneracion y cooldown.", stage, mission),
      tutorial_step(
        2,
        "Captura caballo",
        "El objetivo devuelve su propio valor.",
        stage,
        mission
      ),
      tutorial_step(
        3,
        "Encadena costes",
        "Compara varias piezas en una rafaga.",
        stage,
        mission
      ),
      tutorial_step(4, "Captura peon", "Mide una recompensa pequena.", stage, mission),
      tutorial_step(5, "Captura dama", "Compara una recompensa grande.", stage, mission)
    ]
  end

  defp tutorial_step(number, title, detail, stage, mission) do
    class =
      cond do
        stage == :complete or number < mission -> "is-done"
        number == mission -> "is-active"
        true -> "is-pending"
      end

    %{number: number, title: title, detail: detail, class: class}
  end

  defp metrics(game) do
    settings = game.settings
    max_elixir = setting(settings, :max_elixir, 10.0)
    current = get_in(game, [:elixir, :white]) || 0
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
        label: "Mana ahora",
        value: "#{number(current)} / #{number(max_elixir)}",
        note: "Blancas"
      },
      %{
        label: "Regeneracion",
        value: "+#{number(regen)} / s",
        note: "Continua durante la partida"
      },
      %{label: "Captura", value: "#{number(refund)}%", note: "Del coste del objetivo"},
      %{label: "Cooldown", value: cooldown, note: "Por pieza movida"}
    ]
  end

  defp piece_costs(game) do
    active_piece = GameTutorial.current_piece_type(game)

    [
      {:pawn, "Peon"},
      {:knight, "Caballo"},
      {:bishop, "Alfil"},
      {:rook, "Torre"},
      {:queen, "Dama"},
      {:king, "Rey"}
    ]
    |> Enum.map(fn {piece, label} ->
      %{
        label: label,
        value: number(GameTutorial.piece_cost(game.settings, piece)),
        active?: piece == active_piece
      }
    end)
  end

  defp continue_prompt(game) do
    stage = GameTutorial.stage(game)
    remaining_ms = GameTutorial.cooldown_remaining_ms(game)

    case stage do
      :cooldown when remaining_ms > 0 ->
        seconds = max(ceil(remaining_ms / 1000), 1)

        %{
          eyebrow: "Cooldown activo",
          title: "Espera #{seconds} s",
          detail: "Mira el anillo sobre el peon y la regeneracion de mana.",
          button: "Listo en #{seconds} s",
          disabled?: true
        }

      :cooldown ->
        %{
          eyebrow: "Pieza lista",
          title: "El cooldown termino",
          detail: "Ahora puedes usar el mismo peon para capturar.",
          button: "Continuar: captura el caballo",
          disabled?: false
        }

      :capture_knight_result ->
        %{
          eyebrow: "Primera captura",
          title: "+#{number(Map.get(game, :last_capture_refund, 0))} mana",
          detail: "El caballo devolvio mas que un peon porque su coste es mayor.",
          button: "Siguiente: prueba varios costes",
          disabled?: false
        }

      :sprint_result ->
        plan = GameTutorial.sprint_plan(game.settings)

        %{
          eyebrow: "Rafaga completada",
          title: "#{length(plan.actions)} piezas, #{number(plan.total)} mana",
          detail: "Los cooldowns son individuales y la regeneracion continuo mientras movias.",
          button: "Siguiente: compara capturas",
          disabled?: false
        }

      :capture_pawn_result ->
        queen_reward = GameTutorial.refund(game.settings, :queen)

        %{
          eyebrow: "Referencia guardada",
          title: "+#{number(Map.get(game, :last_capture_refund, 0))} por el peon",
          detail: "La dama puede devolver hasta +#{number(queen_reward)} con las mismas reglas.",
          button: "Ahora captura la dama",
          disabled?: false
        }

      _stage ->
        nil
    end
  end

  defp piece_label(:pawn), do: "Peon"
  defp piece_label(:knight), do: "Caballo"
  defp piece_label(:bishop), do: "Alfil"
  defp piece_label(:rook), do: "Torre"
  defp piece_label(:queen), do: "Dama"
  defp piece_label(:king), do: "Rey"
  defp piece_label(_piece), do: "Pieza"

  defp setting(settings, key, fallback), do: Map.get(settings, key, fallback)

  defp number(nil), do: "0"
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
