defmodule ManaChessOnline.GameLobby do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.GameRules

  @max_games 4
  @tick_ms 250
  @countdown_ms 5_000
  @bot_search_depth 4
  @bot_branch_limit 8
  @bot_root_branch_limit 12
  @bot_move_seconds 1.2
  @mate_score 100_000
  @piece_values %{
    pawn: 100,
    knight: 320,
    bishop: 330,
    rook: 500,
    queen: 900,
    king: 20_000
  }
  @settings_file "mana_chess_settings.json"
  @settings_version 2
  @default_settings %{
    settings_version: @settings_version,
    max_elixir: 10.0,
    initial_elixir: 5.0,
    regen_per_second: 1.0,
    capture_refund_percent: 40,
    cooldown_enabled: true,
    cooldown_seconds: 1.0,
    bot_move_seconds: @bot_move_seconds,
    costs: %{
      pawn: 1.0,
      knight: 3.0,
      bishop: 3.0,
      rook: 4.0,
      queen: 6.0,
      king: 3.0
    }
  }

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def join(player_id), do: GenServer.call(__MODULE__, {:join, player_id})
  def sit(player_id, game_id, color), do: GenServer.call(__MODULE__, {:sit, player_id, game_id, color})
  def sit_anywhere(player_id), do: GenServer.call(__MODULE__, {:sit_anywhere, player_id})
  def create_private(player_id), do: GenServer.call(__MODULE__, {:create_private, player_id})
  def watch(player_id, game_id), do: GenServer.call(__MODULE__, {:watch, player_id, game_id})
  def snapshot(game_id), do: GenServer.call(__MODULE__, {:snapshot, game_id})
  def lobby, do: GenServer.call(__MODULE__, :lobby)
  def global_settings, do: GenServer.call(__MODULE__, :global_settings)
  def update_global_settings(params), do: GenServer.call(__MODULE__, {:update_global_settings, params})
  def apply_global_settings_to_practice(player_id), do: GenServer.call(__MODULE__, {:apply_global_settings_to_practice, player_id})
  def leave(player_id), do: GenServer.call(__MODULE__, {:leave, player_id})
  def clear_room(game_id), do: GenServer.call(__MODULE__, {:clear_room, game_id})
  def reset(player_id), do: GenServer.call(__MODULE__, {:reset, player_id})
  def start_game(player_id), do: GenServer.call(__MODULE__, {:start_game, player_id})
  def ready_to_start(player_id), do: GenServer.call(__MODULE__, {:ready_to_start, player_id})
  def start_practice(player_id), do: GenServer.call(__MODULE__, {:start_practice, player_id})
  def toggle_practice_bot(player_id), do: GenServer.call(__MODULE__, {:toggle_practice_bot, player_id})
  def update_settings(player_id, params), do: GenServer.call(__MODULE__, {:update_settings, player_id, params})
  def promote(player_id, choice), do: GenServer.call(__MODULE__, {:promote, player_id, choice})
  def enqueue(player_id, from, to), do: GenServer.call(__MODULE__, {:enqueue, player_id, from, to})
  def send_chat(player_id, game_id, message), do: GenServer.call(__MODULE__, {:send_chat, player_id, game_id, message})

  @impl true
  def init(:ok) do
    Process.send_after(self(), :tick, @tick_ms)
    settings = load_global_settings()

    {:ok,
     %{
       global_settings: settings,
       games: Map.new(1..@max_games, fn n -> {"game_#{n}", new_game("game_#{n}", settings)} end),
       players: %{}
     }}
  end

  @impl true
  def handle_call({:join, player_id}, _from, state) do
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:sit, player_id, game_id, color}, _from, state) do
    state =
      state
      |> remove_player(player_id)
      |> assign_player(player_id, game_id, color)

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:sit_anywhere, player_id}, _from, state) do
    state =
      case find_slot(state.games) do
        {game_id, color} ->
          state
          |> remove_player(player_id)
          |> assign_player(player_id, game_id, color)

        nil ->
          state
      end

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:create_private, player_id}, _from, state) do
    game_id = unique_private_game_id(state.games)

    state =
      state
      |> remove_player(player_id)
      |> put_in([:games, game_id], private_game(game_id, state.global_settings))
      |> assign_player(player_id, game_id, :white)

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:watch, player_id, game_id}, _from, state) do
    state = ensure_private_game(state, game_id)

    {:reply, player_view(state, player_id, game_id), state}
  end

  def handle_call(:lobby, _from, state) do
    {:reply, public_lobby(state), state}
  end

  def handle_call(:global_settings, _from, state) do
    {:reply, state.global_settings, state}
  end

  def handle_call({:update_global_settings, params}, _from, state) do
    settings = sanitize_settings(params, state.global_settings)
    persist_global_settings(settings)

    state =
      state
      |> Map.put(:global_settings, settings)
      |> update_in([:games], fn games ->
        Map.new(games, fn {game_id, game} ->
          if empty_waiting_game?(game) do
            {game_id, %{game | settings: settings, elixir: full_elixir(settings), cooldowns: %{}}}
          else
            {game_id, game}
          end
        end)
      end)

    broadcast_lobby(state)
    {:reply, settings, state}
  end

  def handle_call({:apply_global_settings_to_practice, player_id}, _from, state) do
    case state.players[player_id] do
      %{game_id: game_id, color: :practice} ->
        state =
          update_in(state.games[game_id], fn game ->
            %{
              game
              | settings: state.global_settings,
                elixir: clamp_elixir(game.elixir, state.global_settings),
                cooldowns: %{},
                log: ["Configuracion admin aplicada a la practica." | game.log]
            }
          end)

        Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, topic(game_id), {:game_update, public_game(state.games[game_id])})
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :no_practice}, state}
    end
  end

  def handle_call({:snapshot, game_id}, _from, state) do
    {:reply, public_game(state.games[game_id]), state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    state = remove_player(state, player_id)
    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:clear_room, game_id}, _from, state) do
    state =
      case state.games[game_id] do
        %{practice?: false} = game when game.status in [:waiting, :ready] ->
          player_ids = seated_players(game)

          state
          |> update_in([:players], fn players -> Map.drop(players, player_ids) end)
          |> put_in([:games, game_id], new_game(game_id, game.settings))

        _ ->
          state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:reset, player_id}, _from, state) do
    state =
      with %{game_id: game_id, color: color} when is_binary(game_id) <- state.players[player_id],
           game when not is_nil(game) <- state.games[game_id] do
        if reset_ready?(game, player_id) do
          reset_game(state, game_id, game)
        else
          put_in(state.games[game_id], %{
            game
            | reset_requests: MapSet.put(game.reset_requests, player_id),
              log: ["#{label(color)} pidio reiniciar la partida." | game.log]
          })
        end
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_game, player_id}, _from, state) do
    state =
      with %{game_id: game_id} when is_binary(game_id) <- state.players[player_id],
           %{status: :ready} = game <- state.games[game_id] do
        starts_at = System.monotonic_time(:millisecond) + @countdown_ms

        put_in(state.games[game_id], %{
          game
          | status: {:starting, starts_at},
            queue: [],
            reset_requests: MapSet.new(),
            start_requests: MapSet.new([player_id]),
            log: ["Cuenta regresiva iniciada." | game.log]
        })
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:ready_to_start, player_id}, _from, state) do
    state =
      with %{game_id: game_id} when is_binary(game_id) <- state.players[player_id],
           %{status: {:starting, _starts_at}} = game <- state.games[game_id],
           true <- player_id in seated_players(game) do
        game =
          game
          |> update_in([:start_requests], &MapSet.put(&1, player_id))
          |> maybe_start_when_everyone_ready()

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_practice, player_id}, _from, state) do
    game_id = practice_game_id(player_id)

    state =
      state
      |> remove_player(player_id)
      |> put_in([:games, game_id], practice_game(game_id, player_id, state.global_settings))
      |> put_in([:players, player_id], %{game_id: game_id, color: :practice})

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:toggle_practice_bot, player_id}, _from, state) do
    state =
      with %{game_id: game_id, color: :practice} <- state.players[player_id],
           %{practice?: true} = game <- state.games[game_id] do
        enabled? = not game.bot_enabled?

        game = %{
          game
          | bot_enabled?: enabled?,
            bot_ready_at: if(enabled?, do: now_ms() + bot_move_ms(game.settings), else: nil),
            log: [bot_toggle_message(enabled?) | game.log]
        }

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:update_settings, player_id, params}, _from, state) do
    state =
      with %{game_id: game_id, color: color} when color in [:white, :practice] <- state.players[player_id],
           game when game.practice? or game.status in [:waiting, :ready] <- state.games[game_id] do
        settings = sanitize_settings(params, game.settings)

        put_in(state.games[game_id], %{
          game
          | settings: settings,
            elixir: full_elixir(settings),
            cooldowns: %{},
            log: ["Blancas ajustaron la configuracion." | game.log]
        })
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:promote, player_id, choice}, _from, state) do
    state =
      with %{game_id: game_id, color: player_color} <- state.players[player_id],
           game when not is_nil(game) <- state.games[game_id],
           %{player_id: ^player_id, color: color, at: square} <- game.promotion_pending,
           true <- controls_color?(player_color, color) do
        board = GameRules.promote(game.board, square, promotion_choice(choice, color), color)
        status = terminal_status(board, game.castling_rights) || :playing

        put_in(state.games[game_id], %{
          game
          | board: board,
            status: status,
            promotion_pending: nil,
            log: ["#{label(color)} promociono peon." | game.log]
        })
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:enqueue, player_id, from, to}, _from, state) do
    {state, game_id} = enqueue_move(state, player_id, from, to)

    if game_id do
      Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, topic(game_id), {:game_update, public_game(state.games[game_id])})
      broadcast_lobby(state)
    end

    {:reply, :ok, state}
  end

  def handle_call({:send_chat, player_id, game_id, message}, _from, state) do
    with {:ok, text} <- sanitize_chat_message(message),
         %{id: ^game_id} = game <- state.games[game_id] do
      entry = %{
        id: System.unique_integer([:positive, :monotonic]),
        player_id: player_id,
        role: chat_role(game, player_id),
        text: text
      }

      state =
        update_in(state.games[game_id], fn game ->
          chat =
            [entry | Map.get(game, :chat, [])]
            |> Enum.take(24)

          Map.put(game, :chat, chat)
        end)

      Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, topic(game_id), {:game_update, public_game(state.games[game_id])})
      {:reply, :ok, state}
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}

      _ ->
        {:reply, {:error, :no_game}, state}
    end
  end

  defp enqueue_move(state, player_id, from, to) do
    with %{game_id: game_id, color: player_color} <- state.players[player_id],
         game when not is_nil(game) <- state.games[game_id] do
      cond do
        not valid_square?(from) or not valid_square?(to) ->
          reject_move(state, game_id, "Movimiento rechazado: casilla invalida.")

        game.status != :playing ->
          reject_move(state, game_id, "Movimiento rechazado: la partida no esta jugando.")

        not is_nil(game.promotion_pending) ->
          reject_move(state, game_id, "Movimiento rechazado: hay una promocion pendiente.")

        true ->
          enqueue_valid_move(state, game_id, game, player_id, player_color, from, to)
      end
    else
      _ -> {state, nil}
    end
  end

  defp enqueue_valid_move(state, game_id, game, player_id, player_color, from, to) do
    piece = GameRules.at(game.board, elem(from, 0), elem(from, 1))
    color = GameRules.color(piece)

    cond do
        piece == "." ->
          reject_move(state, game_id, "Movimiento rechazado: no hay pieza en origen #{inspect(from)}.")

        color not in [:white, :black] ->
          reject_move(state, game_id, "Movimiento rechazado: pieza sin color.")

        bot_controls_black?(game, color) ->
          reject_move(state, game_id, "Movimiento rechazado: BOT controla Negras.")

        not controls_color?(player_color, color) ->
          reject_move(state, game_id, "Movimiento rechazado: no controlas #{label(color)}.")

        not first_move_allowed?(game, color) ->
          reject_move(state, game_id, "Movimiento rechazado: Blancas deben abrir.")

        to not in GameRules.legal_moves_for(game.board, elem(from, 0), elem(from, 1), color, game.castling_rights) ->
          reject_move(state, game_id, "Movimiento rechazado: #{inspect(from)} -> #{inspect(to)} no es legal.")

        true ->
          action = %{player_id: player_id, color: color, from: from, to: to}

          game =
            %{game | queue: game.queue ++ [action]}
            |> process_next_action()
            |> refresh_terminal_status()

          {put_in(state.games[game_id], game), game_id}
    end
  end

  defp reject_move(state, game_id, message) do
    state = update_in(state.games[game_id].log, &[message | &1])
    {state, game_id}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)

    state =
      update_in(state.games, fn games ->
        Map.new(games, fn {game_id, game} ->
          game =
            game
            |> clear_expired_cooldowns()
            |> regen_elixir()
            |> maybe_finish_countdown()
            |> maybe_enqueue_bot_move()
            |> process_next_action()
            |> refresh_terminal_status()

          Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, topic(game_id), {:game_update, public_game(game)})
          Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, lobby_topic(), {:lobby_update, public_lobby(%{games: games, players: state.players})})
          {game_id, game}
        end)
      end)

    {:noreply, state}
  end

  def topic(game_id), do: "game:" <> game_id
  def lobby_topic, do: "lobby"

  defp assign_player(state, player_id, game_id, color) do
    case state.games[game_id] do
      %{players: players} when color in [:white, :black] ->
        if is_nil(players[color]) do
          state
          |> put_in([:players, player_id], %{game_id: game_id, color: color})
          |> put_in([:games, game_id, :players, color], player_id)
          |> update_in([:games, game_id], &refresh_status/1)
        else
          state
        end

      _ ->
        state
    end
  end

  defp remove_player(state, player_id) do
    case state.players[player_id] do
      %{game_id: game_id, color: color} when is_binary(game_id) ->
        case state.games[game_id] do
          %{practice?: true} ->
            state
            |> update_in([:players], &Map.delete(&1, player_id))
            |> update_in([:games], &Map.delete(&1, game_id))

          _game ->
            state
            |> update_in([:players], &Map.delete(&1, player_id))
            |> put_in([:games, game_id, :players, color], nil)
            |> update_in([:games, game_id], fn game ->
              %{
                game
                | status: :waiting,
                  queue: [],
                  reset_requests: MapSet.new(),
                  log: ["#{label(color)} dejo la partida." | game.log]
              }
            end)
            |> maybe_drop_empty_private_game(game_id)
        end

      _ ->
        update_in(state.players, &Map.delete(&1, player_id))
    end
  end

  defp keep_player_if_present(state, nil, _game_id, _color), do: state

  defp keep_player_if_present(state, player_id, game_id, color) do
    state
    |> put_in([:players, player_id], %{game_id: game_id, color: color})
    |> put_in([:games, game_id, :players, color], player_id)
  end

  defp reset_ready?(game, player_id) do
    seated_players = seated_players(game)
    MapSet.size(MapSet.put(game.reset_requests, player_id)) >= length(seated_players)
  end

  defp reset_game(state, game_id, old_game) do
    chat = Map.get(old_game, :chat, [])

    if old_game.practice? do
      player_id = old_game.players.white

      state
      |> put_in([:games, game_id], practice_game(game_id, player_id, old_game.settings))
      |> put_in([:players, player_id], %{game_id: game_id, color: :practice})
      |> put_in([:games, game_id, :chat], chat)
      |> update_in([:games, game_id, :log], &["Practica reiniciada." | &1])
    else
      state
      |> put_in([:games, game_id], new_game(game_id, old_game.settings))
      |> keep_player_if_present(old_game.players.white, game_id, :white)
      |> keep_player_if_present(old_game.players.black, game_id, :black)
      |> put_in([:games, game_id, :chat], chat)
      |> update_in([:games, game_id], &refresh_status/1)
      |> update_in([:games, game_id, :log], &["Partida reiniciada por acuerdo." | &1])
    end
  end

  defp empty_waiting_game?(%{practice?: false, status: :waiting, players: players}) do
    is_nil(players.white) and is_nil(players.black)
  end

  defp empty_waiting_game?(_game), do: false

  defp seated_players(game) do
    game.players
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp find_slot(games) do
    games
    |> Enum.reject(fn {_game_id, game} -> game.practice? or Map.get(game, :private?, false) end)
    |> Enum.find_value(fn {game_id, game} ->
      cond do
        is_nil(game.players.white) -> {game_id, :white}
        is_nil(game.players.black) -> {game_id, :black}
        true -> nil
      end
    end)
  end

  defp player_view(state, player_id) do
    assignment = state.players[player_id] || %{game_id: nil, color: nil}
    game = assignment.game_id && state.games[assignment.game_id]

    %{
      player_id: player_id,
      game_id: assignment.game_id,
      color: assignment.color,
      game: public_game(game),
      lobby: public_lobby(state)
    }
  end

  defp player_view(state, player_id, game_id) do
    assignment =
      case state.players[player_id] do
        %{game_id: ^game_id} = assignment -> assignment
        _ -> %{game_id: game_id, color: nil}
      end

    game = state.games[game_id]

    %{
      player_id: player_id,
      game_id: game_id,
      color: assignment.color,
      game: public_game(game),
      lobby: public_lobby(state)
    }
  end

  defp process_next_action(%{queue: []} = game), do: game
  defp process_next_action(%{promotion_pending: pending} = game) when not is_nil(pending), do: game

  defp process_next_action(%{queue: [action | rest]} = game) do
    piece = GameRules.at(game.board, elem(action.from, 0), elem(action.from, 1))

    cond do
      piece == "." or GameRules.color(piece) != action.color ->
        %{game | queue: rest, log: ["Movimiento descartado: la pieza ya no esta ahi." | game.log]}

      game.elixir[action.color] < piece_cost(game.settings, piece) ->
        %{game | queue: rest, log: ["Sin elixir para #{label(action.color)}." | game.log]}

      action.to not in GameRules.legal_moves_for(game.board, elem(action.from, 0), elem(action.from, 1), action.color, game.castling_rights) ->
        %{game | queue: rest, log: ["Movimiento descartado: ya no es valido." | game.log]}

      true ->
        cost = piece_cost(game.settings, piece)
        {board, captured} = GameRules.move(game.board, action.from, action.to, game.castling_rights)
        castling_rights = GameRules.update_castling_rights(game.castling_rights, piece, action.from, captured, action.to)
        cooldowns =
          game.cooldowns
          |> Map.delete(action.from)
          |> put_piece_cooldown(action.to, piece, game.settings)

        {board, promotion_pending, status} =
          resolve_promotion(board, piece, action, captured, castling_rights)

        %{
          game
          | board: board,
            castling_rights: castling_rights,
            cooldowns: cooldowns,
            promotion_pending: promotion_pending,
            queue: rest,
            first_move_pending: clear_first_move(game.first_move_pending, action.color),
            elixir: spend_and_refund_elixir(game, action.color, cost, captured),
            status: status || game.status,
            log: [move_message(action, captured) | game.log]
        }
    end
  end

  defp regen_elixir(game) do
    if game.status != :playing or not is_nil(game.first_move_pending) do
      game
    else
      do_regen_elixir(game)
    end
  end

  defp maybe_enqueue_bot_move(%{practice?: true, bot_enabled?: true, status: :playing, queue: [], promotion_pending: nil, first_move_pending: nil} = game) do
    now = now_ms()

    if is_integer(game.bot_ready_at) and game.bot_ready_at <= now do
      case bot_action(game, now) do
        nil -> %{game | bot_ready_at: now + bot_move_ms(game.settings)}
        action -> %{game | queue: [action], bot_ready_at: now + bot_move_ms(game.settings)}
      end
    else
      game
    end
  end

  defp maybe_enqueue_bot_move(game), do: game

  defp bot_action(game, now) do
    game.board
    |> bot_actions_for(:black, game)
    |> affordable_bot_actions(game)
    |> pick_best_bot_action(game, now)
  end

  defp bot_actions_for(board, color, game) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        to <- GameRules.legal_moves_for(board, r, c, color, game.castling_rights),
        do: %{player_id: :bot, color: color, from: {r, c}, to: to}
  end

  defp affordable_bot_actions(actions, game) do
    Enum.filter(actions, fn action ->
      piece = GameRules.at(game.board, elem(action.from, 0), elem(action.from, 1))
      game.elixir[action.color] >= piece_cost(game.settings, piece)
    end)
  end

  defp pick_best_bot_action([], _game, _now), do: nil

  defp pick_best_bot_action(actions, game, now) do
    actions
    |> order_search_actions(game.board)
    |> Enum.take(@bot_root_branch_limit)
    |> Enum.map(fn action ->
      position = apply_bot_search_action(game.board, game.castling_rights, action)
      score = minimax(position.board, position.castling_rights, :white, @bot_search_depth - 1, -@mate_score, @mate_score)
      {score + bot_tiebreaker(action, now), action}
    end)
    |> Enum.max_by(fn {score, _action} -> score end)
    |> elem(1)
  end

  defp minimax(board, castling_rights, color, depth, alpha, beta) do
    cond do
      depth <= 0 ->
        evaluate_board(board, castling_rights)

      not GameRules.has_legal_moves?(board, color, castling_rights) ->
        terminal_score(board, color, depth)

      color == :black ->
        actions = board |> legal_search_actions(color, castling_rights) |> order_search_actions(board) |> Enum.take(@bot_branch_limit)
        maximize_bot(board, castling_rights, actions, depth, alpha, beta)

      true ->
        actions = board |> legal_search_actions(color, castling_rights) |> order_search_actions(board) |> Enum.take(@bot_branch_limit)
        minimize_bot(board, castling_rights, actions, depth, alpha, beta)
    end
  end

  defp maximize_bot(_board, _rights, [], _depth, alpha, _beta), do: alpha

  defp maximize_bot(board, rights, [action | rest], depth, alpha, beta) do
    position = apply_bot_search_action(board, rights, action)
    score = minimax(position.board, position.castling_rights, :white, depth - 1, alpha, beta)
    alpha = max(alpha, score)

    if alpha >= beta do
      alpha
    else
      maximize_bot(board, rights, rest, depth, alpha, beta)
    end
  end

  defp minimize_bot(_board, _rights, [], _depth, _alpha, beta), do: beta

  defp minimize_bot(board, rights, [action | rest], depth, alpha, beta) do
    position = apply_bot_search_action(board, rights, action)
    score = minimax(position.board, position.castling_rights, :black, depth - 1, alpha, beta)
    beta = min(beta, score)

    if alpha >= beta do
      beta
    else
      minimize_bot(board, rights, rest, depth, alpha, beta)
    end
  end

  defp legal_search_actions(board, color, castling_rights) do
    for {row, r} <- Enum.with_index(board),
        {piece, c} <- Enum.with_index(row),
        piece != ".",
        GameRules.color(piece) == color,
        to <- GameRules.legal_moves_for(board, r, c, color, castling_rights),
        do: %{color: color, from: {r, c}, to: to}
  end

  defp order_search_actions(actions, board) do
    Enum.sort_by(actions, &search_action_priority(board, &1), :desc)
  end

  defp search_action_priority(board, action) do
    piece = GameRules.at(board, elem(action.from, 0), elem(action.from, 1))
    captured = GameRules.at(board, elem(action.to, 0), elem(action.to, 1))
    capture_value = if captured == ".", do: 0, else: Map.fetch!(@piece_values, piece_type(captured))
    promotion_value = if GameRules.promotion_pending?(piece, elem(action.to, 0)), do: 900, else: 0

    capture_value + promotion_value
  end

  defp apply_bot_search_action(board, castling_rights, action) do
    piece = GameRules.at(board, elem(action.from, 0), elem(action.from, 1))
    {board, captured} = GameRules.move(board, action.from, action.to, castling_rights)
    castling_rights = GameRules.update_castling_rights(castling_rights, piece, action.from, captured, action.to)

    board =
      if GameRules.promotion_pending?(piece, elem(action.to, 0)) do
        promote_for_search(board, action.to, action.color)
      else
        board
      end

    %{board: board, castling_rights: castling_rights}
  end

  defp promote_for_search(board, to, :white), do: GameRules.promote(board, to, "Q", :white)
  defp promote_for_search(board, to, :black), do: GameRules.promote(board, to, "q", :black)

  defp evaluate_board(board, castling_rights) do
    material_score(board) + check_score(board, castling_rights)
  end

  defp material_score(board) do
    board
    |> List.flatten()
    |> Enum.reduce(0, fn
      ".", score ->
        score

      piece, score ->
        value = Map.fetch!(@piece_values, piece_type(piece))
        if GameRules.color(piece) == :black, do: score + value, else: score - value
    end)
  end

  defp check_score(board, castling_rights) do
    cond do
      GameRules.in_check?(board, :white) and not GameRules.has_legal_moves?(board, :white, castling_rights) -> @mate_score
      GameRules.in_check?(board, :black) and not GameRules.has_legal_moves?(board, :black, castling_rights) -> -@mate_score
      GameRules.in_check?(board, :white) -> 25
      GameRules.in_check?(board, :black) -> -25
      true -> 0
    end
  end

  defp terminal_score(board, color, depth) do
    cond do
      GameRules.in_check?(board, color) and color == :white -> @mate_score + depth
      GameRules.in_check?(board, color) and color == :black -> -@mate_score - depth
      true -> 0
    end
  end

  defp bot_tiebreaker(action, now) do
    :erlang.phash2({action.from, action.to, now}, 11) / 100
  end

  defp resolve_promotion(board, piece, %{player_id: :bot, color: :black, to: to} = action, captured, castling_rights) do
    if GameRules.promotion_pending?(piece, elem(to, 0)) do
      board = GameRules.promote(board, to, "q", :black)
      {board, nil, next_status(board, captured, action.color, castling_rights)}
    else
      {board, nil, next_status(board, captured, action.color, castling_rights)}
    end
  end

  defp resolve_promotion(board, piece, action, captured, castling_rights) do
    if GameRules.promotion_pending?(piece, elem(action.to, 0)) do
      {board, %{player_id: action.player_id, color: action.color, at: action.to}, :promotion}
    else
      {board, nil, next_status(board, captured, action.color, castling_rights)}
    end
  end

  defp maybe_finish_countdown(%{status: {:starting, starts_at}} = game) do
    if System.monotonic_time(:millisecond) >= starts_at do
      start_playing(game)
    else
      game
    end
  end

  defp maybe_finish_countdown(game), do: game

  defp maybe_start_when_everyone_ready(%{status: {:starting, _starts_at}} = game) do
    seated_players = seated_players(game)

    if seated_players != [] and Enum.all?(seated_players, &MapSet.member?(game.start_requests, &1)) do
      start_playing(game)
    else
      game
    end
  end

  defp maybe_start_when_everyone_ready(game), do: game

  defp start_playing(game) do
    %{
      game
      | status: :playing,
        queue: [],
        start_requests: MapSet.new(),
        log: ["Partida iniciada. Blancas abren." | game.log]
    }
  end

  defp do_regen_elixir(game) do
    regen_per_tick = game.settings.regen_per_second * @tick_ms / 1000

    update_in(game.elixir, fn elixir ->
      Map.new(elixir, fn {color, amount} ->
        {color, min(game.settings.max_elixir, Float.round(amount + regen_per_tick, 2))}
      end)
    end)
  end

  defp clear_expired_cooldowns(game) do
    now = now_ms()
    %{game | cooldowns: Map.reject(game.cooldowns, fn {_square, ready_at} -> ready_at <= now end)}
  end

  defp put_piece_cooldown(cooldowns, square, _piece, settings) do
    cooldown_ms = round(piece_cooldown(settings) * 1000)

    if not Map.get(settings, :cooldown_enabled, true) or cooldown_ms <= 0 do
      cooldowns
    else
      Map.put(cooldowns, square, now_ms() + cooldown_ms)
    end
  end

  defp piece_cooldown(settings), do: Map.get(settings, :cooldown_seconds, @default_settings.cooldown_seconds)
  defp bot_move_ms(settings), do: round(Map.get(settings, :bot_move_seconds, @bot_move_seconds) * 1000)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp new_game(id, settings) do
    %{
      id: id,
      board: GameRules.initial_board(),
      players: %{white: nil, black: nil},
      practice?: false,
      private?: false,
      settings: settings,
      elixir: full_elixir(settings),
      castling_rights: %{
        {:white, :king} => true,
        {:white, :queen} => true,
        {:black, :king} => true,
        {:black, :queen} => true
      },
      cooldowns: %{},
      bot_enabled?: false,
      bot_ready_at: nil,
      promotion_pending: nil,
      finished_at: nil,
      first_move_pending: :white,
      reset_requests: MapSet.new(),
      start_requests: MapSet.new(),
      queue: [],
      status: :waiting,
      chat: [],
      log: ["Esperando jugadores..."]
    }
  end

  defp practice_game(id, player_id, settings) do
    %{
      new_game(id, settings)
      | players: %{white: player_id, black: player_id},
        practice?: true,
        bot_enabled?: true,
        bot_ready_at: now_ms() + bot_move_ms(settings),
        status: :playing,
        log: ["BOT encendido.", "Practica iniciada. Blancas abren."]
    }
  end

  defp private_game(id, settings) do
    %{
      new_game(id, settings)
      | private?: true,
        log: ["Sala privada creada. Comparte el link para invitar."]
    }
  end

  defp refresh_status(%{players: %{white: white, black: black}} = game)
       when is_binary(white) and is_binary(black),
       do: %{game | status: :ready, queue: [], log: ["Ambos jugadores sentados." | game.log]}

  defp refresh_status(game), do: game

  defp refresh_terminal_status(%{status: :playing} = game) do
    case terminal_status(game.board, game.castling_rights) do
      nil -> game
      status -> %{game | status: status, queue: [], finished_at: now_ms()}
    end
  end

  defp refresh_terminal_status(game), do: game

  defp public_game(nil), do: nil

  defp public_game(game) do
    %{
      id: game.id,
      board: game.board,
      players: game.players,
      practice?: game.practice?,
      private?: Map.get(game, :private?, false),
      elixir: game.elixir,
      settings: game.settings,
      bot_enabled?: game.bot_enabled?,
      castling_rights: game.castling_rights,
      cooldowns: public_cooldowns(game),
      queue: game.queue,
      status: game.status,
      countdown_seconds: countdown_seconds(game.status),
      first_move_pending: game.first_move_pending,
      reset_requests: MapSet.to_list(game.reset_requests),
      start_requests: MapSet.to_list(game.start_requests),
      checked_colors: GameRules.checked_colors(game.board),
      promotion_pending: game.promotion_pending,
      finished_at: game.finished_at,
      chat: Map.get(game, :chat, []),
      log: Enum.take(game.log, 8)
    }
  end

  defp public_lobby(state) do
    state.games
    |> Enum.reject(fn {_game_id, game} -> game.practice? or Map.get(game, :private?, false) end)
    |> Enum.sort_by(fn {game_id, _game} -> game_id end)
    |> Enum.map(fn {_game_id, game} ->
      %{
        id: game.id,
        players: game.players,
        status: game.status,
        countdown_seconds: countdown_seconds(game.status)
      }
    end)
  end

  defp broadcast_lobby(state) do
    Phoenix.PubSub.broadcast(ManaChessOnline.PubSub, lobby_topic(), {:lobby_update, public_lobby(state)})
  end

  defp sanitize_chat_message(message) do
    text =
      message
      |> to_string()
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, 180)

    if text == "", do: {:error, :empty}, else: {:ok, text}
  end

  defp chat_role(%{practice?: true}, player_id) when is_binary(player_id), do: "Practica"
  defp chat_role(%{players: %{white: player_id}}, player_id), do: "Blancas"
  defp chat_role(%{players: %{black: player_id}}, player_id), do: "Negras"
  defp chat_role(_game, _player_id), do: "Espectador"

  defp next_status(board, _captured, _moving_color, castling_rights), do: terminal_status(board, castling_rights)

  defp terminal_status(board, castling_rights) do
    cond do
      GameRules.in_check?(board, :white) and not GameRules.has_legal_moves?(board, :white, castling_rights) ->
        {:checkmate, :black, :white}

      GameRules.in_check?(board, :black) and not GameRules.has_legal_moves?(board, :black, castling_rights) ->
        {:checkmate, :white, :black}

      not GameRules.has_legal_moves?(board, :white, castling_rights) and
          not GameRules.has_legal_moves?(board, :black, castling_rights) ->
        :draw

      true ->
        nil
    end
  end

  defp move_message(action, "."), do: "#{label(action.color)} movio una pieza."
  defp move_message(action, captured), do: "#{label(action.color)} capturo #{captured}."
  defp bot_toggle_message(true), do: "Bot de negras activado."
  defp bot_toggle_message(false), do: "Bot de negras desactivado."
  defp label(:white), do: "Blancas"
  defp label(:black), do: "Negras"
  defp label(:practice), do: "Practica"

  defp full_elixir(settings) do
    initial_elixir = min(settings.initial_elixir, settings.max_elixir)
    %{white: initial_elixir, black: initial_elixir}
  end

  defp clamp_elixir(elixir, settings) do
    Map.new(elixir, fn {color, amount} -> {color, min(amount, settings.max_elixir)} end)
  end

  defp piece_cost(settings, piece), do: Map.fetch!(settings.costs, piece_type(piece))

  defp piece_type(piece) do
    case String.downcase(piece) do
      "p" -> :pawn
      "n" -> :knight
      "b" -> :bishop
      "r" -> :rook
      "q" -> :queen
      "k" -> :king
    end
  end

  defp spend_and_refund_elixir(game, color, cost, captured) do
    max_elixir = game.settings.max_elixir
    refund = capture_refund(game.settings, captured)

    Map.update!(game.elixir, color, fn amount ->
      amount
      |> Kernel.-(cost)
      |> Kernel.+(refund)
      |> min(max_elixir)
      |> Float.round(2)
    end)
  end

  defp capture_refund(_settings, "."), do: 0.0

  defp capture_refund(settings, captured) do
    piece_cost(settings, captured) * settings.capture_refund_percent / 100
  end

  defp sanitize_settings(params, current) do
    current_costs = Map.get(current, :costs, @default_settings.costs)
    max_elixir = number_param(params, "max_elixir", Map.get(current, :max_elixir, 10.0), 1, 99)

    %{
      settings_version: @settings_version,
      max_elixir: max_elixir,
      initial_elixir:
        number_param(params, "initial_elixir", Map.get(current, :initial_elixir, max_elixir), 0, max_elixir),
      regen_per_second: number_param(params, "regen_per_second", Map.get(current, :regen_per_second, 1.0), 0, 20),
      capture_refund_percent:
        number_param(params, "capture_refund_percent", Map.get(current, :capture_refund_percent, 40), 0, 100),
      cooldown_enabled: bool_param(params, "cooldown_enabled", Map.get(current, :cooldown_enabled, true)),
      cooldown_seconds: number_param(params, "cooldown_seconds", Map.get(current, :cooldown_seconds, 1.0), 0, 60),
      bot_move_seconds: number_param(params, "bot_move_seconds", Map.get(current, :bot_move_seconds, @bot_move_seconds), 0.25, 30),
      costs: %{
        pawn: number_param(params, "pawn", Map.get(current_costs, :pawn, 1.0), 0, 99),
        knight: number_param(params, "knight", Map.get(current_costs, :knight, 3.0), 0, 99),
        bishop: number_param(params, "bishop", Map.get(current_costs, :bishop, 3.0), 0, 99),
        rook: number_param(params, "rook", Map.get(current_costs, :rook, 4.0), 0, 99),
        queen: number_param(params, "queen", Map.get(current_costs, :queen, 6.0), 0, 99),
        king: number_param(params, "king", Map.get(current_costs, :king, 3.0), 0, 99)
      }
    }
  end

  defp bool_param(params, key, fallback) do
    case Map.get(params, key) do
      values when is_list(values) -> bool_param(%{key => List.last(values)}, key, fallback)
      "true" -> true
      "on" -> true
      true -> true
      "false" -> false
      false -> false
      nil -> fallback
      _ -> fallback
    end
  end

  defp number_param(params, key, fallback, min_value, max_value) do
    params
    |> Map.get(key, fallback)
    |> parse_number(fallback)
    |> max(min_value)
    |> min(max_value)
    |> Float.round(2)
  end

  defp parse_number(value, fallback) when is_binary(value) do
    case Float.parse(value) do
      {number, _rest} -> number
      :error -> fallback
    end
  end

  defp parse_number(value, _fallback) when is_integer(value), do: value / 1
  defp parse_number(value, _fallback) when is_float(value), do: value
  defp parse_number(_value, fallback), do: fallback

  defp load_global_settings do
    path = settings_path()

    with {:ok, json} <- File.read(path),
         {:ok, params} <- Jason.decode(json) do
      settings =
        params
        |> migrate_settings_params()
        |> sanitize_settings(@default_settings)

      persist_global_settings(settings)
      settings
    else
      _ -> @default_settings
    end
  end

  defp migrate_settings_params(%{"settings_version" => version} = params) when is_number(version) and version >= @settings_version, do: params

  defp migrate_settings_params(params) do
    max_elixir = parse_number(Map.get(params, "max_elixir"), @default_settings.max_elixir)
    initial_elixir = parse_number(Map.get(params, "initial_elixir"), @default_settings.initial_elixir)

    params
    |> Map.put("settings_version", @settings_version)
    |> maybe_start_at_half_elixir(max_elixir, initial_elixir)
  end

  defp maybe_start_at_half_elixir(params, max_elixir, initial_elixir) when initial_elixir >= max_elixir do
    Map.put(params, "initial_elixir", max_elixir / 2)
  end

  defp maybe_start_at_half_elixir(params, _max_elixir, _initial_elixir), do: params

  defp persist_global_settings(settings) do
    path = settings_path()

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(settings),
         :ok <- File.write(path, json) do
      :ok
    else
      _ -> :ok
    end
  end

  defp settings_path do
    System.get_env("MANA_CHESS_SETTINGS_PATH") ||
      Path.join(System.get_env("RAILWAY_VOLUME_MOUNT_PATH") || System.tmp_dir!(), @settings_file)
  end

  defp first_move_allowed?(%{first_move_pending: nil}, _color), do: true
  defp first_move_allowed?(%{first_move_pending: color}, color), do: true
  defp first_move_allowed?(_game, _color), do: false

  defp controls_color?(:practice, color) when color in [:white, :black], do: true
  defp controls_color?(color, color), do: true
  defp controls_color?(_player_color, _piece_color), do: false

  defp bot_controls_black?(%{practice?: true, bot_enabled?: true}, :black), do: true
  defp bot_controls_black?(_game, _color), do: false

  defp valid_square?({r, c}), do: r in 0..7 and c in 0..7
  defp valid_square?(_square), do: false

  defp practice_game_id(player_id), do: "practice_" <> Integer.to_string(:erlang.phash2(player_id))

  defp ensure_private_game(state, game_id) do
    if private_game_id?(game_id) and is_nil(state.games[game_id]) do
      put_in(state.games[game_id], private_game(game_id, state.global_settings))
    else
      state
    end
  end

  defp private_game_id?("private_" <> rest), do: byte_size(rest) >= 6
  defp private_game_id?(_game_id), do: false

  defp maybe_drop_empty_private_game(state, game_id) do
    case state.games[game_id] do
      %{private?: true, players: %{white: nil, black: nil}} ->
        update_in(state.games, &Map.delete(&1, game_id))

      _game ->
        state
    end
  end

  defp unique_private_game_id(games) do
    game_id =
      "private_" <>
        (6
         |> :crypto.strong_rand_bytes()
         |> Base.url_encode64(padding: false))

    if Map.has_key?(games, game_id), do: unique_private_game_id(games), else: game_id
  end

  defp clear_first_move(:white, :white), do: nil
  defp clear_first_move(first_move_pending, _color), do: first_move_pending

  defp countdown_seconds({:starting, starts_at}) do
    remaining = starts_at - System.monotonic_time(:millisecond)
    max(0, ceil(remaining / 1000))
  end

  defp countdown_seconds(_status), do: nil

  defp public_cooldowns(game) do
    now = now_ms()

    game.cooldowns
    |> Enum.flat_map(fn {square, ready_at} ->
      remaining = ready_at - now
      piece = GameRules.at(game.board, elem(square, 0), elem(square, 1))

      if remaining > 0 and piece != "." do
        total = round(piece_cooldown(game.settings) * 1000)
        [%{at: square, seconds: max(1, ceil(remaining / 1000)), remaining_ms: remaining, total_ms: total}]
      else
        []
      end
    end)
  end

  defp promotion_choice("Q", :white), do: "Q"
  defp promotion_choice("R", :white), do: "R"
  defp promotion_choice("B", :white), do: "B"
  defp promotion_choice("N", :white), do: "N"
  defp promotion_choice("Q", :black), do: "q"
  defp promotion_choice("R", :black), do: "r"
  defp promotion_choice("B", :black), do: "b"
  defp promotion_choice("N", :black), do: "n"
  defp promotion_choice(_choice, :white), do: "Q"
  defp promotion_choice(_choice, :black), do: "q"
end
