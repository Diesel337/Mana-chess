defmodule ManaChessOnlineWeb.GameLive do
  use ManaChessOnlineWeb, :live_view

  alias ManaChessOnline.GameLobby
  alias ManaChessOnline.GameRules

  @symbols %{
    "r" => "♜",
    "n" => "♞",
    "b" => "♝",
    "q" => "♛",
    "k" => "♚",
    "p" => "♙",
    "R" => "♖",
    "N" => "♘",
    "B" => "♗",
    "Q" => "♕",
    "K" => "♔",
    "P" => "♙",
    "." => ""
  }

  @impl true
  def mount(params, session, socket) do
    player_id = Map.get(session, "player_id") || random_player_id()
    view =
      case params do
        %{"game_id" => game_id} -> GameLobby.watch(player_id, game_id)
        _ -> GameLobby.join(player_id)
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.lobby_topic())

      if view.game_id do
        Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
      end
    end

    {:ok,
     socket
     |> assign(:page_title, "Mana Chess Online")
     |> assign(:player_id, player_id)
     |> assign(:game_id, view.game_id)
     |> assign(:color, view.color)
     |> assign(:game, view.game)
     |> assign(:lobby, view.lobby)
     |> assign(:symbols, @symbols)
     |> assign(:valid_moves, [])
     |> assign(:selected, nil)
     |> assign(:local_alert, nil)
     |> assign(:reconnected?, recovered_session?(params, view))
     |> assign(:tutorial?, false)}
  end

  defp random_player_id do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @impl true
  def handle_event("select", %{"r" => r, "c" => c}, socket) do
    r = String.to_integer(r)
    c = String.to_integer(c)
    piece = GameRules.at(socket.assigns.game.board, r, c)
    piece_color = GameRules.color(piece)

    selected =
      if selectable_square?(socket.assigns.game, socket.assigns.color, piece, piece_color) do
        {r, c}
      else
        nil
      end

    valid_moves =
      if selected do
        GameRules.legal_moves_for(socket.assigns.game.board, r, c, piece_color, socket.assigns.game.castling_rights)
      else
        []
      end

    {:noreply, assign(socket, selected: selected, valid_moves: valid_moves, local_alert: select_alert(socket.assigns.game, socket.assigns.color, piece, piece_color, selected))}
  end

  def handle_event("move", %{"r" => r, "c" => c}, %{assigns: %{selected: nil}} = socket) do
    handle_event("select", %{"r" => r, "c" => c}, socket)
  end

  def handle_event("move", %{"r" => r, "c" => c}, socket) do
    GameLobby.enqueue(socket.assigns.player_id, socket.assigns.selected, {String.to_integer(r), String.to_integer(c)})
    {:noreply, socket |> refresh_assignment() |> assign(:local_alert, nil)}
  end

  def handle_event("drag_move", %{"from_r" => from_r, "from_c" => from_c, "to_r" => to_r, "to_c" => to_c}, socket) do
    from = {String.to_integer(from_r), String.to_integer(from_c)}
    to = {String.to_integer(to_r), String.to_integer(to_c)}
    piece = GameRules.at(socket.assigns.game.board, elem(from, 0), elem(from, 1))

    if manual_control_allowed?(socket.assigns.game, socket.assigns.color, GameRules.color(piece)) do
      GameLobby.enqueue(socket.assigns.player_id, from, to)
    end

    {:noreply, socket |> refresh_assignment() |> assign(:local_alert, nil)}
  end

  def handle_event("reset", _params, socket) do
    :ok = GameLobby.reset(socket.assigns.player_id)
    {:noreply, refresh_assignment(socket)}
  end

  def handle_event("start_game", _params, socket) do
    :ok = GameLobby.start_game(socket.assigns.player_id)
    {:noreply, refresh_assignment(socket)}
  end

  def handle_event("ready_to_start", _params, socket) do
    :ok = GameLobby.ready_to_start(socket.assigns.player_id)
    {:noreply, refresh_assignment(socket)}
  end

  def handle_event("start_practice", _params, socket) do
    view = GameLobby.start_practice(socket.assigns.player_id)

    if connected?(socket) and view.game_id do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
    end

    {:noreply, socket |> assign_view(view) |> assign(:tutorial?, false)}
  end

  def handle_event("start_tutorial", _params, socket) do
    view = GameLobby.start_practice(socket.assigns.player_id)

    if connected?(socket) and view.game_id do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
    end

    {:noreply, socket |> assign_view(view) |> assign(:tutorial?, true)}
  end

  def handle_event("toggle_practice_bot", _params, socket) do
    view = GameLobby.toggle_practice_bot(socket.assigns.player_id)

    if connected?(socket) and view.game_id do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
    end

    {:noreply, assign_view(socket, view)}
  end

  def handle_event("leave", _params, socket) do
    :ok = GameLobby.leave(socket.assigns.player_id)
    {:noreply, assign_view(socket, GameLobby.join(socket.assigns.player_id))}
  end

  def handle_event("clear_room", %{"game" => game_id}, socket) do
    :ok = GameLobby.clear_room(game_id)
    {:noreply, assign_view(socket, GameLobby.join(socket.assigns.player_id))}
  end

  def handle_event("promote", %{"piece" => piece}, socket) do
    :ok = GameLobby.promote(socket.assigns.player_id, piece)
    {:noreply, assign(socket, selected: nil, valid_moves: [])}
  end

  def handle_event("sit", %{"game" => game_id, "color" => color}, socket) do
    view = GameLobby.sit(socket.assigns.player_id, game_id, color_param(color))

    if connected?(socket) and view.game_id do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
    end

    {:noreply, assign_view(socket, view)}
  end

  def handle_event("sit_anywhere", _params, socket) do
    view = GameLobby.sit_anywhere(socket.assigns.player_id)

    if connected?(socket) and view.game_id do
      Phoenix.PubSub.subscribe(ManaChessOnline.PubSub, GameLobby.topic(view.game_id))
    end

    {:noreply, assign_view(socket, view)}
  end

  @impl true
  def handle_info({:game_update, %{id: game_id} = game}, %{assigns: %{game_id: game_id}} = socket) do
    {:noreply, assign(socket, :game, game)}
  end

  def handle_info({:game_update, _game}, socket), do: {:noreply, socket}

  def handle_info({:lobby_update, lobby}, socket) do
    {:noreply, assign(socket, :lobby, lobby)}
  end

  defp refresh_assignment(socket) do
    view =
      if socket.assigns.game_id && observing?(socket.assigns.game, socket.assigns.player_id) do
        GameLobby.watch(socket.assigns.player_id, socket.assigns.game_id)
      else
        GameLobby.join(socket.assigns.player_id)
      end

    assign_view(socket, view)
  end

  defp assign_view(socket, view) do
    socket
    |> assign(:game_id, view.game_id)
    |> assign(:color, view.color)
    |> assign(:game, view.game)
    |> assign(:lobby, view.lobby)
    |> assign(:valid_moves, [])
    |> assign(:selected, nil)
    |> assign(:local_alert, nil)
    |> assign(:reconnected?, false)
  end

  defp rows_for(%{color: :black, game: %{board: board}}), do: board |> Enum.with_index() |> Enum.reverse()
  defp rows_for(%{game: %{board: board}}), do: Enum.with_index(board)

  defp cols_for(:black, row), do: row |> Enum.with_index() |> Enum.reverse()
  defp cols_for(_color, row), do: Enum.with_index(row)

  defp selected?({r, c}, {r, c}), do: true
  defp selected?(_, _), do: false

  defp in_check_square?(game, r, c) do
    Enum.any?(game.checked_colors, &(GameRules.king_square(game.board, &1) == {r, c}))
  end

  defp square_class(game, r, c, selected, valid_moves) do
    [
      "mc-square",
      rem(r + c, 2) == 0 && "mc-light",
      rem(r + c, 2) == 1 && "mc-dark",
      selected?(selected, {r, c}) && "mc-selected",
      {r, c} in valid_moves && "mc-valid",
      in_check_square?(game, r, c) && "mc-check",
      cooldown_active?(game, {r, c}) && "mc-cooldown"
    ]
  end

  defp piece_class("."), do: "mc-piece"
  defp piece_class(piece), do: "mc-piece mc-" <> Atom.to_string(GameRules.color(piece))

  defp color_label(:white), do: "Blancas"
  defp color_label(:black), do: "Negras"
  defp color_label(:practice), do: "Practica"
  defp color_label(_), do: "Espectador"

  defp top_elixir_color(:black), do: :white
  defp top_elixir_color(_color), do: :black

  defp bottom_elixir_color(:black), do: :black
  defp bottom_elixir_color(_color), do: :white

  defp elixir_color_class(:black), do: "mc-elixir-black"
  defp elixir_color_class(:white), do: "mc-elixir-white"

  defp seat_label(player_id, player_id), do: "Tu"
  defp seat_label(nil, _player_id), do: "Libre"
  defp seat_label(_player_id, _current_player_id), do: "Ocupado"

  defp status_label(:waiting), do: "Esperando rival"
  defp status_label(:ready), do: "Listos para empezar"
  defp status_label({:starting, _starts_at}), do: "Iniciando"
  defp status_label(:playing), do: "Jugando"
  defp status_label(:promotion), do: "Promocion pendiente"
  defp status_label({:winner, color}), do: "Ganaron #{color_label(color)}"
  defp status_label({:checkmate, winner, _loser}), do: "Jaque mate: ganan #{color_label(winner)}"
  defp status_label(:draw), do: "Empate"
  defp status_label(_), do: "Sin lugar"

  defp start_label(%{practice?: true}), do: "Empezar practica"
  defp start_label(_game), do: "Empezar partida"

  defp seated_in?(game, player_id), do: game.players.white == player_id or game.players.black == player_id
  defp observing?(nil, _player_id), do: false
  defp observing?(game, player_id), do: not game.practice? and not seated_in?(game, player_id)
  defp seat_open?(game, color), do: is_nil(game.players[color])
  defp recovered_session?(%{"game_id" => _game_id}, %{game: game, color: color}) when not is_nil(game) and color in [:white, :black, :practice], do: true
  defp recovered_session?(params, %{game: game, color: color}) when params == %{} and not is_nil(game) and color in [:white, :black, :practice], do: true
  defp recovered_session?(_params, _view), do: false
  defp lobby_status(:waiting), do: "Esperando"
  defp lobby_status(:ready), do: "Listos"
  defp lobby_status({:starting, _starts_at}), do: "Iniciando"
  defp lobby_status(:playing), do: "Jugando"
  defp lobby_status(:promotion), do: "Promocion"
  defp lobby_status({:winner, color}), do: "Ganan #{color_label(color)}"
  defp lobby_status({:checkmate, winner, _loser}), do: "Mate: #{color_label(winner)}"
  defp lobby_status(:draw), do: "Empate"
  defp lobby_status(_), do: "-"
  defp lobby_room_name("game_" <> number), do: "Sala " <> number
  defp lobby_room_name(game_id), do: game_id
  defp clearable_room?(%{status: status}), do: status in [:waiting, :ready]

  defp lobby_count(lobby, status) do
    Enum.count(lobby, &(&1.status == status))
  end

  defp open_seats_count(lobby) do
    Enum.reduce(lobby, 0, fn game, total ->
      total + if(is_nil(game.players.white), do: 1, else: 0) + if(is_nil(game.players.black), do: 1, else: 0)
    end)
  end

  defp color_param("white"), do: :white
  defp color_param("black"), do: :black

  defp final_result(%{status: {:checkmate, winner, loser}} = game, player_color) do
    %{
      title: final_title(game, winner, player_color),
      detail: "Jaque mate a #{color_label(loser)}.",
      tone: if(player_color in [winner, :practice], do: :win, else: :loss)
    }
  end

  defp final_result(%{status: {:winner, winner}} = game, player_color) do
    %{
      title: final_title(game, winner, player_color),
      detail: "Partida terminada.",
      tone: if(player_color in [winner, :practice], do: :win, else: :loss)
    }
  end

  defp final_result(%{status: :draw}, _player_color) do
    %{title: "Empate", detail: "Nadie tiene mate.", tone: :draw}
  end

  defp final_result(_game, _player_color), do: nil

  defp final_title(%{practice?: true}, :white, _player_color), do: "Ganaste"
  defp final_title(%{practice?: true}, :black, _player_color), do: "Gana el bot"
  defp final_title(_game, winner, winner), do: "Ganaste"
  defp final_title(_game, _winner, player_color) when player_color in [:white, :black], do: "Perdiste"
  defp final_title(_game, winner, _player_color), do: "Ganan #{color_label(winner)}"

  defp final_panel_class(%{tone: :win}), do: "mc-final-win"
  defp final_panel_class(%{tone: :loss}), do: "mc-final-loss"
  defp final_panel_class(_result), do: "mc-final-draw"

  defp stats_result_key(%{finished_at: finished_at} = game, player_color) when not is_nil(finished_at) do
    case stats_outcome(game, player_color) do
      nil -> ""
      _outcome -> "#{game.id}:#{finished_at}:#{inspect(game.status)}"
    end
  end

  defp stats_result_key(_game, _player_color), do: ""

  defp stats_outcome(%{status: :draw, practice?: true}, _player_color), do: "draw"
  defp stats_outcome(%{status: :draw}, player_color) when player_color in [:white, :black], do: "draw"

  defp stats_outcome(%{status: {:checkmate, winner, _loser}} = game, player_color) do
    stats_winner_outcome(game, winner, player_color)
  end

  defp stats_outcome(%{status: {:winner, winner}} = game, player_color) do
    stats_winner_outcome(game, winner, player_color)
  end

  defp stats_outcome(_game, _player_color), do: nil

  defp stats_winner_outcome(%{practice?: true}, :white, _player_color), do: "win"
  defp stats_winner_outcome(%{practice?: true}, :black, _player_color), do: "loss"
  defp stats_winner_outcome(_game, winner, winner), do: "win"
  defp stats_winner_outcome(_game, _winner, player_color) when player_color in [:white, :black], do: "loss"
  defp stats_winner_outcome(_game, _winner, _player_color), do: nil

  defp check_message(%{checked_colors: []}), do: nil
  defp check_message(%{status: {:checkmate, _winner, loser}}), do: "Jaque mate a #{color_label(loser)}"

  defp check_message(%{checked_colors: colors}) do
    colors
    |> Enum.map(&color_label/1)
    |> Enum.join(" y ")
    |> Kernel.<>(" en jaque")
  end

  defp starting?(%{status: {:starting, _starts_at}}), do: true
  defp starting?(_game), do: false

  defp first_move_message(%{status: :playing, first_move_pending: :white}), do: "Blancas abren la partida"
  defp first_move_message(_game), do: nil

  defp tutorial_steps(game) do
    moved? = tutorial_white_moved?(game)
    bot_on? = game.bot_enabled?

    [
      %{state: tutorial_step_state(moved?, true), text: "Mueve una pieza blanca para abrir."},
      %{state: tutorial_step_state(moved?, moved?), text: "Mira elixir y cooldown: son el ritmo del modo."},
      %{state: tutorial_step_state(bot_on?, moved?), text: "Prende BOT para que Negras conteste."}
    ]
  end

  defp tutorial_complete?(game), do: Enum.all?(tutorial_steps(game), &(&1.state == :done))

  defp tutorial_step_state(true, _available?), do: :done
  defp tutorial_step_state(false, true), do: :active
  defp tutorial_step_state(false, false), do: :pending

  defp tutorial_step_class(%{state: :done}), do: "mc-tutorial-done"
  defp tutorial_step_class(%{state: :active}), do: "mc-tutorial-active"
  defp tutorial_step_class(_step), do: "mc-tutorial-pending"

  defp tutorial_white_moved?(game) do
    game.first_move_pending != :white or Enum.any?(game.log, &String.starts_with?(&1, "Blancas "))
  end

  defp alert_message(%{log: [latest | _rest]}) do
    cond do
      String.starts_with?(latest, "Movimiento rechazado: ") ->
        latest |> String.replace_prefix("Movimiento rechazado: ", "") |> sentence_case()

      String.starts_with?(latest, "Movimiento descartado: ") ->
        latest |> String.replace_prefix("Movimiento descartado: ", "") |> sentence_case()

      String.starts_with?(latest, "Sin elixir") ->
        latest

      true ->
        nil
    end
  end

  defp alert_message(_game), do: nil
  defp visible_alert(game, local_alert), do: local_alert || alert_message(game)

  defp sentence_case(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp sentence_case(message), do: message

  defp reset_message(%{reset_requests: []}), do: nil

  defp reset_message(game) do
    game.reset_requests
    |> Enum.map(fn player_id ->
      cond do
        game.players.white == player_id -> "Blancas"
        game.players.black == player_id -> "Negras"
        true -> "Un jugador"
      end
    end)
    |> Enum.join(" y ")
    |> Kernel.<>(" pidio reiniciar")
  end

  defp reset_label(%{practice?: true}, _player_id), do: "Reiniciar practica"

  defp reset_label(%{reset_requests: requests}, player_id) do
    if player_id in requests do
      "Esperando rival"
    else
      "Pedir reinicio"
    end
  end

  defp reset_disabled?(%{practice?: true}, _player_id), do: false
  defp reset_disabled?(%{reset_requests: requests}, player_id), do: player_id in requests

  defp ready_to_start_label(%{start_requests: requests}, player_id) do
    if player_id in requests do
      "Esperando rival"
    else
      "Listo"
    end
  end

  defp ready_to_start_disabled?(%{start_requests: requests}, player_id), do: player_id in requests

  defp can_move_now?(%{status: :playing, first_move_pending: nil}, _color), do: true
  defp can_move_now?(%{status: :playing, first_move_pending: color}, color), do: true
  defp can_move_now?(_game, _color), do: false

  defp selectable_square?(game, player_color, piece, piece_color) do
    piece != "." and manual_control_allowed?(game, player_color, piece_color) and can_move_now?(game, piece_color)
  end

  defp select_alert(_game, _player_color, _piece, _piece_color, {_r, _c}), do: nil
  defp select_alert(_game, _player_color, ".", _piece_color, nil), do: nil
  defp select_alert(%{status: status}, _player_color, _piece, _piece_color, nil) when status not in [:playing], do: "La partida todavia no esta jugando."
  defp select_alert(game, _player_color, _piece, piece_color, nil) when not is_nil(piece_color) do
    if not can_move_now?(game, piece_color) do
      "Blancas deben abrir la partida."
    else
      "Esa pieza no es tuya."
    end
  end
  defp select_alert(_game, _player_color, _piece, _piece_color, nil), do: "No puedes mover esa pieza."

  defp controls_color?(:practice, color) when color in [:white, :black], do: true
  defp controls_color?(color, color), do: true
  defp controls_color?(_player_color, _piece_color), do: false

  defp manual_control_allowed?(%{practice?: true, bot_enabled?: true}, :practice, :black), do: false
  defp manual_control_allowed?(_game, player_color, piece_color), do: controls_color?(player_color, piece_color)

  defp bot_toggle_label(%{bot_enabled?: true}), do: "ON"
  defp bot_toggle_label(_game), do: "OFF"

  defp cooldown_active?(game, square), do: not is_nil(cooldown_for(game, square))

  defp cooldown_for(game, square) do
    game.cooldowns
    |> Enum.find_value(fn cooldown ->
      if cooldown.at == square, do: cooldown
    end)
  end

  defp cooldown_style(game, square) do
    case cooldown_for(game, square) do
      nil -> nil
      cooldown ->
        elapsed = max(cooldown.total_ms - cooldown.remaining_ms, 0)

        "--cooldown-duration: #{cooldown.total_ms}ms; --cooldown-delay: -#{elapsed}ms"
    end
  end

  defp elixir_width(game, color) do
    percent =
      game.elixir[color]
      |> Kernel./(game.settings.max_elixir)
      |> Kernel.*(100)
      |> max(0)
      |> min(100)
      |> Float.round(1)

    "width: #{percent}%"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="mc-local-stats"
      class="mc-shell"
      phx-hook="LocalStats"
      data-result-key={stats_result_key(@game, @color)}
      data-result-outcome={stats_outcome(@game, @color) || ""}
    >
      <section class="mc-game">
        <div class="mc-header">
          <div>
            <p class="mc-kicker">Mana Chess Online</p>
            <h1>{if @game_id, do: "Partida #{@game_id}", else: "Lobby"}</h1>
          </div>
          <div class="mc-badge">
            <span>{color_label(@color)}</span>
            <strong>{status_label(@game && @game.status)}</strong>
          </div>
        </div>

        <%= if @game do %>
          <div :if={@game.practice?} class="mc-practice-banner">
            <strong>Modo practica</strong>
            <span>Controlas ambos lados para probar reglas, elixir y cooldowns.</span>
            <div class="mc-bot-control">
              <span>BOT</span>
              <button class={["mc-bot-toggle", @game.bot_enabled? && "mc-bot-toggle-on"]} type="button" phx-click="toggle_practice_bot">
                {bot_toggle_label(@game)}
              </button>
            </div>
          </div>

          <div :if={@tutorial? && @game.practice?} class="mc-tutorial mc-tutorial-pop">
            <div>
              <strong>{if tutorial_complete?(@game), do: "Listo: ya sabes el modo", else: "Mana Chess en 1 minuto"}</strong>
              <span>{if tutorial_complete?(@game), do: "Sigue en practica o reta a alguien online.", else: "No es clase de ajedrez: solo aprende elixir, cooldown y bot."}</span>
            </div>
            <ol>
              <li :for={step <- tutorial_steps(@game)} class={tutorial_step_class(step)}>
                <span></span>
                {step.text}
              </li>
            </ol>
          </div>

          <div :if={observing?(@game, @player_id)} class="mc-spectator-banner">
            <strong>Observando partida</strong>
            <span>Puedes mirar el juego en curso sin ocupar asiento.</span>
          </div>

          <div :if={@reconnected?} class="mc-reconnect-banner">
            <strong>Reconectado</strong>
            <span>Recuperaste tu asiento como {color_label(@color)}.</span>
          </div>

          <div :if={!@game.practice?} class="mc-seats">
            <div class={["mc-seat", @color == :white && "mc-seat-current"]}>
              <strong>Blancas</strong>
              <span>{seat_label(@game.players.white, @player_id)}</span>
            </div>
            <div class={["mc-seat", @color == :black && "mc-seat-current"]}>
              <strong>Negras</strong>
              <span>{seat_label(@game.players.black, @player_id)}</span>
            </div>
            <p :if={@game.status == :waiting}>
              Blancas no puede iniciar hasta que Negras se siente. Para jugar solo usa Modo practica.
            </p>
            <div class="mc-seat-actions">
              <a href={~p"/game/#{@game.id}"}>Link de invitacion</a>
              <button
                :if={!seated_in?(@game, @player_id) && seat_open?(@game, :white)}
                type="button"
                phx-click="sit"
                phx-value-game={@game.id}
                phx-value-color="white"
              >
                Sentarme como Blancas
              </button>
              <button
                :if={!seated_in?(@game, @player_id) && seat_open?(@game, :black)}
                type="button"
                phx-click="sit"
                phx-value-game={@game.id}
                phx-value-color="black"
              >
                Sentarme como Negras
              </button>
            </div>
          </div>

          <div class="mc-feedback-zone">
            <div :if={check_message(@game)} class="mc-check-message">
              {check_message(@game)}
            </div>

            <div :if={starting?(@game)} class="mc-countdown">
              Inicia en {@game.countdown_seconds}
            </div>

            <div :if={first_move_message(@game)} class="mc-turn-message">
              {first_move_message(@game)}
            </div>

            <div :if={visible_alert(@game, @local_alert)} class="mc-alert-message">
              {visible_alert(@game, @local_alert)}
            </div>

            <div :if={reset_message(@game)} class="mc-reset-message">
              {reset_message(@game)}
            </div>
          </div>

          <div :if={final_result(@game, @color)} class={["mc-final-panel", final_panel_class(final_result(@game, @color))]}>
            <% result = final_result(@game, @color) %>
            <div>
              <strong>{result.title}</strong>
              <span>{result.detail}</span>
            </div>
            <button type="button" phx-click="reset" disabled={reset_disabled?(@game, @player_id)}>
              {if @game.practice?, do: "Jugar otra vez", else: "Pedir revancha"}
            </button>
          </div>

          <div :if={@game.promotion_pending && @game.promotion_pending.player_id == @player_id} class="mc-promotion">
            <strong>Promocionar peon</strong>
            <button phx-click="promote" phx-value-piece="Q">Reina</button>
            <button phx-click="promote" phx-value-piece="R">Torre</button>
            <button phx-click="promote" phx-value-piece="B">Alfil</button>
            <button phx-click="promote" phx-value-piece="N">Caballo</button>
          </div>

          <div :if={@game.promotion_pending && @game.promotion_pending.player_id != @player_id} class="mc-check-message">
            Esperando promocion del rival
          </div>

          <div class="mc-actions">
            <button :if={@game.status == :ready} type="button" phx-click="start_game">{start_label(@game)}</button>
            <button :if={starting?(@game) and seated_in?(@game, @player_id)} type="button" phx-click="ready_to_start" disabled={ready_to_start_disabled?(@game, @player_id)}>
              {ready_to_start_label(@game, @player_id)}
            </button>
            <button type="button" phx-click="reset" disabled={reset_disabled?(@game, @player_id)}>
              {reset_label(@game, @player_id)}
            </button>
            <button type="button" phx-click="leave">
              {if seated_in?(@game, @player_id), do: "Liberar mi asiento", else: "Volver al lobby"}
            </button>
          </div>

          <div class="mc-play-area">
            <div class="mc-board-stack">
              <% top_elixir = top_elixir_color(@color) %>
              <% bottom_elixir = bottom_elixir_color(@color) %>
              <div class="mc-elixir-bottom">
                <div class={["mc-elixir-bottom-row", elixir_color_class(top_elixir)]}>
                  <span>{color_label(top_elixir)}</span>
                  <div class="mc-elixir-bottom-track">
                    <span style={elixir_width(@game, top_elixir)}></span>
                  </div>
                  <strong>{@game.elixir[top_elixir]}</strong>
                </div>
              </div>

              <div id={"mc-board-#{@game.id}"} class="mc-board" phx-hook="BoardDrag">
                <%= for {row, r} <- rows_for(assigns) do %>
                  <%= for {piece, c} <- cols_for(@color, row) do %>
                    <button class={square_class(@game, r, c, @selected, @valid_moves)} phx-click="move" phx-value-r={r} phx-value-c={c} data-r={r} data-c={c}>
                      <span class={piece_class(piece)}>{@symbols[piece]}</span>
                      <span :if={cooldown_for(@game, {r, c})} class="mc-cooldown-ring" style={cooldown_style(@game, {r, c})}>
                        <svg viewBox="0 0 26 26" aria-hidden="true">
                          <circle class="mc-cooldown-ring-track" cx="13" cy="13" r="10" pathLength="100" />
                          <circle class="mc-cooldown-ring-fill" cx="13" cy="13" r="10" pathLength="100" />
                        </svg>
                      </span>
                    </button>
                  <% end %>
                <% end %>
              </div>

              <div class="mc-elixir-bottom">
                <div class={["mc-elixir-bottom-row", elixir_color_class(bottom_elixir)]}>
                  <span>{color_label(bottom_elixir)}</span>
                  <div class="mc-elixir-bottom-track">
                    <span style={elixir_width(@game, bottom_elixir)}></span>
                  </div>
                  <strong>{@game.elixir[bottom_elixir]}</strong>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div class="mc-menu">
            <section class="mc-menu-hero">
              <div>
                <p class="mc-kicker">Ajedrez en tiempo real con elixir</p>
                <h2>Mana Chess</h2>
              </div>
              <div class="mc-menu-stats">
                <span>{@lobby |> lobby_count(:playing)} en juego</span>
                <span>{open_seats_count(@lobby)} asientos libres</span>
              </div>
            </section>

            <section class="mc-local-stats">
              <div>
                <strong>Tus stats</strong>
                <span>Guardadas en este navegador.</span>
              </div>
              <dl>
                <div>
                  <dt>Partidas</dt>
                  <dd data-stat="played">0</dd>
                </div>
                <div>
                  <dt>Victorias</dt>
                  <dd data-stat="wins">0</dd>
                </div>
                <div>
                  <dt>Derrotas</dt>
                  <dd data-stat="losses">0</dd>
                </div>
                <div>
                  <dt>Empates</dt>
                  <dd data-stat="draws">0</dd>
                </div>
              </dl>
              <button type="button" data-stats-reset>Reiniciar stats</button>
            </section>

            <section class="mc-offline">
              <div>
                <h2>Offline</h2>
                <span>Practica solo con BOT encendido por default.</span>
              </div>
              <div class="mc-mode-grid mc-mode-grid-offline">
                <button type="button" class="mc-mode" phx-click="start_practice">
                  <strong>Practica</strong>
                  <span>Prueba elixir, cooldown y BOT.</span>
                </button>
                <button type="button" class="mc-mode" phx-click="start_tutorial">
                  <strong>Tutorial rapido</strong>
                  <span>Aprende el modo en menos de un minuto.</span>
                </button>
              </div>
            </section>

            <div class="mc-lobby">
              <div class="mc-lobby-head">
                <h2>Salas online</h2>
                <button type="button" class="mc-online-quick" phx-click="sit_anywhere">
                  Online rapido
                </button>
              </div>

              <div :for={game <- @lobby} class="mc-lobby-game">
                <div>
                  <strong>{lobby_room_name(game.id)}</strong>
                  <div class="mc-lobby-meta">
                    <a href={~p"/game/#{game.id}"}>Observar</a>
                    <a href={~p"/game/#{game.id}"}>Link</a>
                    <button :if={clearable_room?(game)} type="button" phx-click="clear_room" phx-value-game={game.id}>Limpiar</button>
                    <span>{lobby_status(game.status)}</span>
                  </div>
                </div>
                <div class="mc-lobby-seats">
                  <button
                    type="button"
                    phx-click="sit"
                    phx-value-game={game.id}
                    phx-value-color="white"
                    disabled={!seat_open?(game, :white) && !seated_in?(game, @player_id)}
                  >
                    Blancas: {seat_label(game.players.white, @player_id)}
                  </button>
                  <button
                    type="button"
                    phx-click="sit"
                    phx-value-game={game.id}
                    phx-value-color="black"
                    disabled={!seat_open?(game, :black) && !seated_in?(game, @player_id)}
                  >
                    Negras: {seat_label(game.players.black, @player_id)}
                  </button>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </section>

      <aside class={["mc-panel", @game && "mc-panel-game"]}>
        <h2>Cola</h2>
        <ol>
          <li :for={action <- (@game && @game.queue) || []}>
            {color_label(action.color)}: {inspect(action.from)} -> {inspect(action.to)}
          </li>
        </ol>

        <h2>Bitacora</h2>
        <ul>
          <li :for={entry <- (@game && @game.log) || []}>{entry}</li>
        </ul>
      </aside>
    </main>
    """
  end
end
