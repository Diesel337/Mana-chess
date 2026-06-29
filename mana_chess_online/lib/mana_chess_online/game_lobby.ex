defmodule ManaChessOnline.GameLobby do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.{
    GameBot,
    GameDirectory,
    GameEngine,
    GameMetrics,
    GameRules,
    GameServer,
    GameState,
    GameSupervisor,
    GameTick,
    RateLimiter
  }

  @max_games 4
  @tick_ms 250
  @countdown_ms 5_000
  @bot_move_seconds 1.2
  @chat_rate_limit {30, 10_000}
  @move_rate_limit {60, 1_000}
  @private_room_rate_limit {3, 60_000}
  @presence_rate_limit {120, 60_000}
  @seat_rate_limit {30, 10_000}
  @rate_limit_retention_ms 60_000
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

  def sit(player_id, game_id, color),
    do: GenServer.call(__MODULE__, {:sit, player_id, game_id, color})

  def sit_anywhere(player_id), do: GenServer.call(__MODULE__, {:sit_anywhere, player_id})
  def create_private(player_id), do: GenServer.call(__MODULE__, {:create_private, player_id})
  def watch(player_id, game_id), do: GenServer.call(__MODULE__, {:watch, player_id, game_id})
  def snapshot(game_id), do: GenServer.call(__MODULE__, {:snapshot, game_id})
  def lobby, do: GenServer.call(__MODULE__, :lobby)
  def metrics(timeout \\ 5_000), do: GenServer.call(__MODULE__, :metrics, timeout)
  def global_settings, do: GenServer.call(__MODULE__, :global_settings)

  def update_global_settings(params),
    do: GenServer.call(__MODULE__, {:update_global_settings, params})

  def apply_global_settings_to_practice(player_id),
    do: GenServer.call(__MODULE__, {:apply_global_settings_to_practice, player_id})

  def leave(player_id), do: GenServer.call(__MODULE__, {:leave, player_id})
  def clear_room(game_id), do: GenServer.call(__MODULE__, {:clear_room, game_id})
  def reset(player_id), do: GenServer.call(__MODULE__, {:reset, player_id})
  def start_game(player_id), do: GenServer.call(__MODULE__, {:start_game, player_id})
  def ready_to_start(player_id), do: GenServer.call(__MODULE__, {:ready_to_start, player_id})
  def start_practice(player_id), do: GenServer.call(__MODULE__, {:start_practice, player_id})

  def toggle_practice_bot(player_id),
    do: GenServer.call(__MODULE__, {:toggle_practice_bot, player_id})

  def toggle_practice_side(player_id),
    do: GenServer.call(__MODULE__, {:toggle_practice_side, player_id})

  def update_settings(player_id, params),
    do: GenServer.call(__MODULE__, {:update_settings, player_id, params})

  def promote(player_id, choice), do: GenServer.call(__MODULE__, {:promote, player_id, choice})

  def enqueue(player_id, from, to),
    do: GenServer.call(__MODULE__, {:enqueue, player_id, from, to})

  def send_chat(player_id, game_id, message),
    do: GenServer.call(__MODULE__, {:send_chat, player_id, game_id, message})

  @impl true
  def init(:ok) do
    Process.send_after(self(), :tick, @tick_ms)
    settings = load_global_settings()

    state = %{
      global_settings: settings,
      games: Map.new(1..@max_games, fn n -> {"game_#{n}", new_game("game_#{n}", settings)} end),
      players: %{},
      rate_limits: %{}
    }

    sync_game_servers(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id}, _from, state) do
    case take_rate_limit(state, {:join, player_id}, @presence_rate_limit) do
      {:ok, state} -> {:reply, player_view(state, player_id), state}
      {:error, :rate_limited, state} -> {:reply, player_view(state, player_id), state}
    end
  end

  def handle_call({:sit, player_id, game_id, color}, _from, state) do
    case take_rate_limit(state, {:seat, player_id}, @seat_rate_limit) do
      {:ok, state} ->
        state =
          state
          |> remove_player(player_id)
          |> assign_player(player_id, game_id, color)

        broadcast_lobby(state)
        {:reply, player_view(state, player_id), state}

      {:error, :rate_limited, state} ->
        {:reply, player_view(state, player_id), state}
    end
  end

  def handle_call({:sit_anywhere, player_id}, _from, state) do
    case take_rate_limit(state, {:seat, player_id}, @seat_rate_limit) do
      {:ok, state} ->
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

      {:error, :rate_limited, state} ->
        {:reply, player_view(state, player_id), state}
    end
  end

  def handle_call({:create_private, player_id}, _from, state) do
    case take_rate_limit(state, {:private_room, player_id}, @private_room_rate_limit) do
      {:ok, state} ->
        game_id = unique_private_game_id(state.games)

        state =
          state
          |> remove_player(player_id)
          |> put_in([:games, game_id], private_game(game_id, state.global_settings))
          |> assign_player(player_id, game_id, :white)

        broadcast_lobby(state)
        {:reply, {:ok, player_view(state, player_id)}, state}

      {:error, :rate_limited, state} ->
        {:reply, {:error, :rate_limited}, state}
    end
  end

  def handle_call({:watch, player_id, game_id}, _from, state) do
    case take_rate_limit(state, {:watch, player_id}, @presence_rate_limit) do
      {:ok, state} ->
        state = ensure_private_game(state, game_id)
        {:reply, player_view(state, player_id, game_id), state}

      {:error, :rate_limited, state} ->
        {:reply, player_view(state, player_id, game_id), state}
    end
  end

  def handle_call(:lobby, _from, state) do
    {:reply, public_lobby(state), state}
  end

  def handle_call(:global_settings, _from, state) do
    {:reply, state.global_settings, state}
  end

  def handle_call(:metrics, _from, state) do
    metrics =
      GameMetrics.snapshot(
        state.games,
        game_server_pids(state.games),
        GameSupervisor.child_count(),
        state.rate_limits
      )

    {:reply, metrics, state}
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

        Phoenix.PubSub.broadcast(
          ManaChessOnline.PubSub,
          topic(game_id),
          {:game_update, public_game(state.games[game_id])}
        )

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :no_practice}, state}
    end
  end

  def handle_call({:snapshot, game_id}, _from, state) do
    {:reply, public_game(state.games[game_id]), state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    previous_assignment = state.players[player_id]
    previous_game = assigned_game(previous_assignment, state)
    state = remove_player(state, player_id)
    sync_player_assignment(previous_assignment, state)

    if public_lobby_game?(previous_game) do
      broadcast_lobby_payload(state)
    end

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

        game =
          update_game_state(game, fn game ->
            %{
              game
              | status: {:starting, starts_at},
                queue: [],
                reset_requests: MapSet.new(),
                start_requests: MapSet.new([player_id]),
                log: ["Cuenta regresiva iniciada." | game.log]
            }
          end)

        put_in(state.games[game_id], game)
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
          update_game_state(game, fn game ->
            game
            |> update_in([:start_requests], &MapSet.put(&1, player_id))
            |> maybe_start_when_everyone_ready()
          end)

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

        game =
          update_game_state(game, fn game ->
            %{
              game
              | bot_enabled?: enabled?,
                bot_ready_at:
                  if(enabled?, do: now_ms() + GameBot.move_delay_ms(game.settings), else: nil),
                log: [bot_toggle_message(enabled?, bot_color(game)) | game.log]
            }
          end)

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:toggle_practice_side, player_id}, _from, state) do
    state =
      with %{game_id: game_id, color: :practice} <- state.players[player_id],
           %{practice?: true} = game <- state.games[game_id] do
        game =
          update_game_state(game, fn game ->
            next_bot_color = game |> bot_color() |> opposite_color()
            chat = Map.get(game, :chat, [])

            practice_game(game_id, player_id, game.settings, next_bot_color)
            |> Map.put(:chat, chat)
            |> update_in(
              [:log],
              &[
                "Ahora juegas #{label(opposite_color(next_bot_color))}; BOT controla #{label(next_bot_color)}."
                | &1
              ]
            )
          end)

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:update_settings, player_id, params}, _from, state) do
    state =
      with %{game_id: game_id, color: color} when color in [:white, :practice] <-
             state.players[player_id],
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
        status = GameEngine.terminal_status(board, game.castling_rights) || :playing

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
    case take_rate_limit(state, {:move, player_id}, @move_rate_limit) do
      {:ok, state} ->
        {state, game_id} = enqueue_move(state, player_id, from, to)

        if game_id do
          Phoenix.PubSub.broadcast(
            ManaChessOnline.PubSub,
            topic(game_id),
            {:game_update, public_game(state.games[game_id])}
          )

          broadcast_lobby(state)
        end

        {:reply, :ok, state}

      {:error, :rate_limited, state} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:send_chat, player_id, game_id, message}, _from, state) do
    with {:ok, text} <- sanitize_chat_message(message),
         {:ok, state} <- take_rate_limit(state, {:chat, game_id, player_id}, @chat_rate_limit),
         %{id: ^game_id} = game <- state.games[game_id] do
      entry = %{
        id: System.unique_integer([:positive, :monotonic]),
        player_id: player_id,
        name: chat_name(player_id),
        role: chat_role(game, player_id),
        sent_at: System.system_time(:second),
        text: text
      }

      game = append_chat_entry(game, entry)
      state = put_in(state.games[game_id], game)

      Phoenix.PubSub.broadcast(
        ManaChessOnline.PubSub,
        topic(game_id),
        {:game_update, public_game(state.games[game_id])}
      )

      {:reply, :ok, state}
    else
      {:error, :rate_limited, state} ->
        {:reply, {:error, :rate_limited}, state}

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
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: no hay pieza en origen #{inspect(from)}."
        )

      color not in [:white, :black] ->
        reject_move(state, game_id, "Movimiento rechazado: pieza sin color.")

      bot_controls_color?(game, color) ->
        reject_move(state, game_id, "Movimiento rechazado: BOT controla #{label(color)}.")

      not controls_color?(player_color, color) ->
        reject_move(state, game_id, "Movimiento rechazado: no controlas #{label(color)}.")

      not first_move_allowed?(game, color) ->
        reject_move(state, game_id, "Movimiento rechazado: Blancas deben abrir.")

      cooldown_active?(game, from) ->
        reject_move(state, game_id, "Movimiento rechazado: pieza en cooldown.")

      to not in GameRules.legal_moves_for(
        game.board,
        elem(from, 0),
        elem(from, 1),
        color,
        game.castling_rights
      ) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: #{inspect(from)} -> #{inspect(to)} no es legal."
        )

      true ->
        action = %{player_id: player_id, color: color, from: from, to: to}
        now = now_ms()

        game = enqueue_game_action(game, action, now)

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
    now = now_ms()

    {games, changed_game_ids} =
      Enum.reduce(state.games, {%{}, []}, fn {game_id, game}, {games, changed_game_ids} ->
        ticked_game = tick_game_server(game, now)

        changed_game_ids =
          if game_broadcast_needed?(game, ticked_game, now) do
            [game_id | changed_game_ids]
          else
            changed_game_ids
          end

        {Map.put(games, game_id, ticked_game), changed_game_ids}
      end)

    next_state = %{
      state
      | games: games,
        rate_limits: RateLimiter.prune(state.rate_limits, now, @rate_limit_retention_ms)
    }

    changed_game_ids
    |> Enum.reverse()
    |> Enum.each(fn game_id -> broadcast_game_update(next_state.games[game_id], now) end)

    if lobby_broadcast_needed?(state, next_state, now) do
      Phoenix.PubSub.broadcast(
        ManaChessOnline.PubSub,
        lobby_topic(),
        {:lobby_update, public_lobby_at(next_state, now)}
      )
    end

    {:noreply, next_state}
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
            stop_game_server(game_id)

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
      |> put_in(
        [:games, game_id],
        practice_game(game_id, player_id, old_game.settings, bot_color(old_game))
      )
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

  defp empty_waiting_game?(game), do: GameDirectory.empty_waiting_game?(game)

  defp seated_players(game), do: GameDirectory.seated_players(game)

  defp find_slot(games), do: GameDirectory.find_open_slot(games)

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

  defp take_rate_limit(state, key, {max_hits, window_ms}) do
    case RateLimiter.hit(state.rate_limits, key, now_ms(), max_hits, window_ms) do
      {:ok, rate_limits} ->
        {:ok, %{state | rate_limits: rate_limits}}

      {{:error, :rate_limited}, rate_limits} ->
        {:error, :rate_limited, %{state | rate_limits: rate_limits}}
    end
  end

  defp enqueue_game_action(game, action, now) do
    case GameSupervisor.upsert_game(game) do
      {:ok, pid} ->
        GameServer.enqueue(pid, action, now)

      _error ->
        game
        |> Map.update!(:queue, &(&1 ++ [action]))
        |> GameTick.after_bot(now, @default_settings.cooldown_seconds)
    end
  end

  defp update_game_state(game, fun) when is_function(fun, 1) do
    case GameSupervisor.upsert_game(game) do
      {:ok, pid} ->
        GameServer.update(pid, fun)

      _error ->
        fun.(game)
    end
  end

  defp append_chat_entry(game, entry), do: update_game_state(game, &put_chat_entry(&1, entry))

  defp put_chat_entry(game, entry) do
    chat =
      [entry | Map.get(game, :chat, [])]
      |> Enum.take(24)

    Map.put(game, :chat, chat)
  end

  defp tick_game_server(game, now) do
    case GameSupervisor.upsert_game(game) do
      {:ok, pid} -> GameServer.tick(pid, now)
      _error -> GameTick.tick(game, now, @tick_ms, @default_settings.cooldown_seconds)
    end
  end

  defp maybe_start_when_everyone_ready(%{status: {:starting, _starts_at}} = game) do
    GameTick.start_when_ready(game, seated_players(game))
  end

  defp maybe_start_when_everyone_ready(game), do: game

  defp cooldown_active?(game, square), do: GameEngine.cooldown_active?(game, square, now_ms())

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp new_game(id, settings), do: GameState.new_game(id, settings)

  defp practice_game(id, player_id, settings, bot_color \\ :black) do
    GameState.practice_game(
      id,
      player_id,
      settings,
      now_ms(),
      GameBot.move_delay_ms(settings),
      bot_color
    )
  end

  defp private_game(id, settings), do: GameState.private_game(id, settings)

  defp refresh_status(%{players: %{white: white, black: black}} = game)
       when is_binary(white) and is_binary(black),
       do: %{game | status: :ready, queue: [], log: ["Ambos jugadores sentados." | game.log]}

  defp refresh_status(game), do: game

  defp public_game(game), do: public_game_at(game, now_ms())

  defp public_game_at(game, now),
    do: GameState.public_game(game, now, @default_settings.cooldown_seconds)

  defp public_lobby(state), do: public_lobby_at(state, now_ms())

  defp public_lobby_at(state, now), do: GameState.public_lobby(state, now)

  defp broadcast_game_update(game, now) do
    Phoenix.PubSub.broadcast(
      ManaChessOnline.PubSub,
      topic(game.id),
      {:game_update, public_game_at(game, now)}
    )
  end

  defp game_broadcast_needed?(previous_game, next_game, now) do
    public_game_at(previous_game, now) != public_game_at(next_game, now) or
      countdown_visible?(next_game) or cooldowns_visible?(next_game)
  end

  defp lobby_broadcast_needed?(previous_state, next_state, now) do
    public_lobby_at(previous_state, now) != public_lobby_at(next_state, now) or
      Enum.any?(next_state.games, fn {_game_id, game} -> countdown_visible?(game) end)
  end

  defp countdown_visible?(%{status: {:starting, _starts_at}}), do: true
  defp countdown_visible?(_game), do: false

  defp cooldowns_visible?(%{status: :playing, cooldowns: cooldowns}), do: map_size(cooldowns) > 0
  defp cooldowns_visible?(_game), do: false

  defp broadcast_lobby(state) do
    sync_game_servers(state)
    broadcast_lobby_payload(state)
  end

  defp broadcast_lobby_payload(state) do
    Phoenix.PubSub.broadcast(
      ManaChessOnline.PubSub,
      lobby_topic(),
      {:lobby_update, public_lobby(state)}
    )
  end

  defp sync_game_servers(state) do
    Enum.each(state.games, fn {_game_id, game} -> sync_game_server(game) end)
    state
  end

  defp sync_game_server(nil), do: :ok

  defp sync_game_server(game) do
    case GameSupervisor.upsert_game(game) do
      {:ok, _pid} -> :ok
      _error -> :ok
    end
  end

  defp sync_player_assignment(%{game_id: game_id}, state) when is_binary(game_id) do
    sync_game_server(state.games[game_id])
  end

  defp sync_player_assignment(_assignment, _state), do: :ok

  defp assigned_game(%{game_id: game_id}, state) when is_binary(game_id), do: state.games[game_id]
  defp assigned_game(_assignment, _state), do: nil

  defp public_lobby_game?(%{practice?: false} = game), do: !Map.get(game, :private?, false)
  defp public_lobby_game?(_game), do: false

  defp game_server_pids(games) do
    games
    |> Map.keys()
    |> Enum.flat_map(fn game_id ->
      case GameSupervisor.lookup_game(game_id) do
        {:ok, pid} -> [pid]
        :error -> []
      end
    end)
  end

  defp stop_game_server(game_id), do: GameSupervisor.stop_game(game_id)

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

  defp chat_name(player_id) when is_binary(player_id) do
    tag =
      player_id
      |> :erlang.phash2(36 * 36 * 36 * 36)
      |> Integer.to_string(36)
      |> String.upcase()
      |> String.pad_leading(4, "0")

    "Jugador " <> tag
  end

  defp chat_name(_player_id), do: "Jugador"

  defp bot_toggle_message(true, color), do: "Bot activado: controla #{label(color)}."
  defp bot_toggle_message(false, _color), do: "Bot desactivado."
  defp label(:white), do: "Blancas"
  defp label(:black), do: "Negras"
  defp label(:practice), do: "Practica"

  defp full_elixir(settings), do: GameState.full_elixir(settings)

  defp clamp_elixir(elixir, settings) do
    Map.new(elixir, fn {color, amount} -> {color, min(amount, settings.max_elixir)} end)
  end

  defp sanitize_settings(params, current) do
    current_costs = Map.get(current, :costs, @default_settings.costs)
    max_elixir = number_param(params, "max_elixir", Map.get(current, :max_elixir, 10.0), 1, 99)

    %{
      settings_version: @settings_version,
      max_elixir: max_elixir,
      initial_elixir:
        number_param(
          params,
          "initial_elixir",
          Map.get(current, :initial_elixir, max_elixir),
          0,
          max_elixir
        ),
      regen_per_second:
        number_param(params, "regen_per_second", Map.get(current, :regen_per_second, 1.0), 0, 20),
      capture_refund_percent:
        number_param(
          params,
          "capture_refund_percent",
          Map.get(current, :capture_refund_percent, 40),
          0,
          100
        ),
      cooldown_enabled:
        bool_param(params, "cooldown_enabled", Map.get(current, :cooldown_enabled, true)),
      cooldown_seconds:
        number_param(params, "cooldown_seconds", Map.get(current, :cooldown_seconds, 1.0), 0, 60),
      bot_move_seconds:
        number_param(
          params,
          "bot_move_seconds",
          Map.get(current, :bot_move_seconds, @bot_move_seconds),
          0.25,
          30
        ),
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

  defp migrate_settings_params(%{"settings_version" => version} = params)
       when is_number(version) and version >= @settings_version, do: params

  defp migrate_settings_params(params) do
    max_elixir = parse_number(Map.get(params, "max_elixir"), @default_settings.max_elixir)

    initial_elixir =
      parse_number(Map.get(params, "initial_elixir"), @default_settings.initial_elixir)

    params
    |> Map.put("settings_version", @settings_version)
    |> maybe_start_at_half_elixir(max_elixir, initial_elixir)
  end

  defp maybe_start_at_half_elixir(params, max_elixir, initial_elixir)
       when initial_elixir >= max_elixir do
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

  defp bot_controls_color?(%{practice?: true, bot_enabled?: true} = game, color),
    do: bot_color(game) == color

  defp bot_controls_color?(_game, _color), do: false

  defp bot_color(%{bot_color: color}) when color in [:white, :black], do: color
  defp bot_color(_game), do: :black

  defp opposite_color(:white), do: :black
  defp opposite_color(:black), do: :white

  defp valid_square?({r, c}), do: r in 0..7 and c in 0..7
  defp valid_square?(_square), do: false

  defp practice_game_id(player_id),
    do: "practice_" <> Integer.to_string(:erlang.phash2(player_id))

  defp ensure_private_game(state, game_id) do
    if private_game_id?(game_id) and is_nil(state.games[game_id]) do
      game = private_game(game_id, state.global_settings)
      sync_game_server(game)
      put_in(state.games[game_id], game)
    else
      state
    end
  end

  defp private_game_id?("private_" <> rest), do: byte_size(rest) >= 6
  defp private_game_id?(_game_id), do: false

  defp maybe_drop_empty_private_game(state, game_id) do
    case state.games[game_id] do
      %{private?: true, players: %{white: nil, black: nil}} ->
        stop_game_server(game_id)
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
