defmodule ManaChessOnlineWeb.GameLive do
  use ManaChessOnlineWeb, :live_view

  alias ManaChessOnline.GameLobby
  alias ManaChessOnline.GameRules
  alias ManaChessOnlineWeb.GameText

  import ManaChessOnlineWeb.GameBrandComponents
  import ManaChessOnlineWeb.GameComponents
  import ManaChessOnlineWeb.GameMatchComponents
  import ManaChessOnlineWeb.GameSoundComponents

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
     |> assign(:page_title, "Mana Chess")
     |> assign(:player_id, player_id)
     |> assign(:game_id, view.game_id)
     |> assign(:color, view.color)
     |> assign(:game, view.game)
     |> assign(:lobby, view.lobby)
     |> assign(:symbols, @symbols)
     |> assign(:valid_moves, [])
     |> assign(:selected, nil)
     |> assign(:blocked_square, nil)
     |> assign(:local_alert, nil)
     |> assign(:chat_draft, "")
     |> assign(:chat_error, nil)
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
    square = {r, c}
    piece = GameRules.at(socket.assigns.game.board, r, c)
    piece_color = GameRules.color(piece)

    legal_moves =
      if piece_color in [:white, :black] do
        GameRules.legal_moves_for(socket.assigns.game.board, r, c, piece_color, socket.assigns.game.castling_rights)
      else
        []
      end

    selected =
      if selectable_square?(socket.assigns.game, socket.assigns.color, piece, piece_color, legal_moves, square) do
        square
      else
        nil
      end

    valid_moves = if selected, do: legal_moves, else: []

    local_alert = select_alert(socket.assigns.game, socket.assigns.color, piece, piece_color, selected, legal_moves, square)

    {:noreply,
     assign(socket,
       selected: selected,
       valid_moves: valid_moves,
       blocked_square: blocked_square_for(local_alert, square),
       local_alert: local_alert
     )}
  end

  def handle_event("move", %{"r" => r, "c" => c}, %{assigns: %{selected: nil}} = socket) do
    handle_event("select", %{"r" => r, "c" => c}, socket)
  end

  def handle_event("move", %{"r" => r, "c" => c}, socket) do
    to = {String.to_integer(r), String.to_integer(c)}
    blocked_square = if to in socket.assigns.valid_moves, do: nil, else: to

    GameLobby.enqueue(socket.assigns.player_id, socket.assigns.selected, to)

    {:noreply,
     socket
     |> refresh_assignment()
     |> assign(local_alert: nil, blocked_square: blocked_square)}
  end

  def handle_event("drag_move", %{"from_r" => from_r, "from_c" => from_c, "to_r" => to_r, "to_c" => to_c}, socket) do
    from = {String.to_integer(from_r), String.to_integer(from_c)}
    to = {String.to_integer(to_r), String.to_integer(to_c)}
    piece = GameRules.at(socket.assigns.game.board, elem(from, 0), elem(from, 1))
    piece_color = GameRules.color(piece)
    legal_moves = legal_moves_for(socket.assigns.game, piece_color, from)

    local_alert =
      if manual_control_allowed?(socket.assigns.game, socket.assigns.color, piece_color) do
        GameLobby.enqueue(socket.assigns.player_id, from, to)
        nil
      else
        select_alert(socket.assigns.game, socket.assigns.color, piece, piece_color, nil, [], from)
      end

    blocked_square =
      cond do
        not is_nil(local_alert) -> from
        to in legal_moves -> nil
        true -> to
      end

    {:noreply,
     socket
     |> refresh_assignment()
     |> assign(local_alert: local_alert, blocked_square: blocked_square)}
  end

  def handle_event("drag_invalid", %{"from_r" => from_r, "from_c" => from_c}, socket) do
    from = {String.to_integer(from_r), String.to_integer(from_c)}

    {:noreply,
     assign(socket,
       selected: nil,
       valid_moves: [],
       blocked_square: from,
       local_alert: GameText.friendly_alert("casilla invalida.")
     )}
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

  def handle_event("create_private", _params, socket) do
    view = GameLobby.create_private(socket.assigns.player_id)

    {:noreply, push_navigate(socket, to: ~p"/game/#{view.game_id}")}
  end

  def handle_event("chat_change", %{"message" => message}, socket) do
    {:noreply, assign(socket, chat_draft: String.slice(message || "", 0, 180), chat_error: nil)}
  end

  def handle_event("send_chat", %{"message" => message}, socket) do
    case GameLobby.send_chat(socket.assigns.player_id, socket.assigns.game_id, message) do
      :ok ->
        {:noreply, assign(socket, chat_draft: "", chat_error: nil)}

      {:error, :empty} ->
        {:noreply, assign(socket, chat_error: "Escribe un mensaje.")}

      {:error, _reason} ->
        {:noreply, assign(socket, chat_error: "No se pudo enviar.")}
    end
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
    |> assign(:blocked_square, nil)
    |> assign(:local_alert, nil)
    |> assign(:chat_error, nil)
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

  defp square_class(game, r, c, selected, valid_moves, blocked_square) do
    [
      "mc-square",
      rem(r + c, 2) == 0 && "mc-light",
      rem(r + c, 2) == 1 && "mc-dark",
      selected?(selected, {r, c}) && "mc-selected",
      {r, c} in valid_moves && "mc-valid",
      selected?(blocked_square, {r, c}) && "mc-blocked",
      in_check_square?(game, r, c) && "mc-check",
      cooldown_active?(game, {r, c}) && "mc-cooldown"
    ]
  end

  defp blocked_square_for(nil, _square), do: nil
  defp blocked_square_for(_alert, square), do: square

  defp legal_moves_data(game, player_color, piece, r, c) do
    piece_color = GameRules.color(piece)
    square = {r, c}

    legal_moves = legal_moves_for(game, piece_color, square)

    if selectable_square?(game, player_color, piece, piece_color, legal_moves, square) do
      legal_moves
      |> Enum.map(fn {to_r, to_c} -> "#{to_r},#{to_c}" end)
      |> Enum.join(" ")
    else
      ""
    end
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

  defp match_phase(%{status: :waiting, private?: true}), do: %{title: "Privado por link", detail: "Comparte el enlace y espera a que el rival tome asiento.", tone: :waiting}
  defp match_phase(%{status: :waiting}), do: %{title: "Esperando rival", detail: "Comparte el link o toma el asiento libre.", tone: :waiting}
  defp match_phase(%{status: :ready}), do: %{title: "Listos para empezar", detail: "Cualquiera puede iniciar la cuenta regresiva.", tone: :ready}
  defp match_phase(%{status: {:starting, _starts_at}, countdown_seconds: seconds}), do: %{title: "Inicia en #{seconds}", detail: "Ambos pueden marcar listo para saltar la espera.", tone: :starting}
  defp match_phase(%{status: :promotion}), do: %{title: "Promocion pendiente", detail: "Elige pieza para continuar.", tone: :alert}
  defp match_phase(%{status: {:checkmate, winner, _loser}}), do: %{title: "Jaque mate", detail: "Ganan #{color_label(winner)}.", tone: :final}
  defp match_phase(%{status: {:winner, winner}}), do: %{title: "Partida terminada", detail: "Ganan #{color_label(winner)}.", tone: :final}
  defp match_phase(%{status: :draw}), do: %{title: "Empate", detail: "La partida termino sin ganador.", tone: :final}

  defp match_phase(%{status: :playing, first_move_pending: :white}) do
    %{title: "Blancas abren", detail: "Elixir pausado hasta el primer movimiento blanco.", tone: :ready}
  end

  defp match_phase(%{practice?: true, bot_enabled?: true, queue: []}) do
    %{title: "Tiempo real contra BOT", detail: "Mueve cuando tengas elixir; el BOT controla Negras.", tone: :bot}
  end

  defp match_phase(%{practice?: true, bot_enabled?: true}) do
    %{title: "BOT pensando", detail: "La cola esta procesando una accion.", tone: :bot}
  end

  defp match_phase(%{status: :playing}) do
    %{title: "Tiempo real", detail: "No hay turnos: mueve cuando tengas elixir y cooldown libre.", tone: :playing}
  end

  defp match_phase(_game), do: %{title: "Mana Chess", detail: "Elixir, cooldown y movimientos en tiempo real.", tone: :ready}

  defp match_phase_class(%{tone: tone}), do: "mc-match-status-#{tone}"

  defp player_role(%{practice?: true}, _color), do: "Practica"
  defp player_role(_game, :white), do: "Tu lado: Blancas"
  defp player_role(_game, :black), do: "Tu lado: Negras"
  defp player_role(_game, _color), do: "Modo espectador"

  defp player_role_hint(%{practice?: true, bot_enabled?: true}, _color), do: "BOT ON"
  defp player_role_hint(%{practice?: true}, _color), do: "BOT OFF"
  defp player_role_hint(_game, color) when color in [:white, :black], do: "Sentado"
  defp player_role_hint(_game, _color), do: "Observando"

  defp invite_title(%{private?: true} = game, player_id) do
    if private_link_guest?(game, player_id), do: "Llegaste por link", else: "Invitacion privada"
  end

  defp invite_title(_game, _player_id), do: "Link de sala"

  defp invite_hint(%{private?: true} = game, player_id) do
    if private_link_guest?(game, player_id) do
      "Toma un asiento libre para jugar, o quedate mirando."
    else
      "Comparte este enlace; el rival entra y toma el asiento libre."
    end
  end

  defp invite_hint(_game, _player_id), do: "Rival o espectador entra aqui."

  defp invite_copy_label(%{private?: true} = game, player_id) do
    if private_link_guest?(game, player_id), do: "Copiar link", else: "Copiar invitacion"
  end

  defp invite_copy_label(_game, _player_id), do: "Copiar link"

  defp invite_badge(%{private?: true} = game, player_id) do
    if private_link_guest?(game, player_id), do: "Invitado", else: "Privado"
  end

  defp invite_badge(_game, _player_id), do: nil

  defp waiting_seat_hint(%{private?: true} = game, player_id) do
    if private_link_guest?(game, player_id) do
      "Entraste por invitacion: elige un asiento libre para jugar."
    else
      "Privado listo: comparte el link y el rival puede tomar el asiento libre."
    end
  end

  defp waiting_seat_hint(_game, _player_id), do: "Blancas no puede iniciar hasta que Negras se siente. Para jugar solo usa Modo practica."

  defp seat_cta_label(%{private?: true}, :white), do: "Tomar Blancas"
  defp seat_cta_label(%{private?: true}, :black), do: "Tomar Negras"
  defp seat_cta_label(_game, :white), do: "Sentarme como Blancas"
  defp seat_cta_label(_game, :black), do: "Sentarme como Negras"

  defp private_link_guest?(%{private?: true, status: status} = game, player_id) when status in [:waiting, :ready] do
    observing?(game, player_id)
  end

  defp private_link_guest?(_game, _player_id), do: false

  defp start_label(%{practice?: true}), do: "Empezar practica"
  defp start_label(_game), do: "Empezar partida"

  defp seated_in?(game, player_id), do: game.players.white == player_id or game.players.black == player_id
  defp observing?(nil, _player_id), do: false
  defp observing?(game, player_id), do: not game.practice? and not seated_in?(game, player_id)
  defp seat_open?(game, color), do: is_nil(game.players[color])
  defp recovered_session?(%{"game_id" => _game_id}, %{game: %{private?: true, status: :waiting}}), do: false
  defp recovered_session?(%{"game_id" => _game_id}, %{game: game, color: color}) when not is_nil(game) and color in [:white, :black, :practice], do: true
  defp recovered_session?(params, %{game: game, color: color}) when params == %{} and not is_nil(game) and color in [:white, :black, :practice], do: true
  defp recovered_session?(_params, _view), do: false
  defp show_reconnect_banner?(%{private?: true, status: :waiting}), do: false
  defp show_reconnect_banner?(_game), do: true
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

  defp feedback_alert_kind(nil, _local_alert), do: "alert"

  defp feedback_alert_kind(game, local_alert) do
    cond do
      not is_nil(local_alert) -> "local"
      not is_nil(check_message(game)) -> "check"
      not is_nil(reset_message(game)) -> "reset"
      not is_nil(alert_message(game)) -> "alert"
      true -> "alert"
    end
  end

  defp stats_winner_outcome(%{practice?: true}, :white, _player_color), do: "win"
  defp stats_winner_outcome(%{practice?: true}, :black, _player_color), do: "loss"
  defp stats_winner_outcome(_game, winner, winner), do: "win"
  defp stats_winner_outcome(_game, _winner, player_color) when player_color in [:white, :black], do: "loss"
  defp stats_winner_outcome(_game, _winner, _player_color), do: nil

  defp check_message(nil), do: nil
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

  defp legal_moves_for(game, piece_color, {r, c}) when piece_color in [:white, :black] do
    GameRules.legal_moves_for(game.board, r, c, piece_color, game.castling_rights)
  end

  defp legal_moves_for(_game, _piece_color, _square), do: []

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
        latest |> String.replace_prefix("Movimiento rechazado: ", "") |> GameText.friendly_alert()

      String.starts_with?(latest, "Movimiento descartado: ") ->
        latest |> String.replace_prefix("Movimiento descartado: ", "") |> GameText.friendly_alert()

      String.starts_with?(latest, "Sin elixir") ->
        latest

      true ->
        nil
    end
  end

  defp alert_message(_game), do: nil
  defp visible_alert(game, local_alert), do: local_alert || alert_message(game)

  defp reset_message(nil), do: nil
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

  defp selectable_square?(game, player_color, piece, piece_color, legal_moves, square) do
    piece != "." and manual_control_allowed?(game, player_color, piece_color) and
      can_move_now?(game, piece_color) and not cooldown_active?(game, square) and
      can_afford_piece?(game, piece, piece_color) and legal_moves != []
  end

  defp select_alert(_game, _player_color, _piece, _piece_color, {_r, _c}, _legal_moves, _square), do: nil
  defp select_alert(_game, _player_color, ".", _piece_color, nil, _legal_moves, _square), do: nil
  defp select_alert(%{status: status}, _player_color, _piece, _piece_color, nil, _legal_moves, _square) when status not in [:playing], do: "La partida todavia no esta jugando."

  defp select_alert(game, player_color, piece, piece_color, nil, legal_moves, square) when not is_nil(piece_color) do
    cond do
      not can_move_now?(game, piece_color) -> "Blancas abren: mueve una pieza blanca primero."
      game.practice? and game.bot_enabled? and piece_color == :black -> "El BOT controla Negras."
      not controls_color?(player_color, piece_color) -> spectator_or_control_alert(player_color)
      cooldown_active?(game, square) -> cooldown_alert(game, square)
      not can_afford_piece?(game, piece, piece_color) -> elixir_alert(game, piece, piece_color)
      legal_moves == [] -> "Esa pieza no tiene destinos legales ahora."
      true -> "No puedes mover esa pieza ahora."
    end
  end

  defp select_alert(_game, _player_color, _piece, _piece_color, nil, _legal_moves, _square), do: "No puedes mover esa pieza ahora."

  defp spectator_or_control_alert(nil), do: "Estas observando; toma un asiento para mover."
  defp spectator_or_control_alert(_player_color), do: "Esa pieza no es tuya; elige una de tu lado."

  defp can_afford_piece?(game, piece, color), do: Map.get(game.elixir, color, 0) >= piece_cost_for_ui(game, piece)

  defp elixir_alert(game, piece, color) do
    "Falta elixir para esa pieza: #{short_number(Map.get(game.elixir, color, 0))}/#{short_number(piece_cost_for_ui(game, piece))}."
  end

  defp cooldown_alert(game, square) do
    case cooldown_for(game, square) do
      nil -> "Esa pieza esta en cooldown."
      %{remaining_ms: remaining_ms} -> "Cooldown activo: espera #{ceil(remaining_ms / 1000)}s."
    end
  end

  defp piece_cost_for_ui(game, piece) do
    game.settings.costs
    |> Map.get(piece_type(piece), GameRules.piece_cost(piece))
  end

  defp piece_type(piece) do
    case String.downcase(piece) do
      "p" -> :pawn
      "n" -> :knight
      "b" -> :bishop
      "r" -> :rook
      "q" -> :queen
      "k" -> :king
      _ -> :pawn
    end
  end

  defp short_number(number) when is_integer(number), do: Integer.to_string(number)

  defp short_number(number) when is_float(number) do
    number
    |> Float.round(2)
    |> :erlang.float_to_binary(decimals: 2)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp short_number(number), do: to_string(number)

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
      {sound_state_attrs(
        @game,
        check_message(@game),
        visible_alert(@game, @local_alert),
        reset_message(@game)
      )}
    >
      <section class="mc-game">
        <div class="mc-header">
          <.brand_lockup title={if @game_id, do: "Partida", else: "Lobby"} detail={@game_id} />
          <div class="mc-badge">
            <.sound_control />
          </div>
        </div>

        <%= if @game do %>
          <div :if={@game.practice?} class="mc-practice-banner">
            <strong>Modo practica</strong>
            <span>Controlas ambos lados para probar reglas, elixir y cooldowns.</span>
            <div class="mc-bot-control">
              <span>BOT</span>
              <button class={["mc-bot-toggle", @game.bot_enabled? && "mc-bot-toggle-on"]} type="button" phx-click="toggle_practice_bot" data-sound-action="tap">
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

          <div :if={@reconnected? && show_reconnect_banner?(@game)} class="mc-reconnect-banner">
            <strong>Reconectado</strong>
            <span>Recuperaste tu asiento como {color_label(@color)}.</span>
          </div>

          <% phase = match_phase(@game) %>
          <.match_status
            phase={phase}
            phase_class={match_phase_class(phase)}
            role={player_role(@game, @color)}
            hint={player_role_hint(@game, @color)}
          />

          <div :if={!@game.practice?} class="mc-seats">
            <div class={["mc-seat", @color == :white && "mc-seat-current"]}>
              <strong>Blancas</strong>
              <span>{seat_label(@game.players.white, @player_id)}</span>
            </div>
            <div class={["mc-seat", @color == :black && "mc-seat-current"]}>
              <strong>Negras</strong>
              <span>{seat_label(@game.players.black, @player_id)}</span>
            </div>
            <p :if={@game.status == :waiting}>{waiting_seat_hint(@game, @player_id)}</p>
            <% invite_path = ~p"/game/#{@game.id}" %>
            <.invite_strip
              game={@game}
              invite_path={invite_path}
              title={invite_title(@game, @player_id)}
              hint={invite_hint(@game, @player_id)}
              copy_label={invite_copy_label(@game, @player_id)}
              badge={invite_badge(@game, @player_id)}
              arrived_by_link?={private_link_guest?(@game, @player_id)}
            />
            <div class="mc-seat-actions">
              <button
                :if={!seated_in?(@game, @player_id) && seat_open?(@game, :white)}
                type="button"
                phx-click="sit"
                phx-value-game={@game.id}
                phx-value-color="white"
                data-sound-action="mode"
              >
                {seat_cta_label(@game, :white)}
              </button>
              <button
                :if={!seated_in?(@game, @player_id) && seat_open?(@game, :black)}
                type="button"
                phx-click="sit"
                phx-value-game={@game.id}
                phx-value-color="black"
                data-sound-action="mode"
              >
                {seat_cta_label(@game, :black)}
              </button>
            </div>
          </div>

          <.match_feedback
            check_message={check_message(@game)}
            starting?={starting?(@game)}
            countdown_seconds={@game.countdown_seconds}
            first_move_message={first_move_message(@game)}
            alert_message={visible_alert(@game, @local_alert)}
            alert_kind={feedback_alert_kind(@game, @local_alert)}
            reset_message={reset_message(@game)}
          />

          <div :if={final_result(@game, @color)} class={["mc-final-panel", final_panel_class(final_result(@game, @color))]}>
            <% result = final_result(@game, @color) %>
            <div>
              <strong>{result.title}</strong>
              <span>{result.detail}</span>
            </div>
            <button type="button" phx-click="reset" disabled={reset_disabled?(@game, @player_id)} data-sound-action="reset">
              {if @game.practice?, do: "Jugar otra vez", else: "Pedir revancha"}
            </button>
          </div>

          <.promotion_panel pending={@game.promotion_pending} player_id={@player_id} />

          <div class="mc-actions">
            <button :if={@game.status == :ready} class="mc-action-primary" type="button" phx-click="start_game" data-sound-action="mode">{start_label(@game)}</button>
            <button :if={starting?(@game) and seated_in?(@game, @player_id)} class="mc-action-primary" type="button" phx-click="ready_to_start" disabled={ready_to_start_disabled?(@game, @player_id)} data-sound-action="mode">
              {ready_to_start_label(@game, @player_id)}
            </button>
            <button class="mc-action-secondary" type="button" phx-click="reset" disabled={reset_disabled?(@game, @player_id)} data-sound-action="reset">
              {reset_label(@game, @player_id)}
            </button>
            <button class="mc-action-quiet" type="button" phx-click="leave" data-sound-action="tap">
              {if seated_in?(@game, @player_id), do: "Liberar mi asiento", else: "Volver al lobby"}
            </button>
          </div>

          <div class="mc-play-area">
            <div class="mc-skin-strip" aria-label="Skins de tablero">
              <span>Tablero</span>
              <button type="button" data-board-skin-choice="classic" data-sound-action="skin" title="Tablero clasico blanco y negro" aria-label="Tablero clasico blanco y negro" aria-pressed="false">
                <i class="mc-skin-dot mc-skin-dot-classic"></i>
                Clasico
              </button>
              <button type="button" data-board-skin-choice="gilded" data-sound-action="skin" title="Tablero Dorado" aria-label="Tablero Dorado" aria-pressed="false">
                <i class="mc-skin-dot mc-skin-dot-gilded"></i>
                Dorado
              </button>
              <button type="button" class="mc-skin-locked" data-board-skin-choice="arcane" data-cosmetic-premium="board:arcane" data-sound-action="skin" title="Probar y desbloquear Arcano localmente" aria-label="Probar y desbloquear Arcano localmente" aria-disabled="false" aria-pressed="false">
                <i class="mc-skin-dot mc-skin-dot-arcane"></i>
                Arcano
                <small data-cosmetic-status data-cosmetic-state="premium">Premium proximamente</small>
              </button>
              <button type="button" class="mc-skin-locked" data-board-skin-choice="custom" data-cosmetic-premium="board:custom" data-sound-action="skin" title="Probar y desbloquear paleta localmente" aria-label="Probar y desbloquear paleta localmente" aria-disabled="false" aria-pressed="false">
                <i class="mc-skin-dot mc-skin-dot-custom"></i>
                Paleta
                <small data-cosmetic-status data-cosmetic-state="premium">Premium proximamente</small>
              </button>
            </div>
            <div class="mc-skin-strip mc-piece-strip" aria-label="Skins de piezas">
              <span>Piezas</span>
              <button type="button" data-piece-skin-choice="classic" data-sound-action="skin" title="Piezas clasicas" aria-label="Piezas clasicas" aria-pressed="false">
                <i class="mc-piece-dot mc-piece-dot-classic"></i>
                Clasicas
              </button>
              <button type="button" data-piece-skin-choice="runes" data-sound-action="skin" title="Piezas Arcano" aria-label="Piezas Arcano" aria-pressed="false">
                <i class="mc-piece-dot mc-piece-dot-runes"></i>
                Arcano
              </button>
              <button type="button" class="mc-skin-locked" data-piece-skin-choice="crystal" data-cosmetic-premium="piece:crystal" data-sound-action="skin" title="Probar y desbloquear piezas localmente" aria-label="Probar y desbloquear piezas localmente" aria-disabled="false" aria-pressed="false">
                <i class="mc-piece-dot mc-piece-dot-crystal"></i>
                Premium
                <small data-cosmetic-status data-cosmetic-state="premium">Premium proximamente</small>
              </button>
              <button type="button" class="mc-skin-locked" data-piece-skin-choice="custom" data-cosmetic-premium="piece:custom" data-sound-action="skin" title="Probar y desbloquear paleta localmente" aria-label="Probar y desbloquear paleta localmente" aria-disabled="false" aria-pressed="false">
                <i class="mc-piece-dot mc-piece-dot-custom"></i>
                Paleta
                <small data-cosmetic-status data-cosmetic-state="premium">Premium proximamente</small>
              </button>
            </div>
            <div class="mc-board-stack" data-board-skin-target>
              <% top_elixir = top_elixir_color(@color) %>
              <% bottom_elixir = bottom_elixir_color(@color) %>
              <div class="mc-elixir-bottom">
                <div class={["mc-elixir-bottom-row", elixir_color_class(top_elixir)]}>
                  <span>{color_label(top_elixir)}</span>
                  <div class="mc-elixir-bottom-track">
                    <span style={elixir_width(@game, top_elixir)}></span>
                  </div>
                  <strong>{@game.elixir[top_elixir]}/{@game.settings.max_elixir}</strong>
                </div>
              </div>

              <div id={"mc-board-#{@game.id}"} class="mc-board" phx-hook="BoardDrag">
                <%= for {row, r} <- rows_for(assigns) do %>
                  <%= for {piece, c} <- cols_for(@color, row) do %>
                    <button
                      class={square_class(@game, r, c, @selected, @valid_moves, @blocked_square)}
                      phx-click="move"
                      phx-value-r={r}
                      phx-value-c={c}
                      data-r={r}
                      data-c={c}
                      data-legal-moves={legal_moves_data(@game, @color, piece, r, c)}
                    >
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
                  <strong>{@game.elixir[bottom_elixir]}/{@game.settings.max_elixir}</strong>
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
              <button type="button" data-stats-reset data-sound-action="reset">Reiniciar stats</button>
            </section>

            <.cosmetic_shop symbols={@symbols} class="mc-skins mc-skins-inline" aria_label="Tienda cosmetica" />

            <section class="mc-offline">
              <div>
                <h2>Offline</h2>
                <span>Practica solo con BOT encendido por default.</span>
              </div>
              <div class="mc-mode-grid mc-mode-grid-offline">
                <button type="button" class="mc-mode" phx-click="start_practice" data-sound-action="mode">
                  <strong>Practica</strong>
                  <span>Prueba elixir, cooldown y BOT.</span>
                </button>
                <button type="button" class="mc-mode" phx-click="start_tutorial" data-sound-action="mode">
                  <strong>Tutorial rapido</strong>
                  <span>Aprende el modo en menos de un minuto.</span>
                </button>
              </div>
            </section>

            <div class="mc-lobby">
              <div class="mc-lobby-head">
                <h2>Salas online</h2>
                <div class="mc-lobby-actions">
                  <button type="button" class="mc-private-quick" phx-click="create_private" title="Crear sala privada por link" data-sound-action="private">
                    <strong>Privado por link</strong>
                    <small>Crear sala</small>
                  </button>
                  <button type="button" class="mc-online-quick" phx-click="sit_anywhere" data-sound-action="mode">
                    Online rapido
                  </button>
                </div>
              </div>

              <div :for={game <- @lobby} class="mc-lobby-game">
                <div>
                  <div class="mc-lobby-title">
                    <strong>{lobby_room_name(game.id)}</strong>
                  </div>
                  <div class="mc-lobby-meta">
                    <a href={~p"/game/#{game.id}"}>Observar</a>
                    <button type="button" title="Copiar link de sala" data-copy-invite={~p"/game/#{game.id}"}>Link</button>
                    <button :if={clearable_room?(game)} type="button" phx-click="clear_room" phx-value-game={game.id} data-sound-action="reset">Limpiar</button>
                    <span>{lobby_status(game.status)}</span>
                  </div>
                </div>
                <div class="mc-lobby-seats">
                  <button
                    type="button"
                    phx-click="sit"
                    phx-value-game={game.id}
                    phx-value-color="white"
                    data-sound-action="mode"
                    disabled={!seat_open?(game, :white) && !seated_in?(game, @player_id)}
                  >
                    Blancas: {seat_label(game.players.white, @player_id)}
                  </button>
                  <button
                    type="button"
                    phx-click="sit"
                    phx-value-game={game.id}
                    phx-value-color="black"
                    data-sound-action="mode"
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

      <.cosmetic_shop :if={!@game} symbols={@symbols} class="mc-skins mc-skins-rail" aria_label="Tienda cosmetica lateral" />

      <.side_panel game={@game} player_id={@player_id} chat_draft={@chat_draft} chat_error={@chat_error} />
    </main>
    """
  end
end
