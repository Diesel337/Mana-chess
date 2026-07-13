defmodule ManaChessOnline.GameLobby do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.{
    GameBot,
    GameBroadcast,
    GameChat,
    GameControl,
    GameDirectory,
    GameEngine,
    GameLobbyServers,
    GameLobbyView,
    GameMetrics,
    GamePlayers,
    GamePromotion,
    GameRules,
    GameRooms,
    GameSettings,
    GameSupervisor,
    RateLimiter
  }

  @max_games 4
  @tick_ms 250
  @countdown_ms 5_000
  @chat_rate_limit {30, 10_000}
  @move_rate_limit {60, 1_000}
  @private_room_rate_limit {3, 60_000}
  @presence_rate_limit {120, 60_000}
  @seat_rate_limit {30, 10_000}
  @rate_limit_retention_ms 60_000

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

  def clear_room(player_id, game_id),
    do: GenServer.call(__MODULE__, {:clear_room, player_id, game_id})

  def force_clear_room(game_id), do: GenServer.call(__MODULE__, {:force_clear_room, game_id})
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
    settings = GameSettings.load_global()

    state = %{
      global_settings: settings,
      games:
        Map.new(1..@max_games, fn n ->
          {"game_#{n}", GameRooms.new_game("game_#{n}", settings)}
        end),
      players: %{},
      rate_limits: %{}
    }

    GameLobbyServers.sync_game_servers(state.games)
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
          case find_slot(server_backed_games(state)) do
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
        game_id = GameRooms.unique_private_game_id(server_backed_games(state))

        state =
          state
          |> remove_player(player_id)
          |> put_in(
            [:games, game_id],
            replace_game_state(GameRooms.private_game(game_id, state.global_settings))
          )
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
    {:reply, public_live_lobby(state), state}
  end

  def handle_call(:global_settings, _from, state) do
    {:reply, state.global_settings, state}
  end

  def handle_call(:metrics, _from, state) do
    games = server_backed_games(state)

    metrics =
      GameMetrics.snapshot(
        games,
        GameLobbyServers.game_server_pids(games),
        GameSupervisor.child_count(),
        state.rate_limits
      )

    {:reply, metrics, state}
  end

  def handle_call({:update_global_settings, params}, _from, state) do
    settings = GameSettings.sanitize(params, state.global_settings)
    GameSettings.persist_global(settings)
    games = server_backed_games(state)

    state =
      %{
        state
        | global_settings: settings,
          games:
            Map.new(games, fn {game_id, game} ->
              if empty_waiting_game?(game) do
                {game_id, apply_global_settings_to_waiting_game(game, settings)}
              else
                {game_id, game}
              end
            end)
      }

    broadcast_lobby(state)
    {:reply, settings, state}
  end

  def handle_call({:apply_global_settings_to_practice, player_id}, _from, state) do
    with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
         %{practice?: true} = game <- game_snapshot(game_id, state) do
      game =
        update_game_state(game, fn game ->
          %{
            game
            | settings: state.global_settings,
              elixir: GameSettings.clamp_elixir(game.elixir, state.global_settings),
              cooldowns: %{},
              log: ["Configuracion admin aplicada a la practica." | game.log]
          }
        end)

      state = put_in(state.games[game_id], game)

      Phoenix.PubSub.broadcast(
        ManaChessOnline.PubSub,
        topic(game_id),
        {:game_update, public_game_snapshot(game_id, state)}
      )

      {:reply, :ok, state}
    else
      _ ->
        {:reply, {:error, :no_practice}, state}
    end
  end

  def handle_call({:snapshot, game_id}, _from, state) do
    {:reply, public_game(game_snapshot(game_id, state)), state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    previous_assignment = GamePlayers.assignment(state, player_id)
    previous_game = assigned_game(previous_assignment, state)
    state = remove_player(state, player_id)
    sync_player_assignment(previous_assignment, state)

    if GameRooms.public_lobby_game?(previous_game) do
      GameBroadcast.lobby_update(lobby_topic(), state, now_ms())
    end

    {:reply, :ok, state}
  end

  def handle_call({:clear_room, player_id, game_id}, _from, state) do
    case game_snapshot(game_id, state) do
      %{practice?: false} = game
      when game.status in [:waiting, :ready] ->
        if GameRooms.can_clear_room?(
             GamePlayers.assignment(state, player_id),
             player_id,
             game_id,
             game
           ) do
          state = clear_room_state(state, game_id, game)
          broadcast_lobby(state)
          {:reply, :ok, state}
        else
          {:reply, {:error, :forbidden}, state}
        end

      _ ->
        {:reply, {:error, :not_clearable}, state}
    end
  end

  def handle_call({:force_clear_room, game_id}, _from, state) do
    state =
      case game_snapshot(game_id, state) do
        %{practice?: false} = game when game.status in [:waiting, :ready] ->
          clear_room_state(state, game_id, game)

        _ ->
          state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:reset, player_id}, _from, state) do
    state =
      with %{game_id: game_id, color: color} when is_binary(game_id) <-
             GamePlayers.assignment(state, player_id),
           game when not is_nil(game) <- game_snapshot(game_id, state) do
        if GameRooms.reset_ready?(game, player_id) do
          reset_game(state, game_id, game)
        else
          game =
            update_game_state(game, fn game ->
              %{
                game
                | reset_requests: MapSet.put(game.reset_requests, player_id),
                  log: ["#{GameChat.label(color)} pidio reiniciar la partida." | game.log]
              }
            end)

          put_in(state.games[game_id], game)
        end
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_game, player_id}, _from, state) do
    state =
      with %{game_id: game_id} when is_binary(game_id) <- GamePlayers.assignment(state, player_id),
           %{status: :ready} = game <- game_snapshot(game_id, state) do
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
      with %{game_id: game_id} when is_binary(game_id) <- GamePlayers.assignment(state, player_id),
           %{status: {:starting, _starts_at}} = game <- game_snapshot(game_id, state),
           true <- player_id in seated_players(game) do
        game =
          update_game_state(game, fn game ->
            game
            |> update_in([:start_requests], &MapSet.put(&1, player_id))
            |> GameRooms.maybe_start_when_everyone_ready()
          end)

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_practice, player_id}, _from, state) do
    game_id = GameRooms.practice_game_id(player_id)

    state =
      state
      |> remove_player(player_id)
      |> put_in(
        [:games, game_id],
        replace_game_state(practice_game(game_id, player_id, state.global_settings))
      )
      |> put_in([:players, player_id], %{game_id: game_id, color: :practice})

    broadcast_lobby(state)
    {:reply, player_view(state, player_id), state}
  end

  def handle_call({:toggle_practice_bot, player_id}, _from, state) do
    state =
      with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
           %{practice?: true} = game <- game_snapshot(game_id, state) do
        game =
          update_game_state(game, fn game ->
            enabled? = not game.bot_enabled?

            %{
              game
              | bot_enabled?: enabled?,
                bot_ready_at:
                  if(enabled?, do: now_ms() + GameBot.move_delay_ms(game.settings), else: nil),
                log: [
                  GameChat.bot_toggle_message(enabled?, GameControl.bot_color(game)) | game.log
                ]
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
      with %{game_id: game_id, color: :practice} <- GamePlayers.assignment(state, player_id),
           %{practice?: true} = game <- game_snapshot(game_id, state) do
        game =
          update_game_state(game, fn game ->
            next_bot_color = game |> GameControl.bot_color() |> GameControl.opposite_color()
            chat = Map.get(game, :chat, [])

            practice_game(game_id, player_id, game.settings, next_bot_color)
            |> GameRooms.preserve_practice_bot_state(game)
            |> Map.put(:chat, chat)
            |> update_in(
              [:log],
              &[
                "Ahora juegas #{GameChat.label(GameControl.opposite_color(next_bot_color))}; BOT controla #{GameChat.label(next_bot_color)}."
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
             GamePlayers.assignment(state, player_id),
           game when game.practice? or game.status in [:waiting, :ready] <-
             game_snapshot(game_id, state) do
        settings = GameSettings.sanitize(params, game.settings)

        game =
          update_game_state(game, fn game ->
            %{
              game
              | settings: settings,
                elixir: GameSettings.full_elixir(settings),
                cooldowns: %{},
                log: ["Blancas ajustaron la configuracion." | game.log]
            }
          end)

        put_in(state.games[game_id], game)
      else
        _ -> state
      end

    broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:promote, player_id, choice}, _from, state) do
    state =
      with %{game_id: game_id, color: player_color} <- GamePlayers.assignment(state, player_id),
           game when not is_nil(game) <- game_snapshot(game_id, state),
           %{player_id: ^player_id, color: color, at: square} <- game.promotion_pending,
           true <- GameControl.controls_color?(player_color, color) do
        game =
          update_game_state(game, fn game ->
            board =
              GameRules.promote(game.board, square, GamePromotion.choice(choice, color), color)

            status = GameEngine.terminal_status(board, game.castling_rights) || :playing

            %{
              game
              | board: board,
                status: status,
                promotion_pending: nil,
                log: ["#{GameChat.label(color)} promociono peon." | game.log]
            }
          end)

        put_in(state.games[game_id], game)
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
            {:game_update, public_game_snapshot(game_id, state)}
          )

          broadcast_lobby(state)
        end

        {:reply, :ok, state}

      {:error, :rate_limited, state} ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:send_chat, player_id, game_id, message}, _from, state) do
    with {:ok, text} <- GameChat.sanitize_message(message),
         {:ok, state} <- take_rate_limit(state, {:chat, game_id, player_id}, @chat_rate_limit),
         %{id: ^game_id} = game <- game_snapshot(game_id, state) do
      entry = %{
        id: System.unique_integer([:positive, :monotonic]),
        player_id: player_id,
        name: GameChat.player_name(player_id),
        role: GameChat.role(game, player_id),
        sent_at: System.system_time(:second),
        text: text
      }

      game = append_chat_entry(game, entry)
      state = put_in(state.games[game_id], game)

      Phoenix.PubSub.broadcast(
        ManaChessOnline.PubSub,
        topic(game_id),
        {:game_update, public_game_snapshot(game_id, state)}
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
    with %{game_id: game_id, color: player_color} <- GamePlayers.assignment(state, player_id),
         game when not is_nil(game) <- game_snapshot(game_id, state) do
      cond do
        not GameControl.valid_square?(from) or not GameControl.valid_square?(to) ->
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

      GameControl.bot_controls_color?(game, color) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: BOT controla #{GameChat.label(color)}."
        )

      not GameControl.controls_color?(player_color, color) ->
        reject_move(
          state,
          game_id,
          "Movimiento rechazado: no controlas #{GameChat.label(color)}."
        )

      not GameControl.first_move_allowed?(game, color) ->
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
    case game_snapshot(game_id, state) do
      nil ->
        {state, nil}

      game ->
        game = update_game_state(game, &update_in(&1.log, fn log -> [message | log] end))
        state = put_in(state.games[game_id], game)

        {state, game_id}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @tick_ms)
    now = now_ms()
    live_games = server_backed_games(state)

    {games, changed_game_ids} =
      Enum.reduce(live_games, {%{}, []}, fn {game_id, game}, {games, changed_game_ids} ->
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
    case game_snapshot(game_id, state) do
      %{players: players} = game when color in [:white, :black] ->
        if is_nil(players[color]) do
          state = GamePlayers.assign(state, player_id, game_id, color)

          game =
            update_game_state(game, fn game ->
              game
              |> put_in([:players, color], player_id)
              |> GameRooms.refresh_status()
            end)

          put_in(state.games[game_id], game)
        else
          state
        end

      _ ->
        state
    end
  end

  defp remove_player(state, player_id) do
    case GamePlayers.assignment(state, player_id) do
      %{game_id: game_id, color: color} when is_binary(game_id) ->
        case game_snapshot(game_id, state) do
          %{practice?: true} ->
            GameLobbyServers.stop_game_server(game_id)

            state
            |> GamePlayers.remove(player_id)
            |> update_in([:games], &Map.delete(&1, game_id))

          nil ->
            GamePlayers.remove(state, player_id)

          game ->
            state = GamePlayers.remove(state, player_id)

            game =
              update_game_state(game, fn game ->
                game = put_in(game.players[color], nil)

                %{
                  game
                  | status: :waiting,
                    queue: [],
                    reset_requests: MapSet.new(),
                    log: ["#{GameChat.label(color)} dejo la partida." | game.log]
                }
              end)

            state
            |> put_in([:games, game_id], game)
            |> maybe_drop_empty_private_game(game_id, game)
        end

      _ ->
        GamePlayers.remove(state, player_id)
    end
  end

  defp reset_game(state, game_id, old_game) do
    chat = Map.get(old_game, :chat, [])

    {state, reset_game} =
      if old_game.practice? do
        player_id = old_game.players.white

        reset_game =
          practice_game(game_id, player_id, old_game.settings, GameControl.bot_color(old_game))
          |> GameRooms.preserve_practice_bot_state(old_game)
          |> Map.put(:chat, chat)
          |> update_in([:log], &["Practica reiniciada." | &1])

        {
          GamePlayers.assign(state, player_id, game_id, :practice),
          reset_game
        }
      else
        reset_game =
          GameRooms.reset_room_state(game_id, old_game)
          |> put_in([:players, :white], old_game.players.white)
          |> put_in([:players, :black], old_game.players.black)
          |> Map.put(:chat, chat)
          |> GameRooms.refresh_status()
          |> update_in([:log], &["Partida reiniciada por acuerdo." | &1])

        state =
          state
          |> GamePlayers.keep_assignment_if_present(old_game.players.white, game_id, :white)
          |> GamePlayers.keep_assignment_if_present(old_game.players.black, game_id, :black)

        {state, reset_game}
      end

    put_in(state.games[game_id], replace_game_state(reset_game))
  end

  defp empty_waiting_game?(game), do: GameDirectory.empty_waiting_game?(game)

  defp seated_players(game), do: GameDirectory.seated_players(game)

  defp find_slot(games), do: GameDirectory.find_open_slot(games)

  defp clear_room_state(state, game_id, game) do
    player_ids = seated_players(game)

    state
    |> GamePlayers.remove_many(player_ids)
    |> put_in([:games, game_id], replace_game_state(GameRooms.cleared_game_state(game_id, game)))
  end

  defp player_view(state, player_id) do
    assignment = GamePlayers.assignment_or_empty(state, player_id)
    game = game_snapshot(assignment.game_id, state)

    GameLobbyView.player_view(player_id, assignment, public_game(game), public_live_lobby(state))
  end

  defp player_view(state, player_id, game_id) do
    assignment =
      case GamePlayers.assignment(state, player_id) do
        %{game_id: ^game_id} = assignment -> assignment
        _ -> %{game_id: game_id, color: nil}
      end

    game = game_snapshot(game_id, state)

    GameLobbyView.spectator_view(
      player_id,
      game_id,
      assignment.color,
      public_game(game),
      public_live_lobby(state)
    )
  end

  defp take_rate_limit(state, key, limits),
    do: RateLimiter.take_state(state, key, limits, now_ms())

  defp enqueue_game_action(%{id: _game_id} = game, action, now) do
    GameLobbyServers.enqueue_action(game, action, now)
  end

  defp enqueue_game_action(game, action, now),
    do: GameLobbyServers.enqueue_action(game, action, now)

  defp update_game_state(%{id: _game_id} = game, fun) when is_function(fun, 1) do
    GameLobbyServers.update_state(game, fun)
  end

  defp update_game_state(game, fun) when is_function(fun, 1),
    do: GameLobbyServers.update_state(game, fun)

  defp replace_game_state(game) do
    GameLobbyServers.replace_game_state(game)
  end

  defp game_snapshot(game_id, state) when is_binary(game_id) do
    GameLobbyServers.game_snapshot(game_id, state.games)
  end

  defp game_snapshot(_game_id, _state), do: nil

  defp server_backed_games(state) do
    GameLobbyServers.server_backed_games(state.games)
  end

  defp append_chat_entry(game, entry), do: update_game_state(game, &GameChat.put_entry(&1, entry))

  defp apply_global_settings_to_waiting_game(game, settings) do
    update_game_state(game, fn game ->
      if empty_waiting_game?(game) do
        %{game | settings: settings, elixir: GameSettings.full_elixir(settings), cooldowns: %{}}
      else
        game
      end
    end)
  end

  defp tick_game_server(game, now), do: GameLobbyServers.tick_game(game, now, @tick_ms)

  defp cooldown_active?(game, square), do: GameEngine.cooldown_active?(game, square, now_ms())

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp practice_game(id, player_id, settings, bot_color \\ :black) do
    GameRooms.practice_game_for_player(id, player_id, settings, now_ms(), bot_color)
  end

  defp public_game(game), do: public_game_at(game, now_ms())

  defp public_game_at(game, now),
    do: GameLobbyView.public_game(game, now)

  defp public_game_snapshot(game_id, state), do: public_game(game_snapshot(game_id, state))

  defp public_lobby_at(state, now), do: GameLobbyView.public_lobby(state, now)

  defp public_live_lobby(state),
    do: GameBroadcast.live_lobby(state, now_ms())

  defp broadcast_game_update(game, now) do
    GameBroadcast.game_update(topic(game.id), game, now)
  end

  defp game_broadcast_needed?(previous_game, next_game, now) do
    GameBroadcast.game_update_needed?(
      public_game_at(previous_game, now),
      public_game_at(next_game, now),
      next_game
    )
  end

  defp lobby_broadcast_needed?(previous_state, next_state, now) do
    GameBroadcast.lobby_update_needed?(
      public_lobby_at(previous_state, now),
      public_lobby_at(next_state, now),
      next_state.games
    )
  end

  defp broadcast_lobby(state) do
    GameLobbyServers.sync_game_servers(state.games)
    GameBroadcast.lobby_update(lobby_topic(), state, now_ms())
  end

  defp sync_player_assignment(%{game_id: game_id}, state) when is_binary(game_id) do
    game_id
    |> game_snapshot(state)
    |> GameLobbyServers.sync_game_server()
  end

  defp sync_player_assignment(_assignment, _state), do: :ok

  defp assigned_game(%{game_id: game_id}, state) when is_binary(game_id),
    do: game_snapshot(game_id, state)

  defp assigned_game(_assignment, _state), do: nil

  defp ensure_private_game(state, game_id) do
    if GameRooms.private_game_id?(game_id) do
      case game_snapshot(game_id, state) do
        nil ->
          game = replace_game_state(GameRooms.private_game(game_id, state.global_settings))
          put_in(state.games[game_id], game)

        game ->
          game = replace_game_state(game)
          put_in(state.games[game_id], game)
      end
    else
      state
    end
  end

  defp maybe_drop_empty_private_game(state, game_id, game) do
    if GameRooms.empty_private_game?(game) do
      GameLobbyServers.stop_game_server(game_id)
      update_in(state.games, &Map.delete(&1, game_id))
    else
      state
    end
  end
end
