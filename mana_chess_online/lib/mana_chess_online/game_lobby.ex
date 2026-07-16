defmodule ManaChessOnline.GameLobby do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.{
    GameCapacity,
    GameLifecycle,
    GameLobbyActions,
    GameLobbyChat,
    GameLobbyMatchmaking,
    GameLobbyMoves,
    GameLobbyPractice,
    GameLobbyPresence,
    GameLobbyRooms,
    GameLobbyRuntime,
    GameLobbySettings,
    GameLobbyTick,
    GameMetrics,
    GamePlayers,
    GameRooms,
    GameRuntimeConfig,
    GameSettings,
    GameSupervisor
  }

  @max_games 4
  @countdown_ms 5_000
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

  def heartbeat(player_id, game_id),
    do: GenServer.cast(__MODULE__, {:heartbeat, player_id, game_id})

  @impl true
  def init(:ok) do
    Process.send_after(self(), :tick, GameRuntimeConfig.tick_ms())
    settings = GameSettings.load_global()
    now = GameLobbyRuntime.now_ms()

    state = %{
      global_settings: settings,
      games:
        Map.new(1..@max_games, fn n ->
          {"game_#{n}", GameRooms.new_game("game_#{n}", settings)}
        end),
      players: %{},
      rate_limits: %{},
      game_activity: %{},
      last_lifecycle_at: now,
      capacity_stats: %{rejected_count: 0, cleaned_count: 0}
    }

    GameLobbyRuntime.sync_game_servers(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, player_id}, _from, state) do
    state = GameLobbyPresence.join(state, player_id, GameLobbyRuntime.now_ms())
    {:reply, GameLobbyRuntime.player_view(state, player_id), state}
  end

  def handle_call({:sit, player_id, game_id, color}, _from, state) do
    now = GameLobbyRuntime.now_ms()

    case GameLobbyMatchmaking.sit(state, player_id, game_id, color, now) do
      {:ok, state} ->
        state = GameLifecycle.touch_player(state, player_id, now)
        GameLobbyRuntime.broadcast_lobby(state)
        {:reply, GameLobbyRuntime.player_view(state, player_id), state}

      {:error, :rate_limited, state} ->
        {:reply, GameLobbyRuntime.player_view(state, player_id), state}
    end
  end

  def handle_call({:sit_anywhere, player_id}, _from, state) do
    now = GameLobbyRuntime.now_ms()

    case GameLobbyMatchmaking.sit_anywhere(state, player_id, now) do
      {:ok, state} ->
        state = GameLifecycle.touch_player(state, player_id, now)
        GameLobbyRuntime.broadcast_lobby(state)
        {:reply, GameLobbyRuntime.player_view(state, player_id), state}

      {:error, :rate_limited, state} ->
        {:reply, GameLobbyRuntime.player_view(state, player_id), state}
    end
  end

  def handle_call({:create_private, player_id}, _from, state) do
    now = GameLobbyRuntime.now_ms()

    case GameLobbyMatchmaking.create_private(state, player_id, now) do
      {:ok, state, game_id} ->
        state = GameLifecycle.touch_game(state, game_id, now)
        GameLobbyRuntime.broadcast_lobby(state)
        {:reply, {:ok, GameLobbyRuntime.player_view(state, player_id)}, state}

      {:error, :rate_limited, state} ->
        {:reply, {:error, :rate_limited}, state}

      {:error, :capacity, state} ->
        {:reply, {:error, :capacity}, state}
    end
  end

  def handle_call({:watch, player_id, game_id}, _from, state) do
    now = GameLobbyRuntime.now_ms()
    state = GameLobbyPresence.watch(state, player_id, game_id, now)
    state = GameLifecycle.heartbeat(state, player_id, game_id, now)
    {:reply, GameLobbyRuntime.spectator_view(state, player_id, game_id), state}
  end

  def handle_call(:lobby, _from, state) do
    {:reply, GameLobbyRuntime.public_live_lobby(state), state}
  end

  def handle_call(:global_settings, _from, state) do
    {:reply, state.global_settings, state}
  end

  def handle_call(:metrics, _from, state) do
    games = GameLobbyRuntime.server_backed_games(state)

    metrics =
      GameMetrics.snapshot(
        games,
        GameLobbyRuntime.game_server_pids(state),
        GameSupervisor.child_count(),
        state.rate_limits,
        System.system_time(:millisecond),
        GameCapacity.snapshot(state)
      )

    {:reply, metrics, state}
  end

  def handle_call({:update_global_settings, params}, _from, state) do
    {state, settings} = GameLobbySettings.update_global_settings(state, params)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, settings, state}
  end

  def handle_call({:apply_global_settings_to_practice, player_id}, _from, state) do
    case GameLobbySettings.apply_global_settings_to_practice(state, player_id) do
      {:ok, state} ->
        %{game_id: game_id} = GamePlayers.assignment(state, player_id)
        GameLobbyRuntime.broadcast_game_snapshot(game_id, state)
        {:reply, :ok, state}

      {:error, :no_practice, state} ->
        {:reply, {:error, :no_practice}, state}
    end
  end

  def handle_call({:snapshot, game_id}, _from, state) do
    {:reply, GameLobbyRuntime.public_game_snapshot(game_id, state), state}
  end

  def handle_call({:leave, player_id}, _from, state) do
    {state, public_lobby_changed?} = GameLobbyPresence.leave(state, player_id)
    state = GameLifecycle.forget_missing_games(state)

    if public_lobby_changed? do
      GameLobbyRuntime.broadcast_lobby(state)
    end

    {:reply, :ok, state}
  end

  def handle_call({:clear_room, player_id, game_id}, _from, state) do
    case GameLobbyRooms.clear_room(state, player_id, game_id) do
      {:ok, state} ->
        GameLobbyRuntime.broadcast_lobby(state)
        {:reply, :ok, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:force_clear_room, game_id}, _from, state) do
    state = GameLobbyRooms.force_clear_room(state, game_id)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:reset, player_id}, _from, state) do
    state = GameLobbyActions.reset(state, player_id, GameLobbyRuntime.now_ms())
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_game, player_id}, _from, state) do
    starts_at = GameLobbyRuntime.now_ms() + @countdown_ms
    state = GameLobbyActions.start_game(state, player_id, starts_at)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:ready_to_start, player_id}, _from, state) do
    state = GameLobbyActions.ready_to_start(state, player_id)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:start_practice, player_id}, _from, state) do
    now = GameLobbyRuntime.now_ms()
    state = GameLobbyPractice.start_practice(state, player_id, now)
    state = GameLifecycle.touch_player(state, player_id, now)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, GameLobbyRuntime.player_view(state, player_id), state}
  end

  def handle_call({:toggle_practice_bot, player_id}, _from, state) do
    state = GameLobbyPractice.toggle_bot(state, player_id, GameLobbyRuntime.now_ms())
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, GameLobbyRuntime.player_view(state, player_id), state}
  end

  def handle_call({:toggle_practice_side, player_id}, _from, state) do
    state = GameLobbyPractice.toggle_side(state, player_id, GameLobbyRuntime.now_ms())
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, GameLobbyRuntime.player_view(state, player_id), state}
  end

  def handle_call({:update_settings, player_id, params}, _from, state) do
    state = GameLobbySettings.update_player_settings(state, player_id, params)
    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:promote, player_id, choice}, _from, state) do
    state =
      GameLobbyActions.promote(state, player_id, choice, GameLobbyRuntime.now_ms())

    GameLobbyRuntime.broadcast_lobby(state)
    {:reply, :ok, state}
  end

  def handle_call({:enqueue, player_id, from, to}, _from, state) do
    now = GameLobbyRuntime.now_ms()

    {state, game_id} =
      GameLobbyMoves.enqueue(state, player_id, from, to, now)

    state = if game_id, do: GameLifecycle.touch_game(state, game_id, now), else: state

    if game_id do
      GameLobbyRuntime.broadcast_game_snapshot(game_id, state)
      GameLobbyRuntime.broadcast_lobby(state)
    end

    {:reply, :ok, state}
  end

  def handle_call({:send_chat, player_id, game_id, message}, _from, state) do
    case GameLobbyChat.send_chat(
           state,
           player_id,
           game_id,
           message,
           GameLobbyRuntime.now_ms(),
           System.system_time(:second)
         ) do
      {:ok, state} ->
        state = GameLifecycle.touch_game(state, game_id, GameLobbyRuntime.now_ms())
        GameLobbyRuntime.broadcast_game_snapshot(game_id, state)
        {:reply, :ok, state}

      {:error, :rate_limited, state} ->
        {:reply, {:error, :rate_limited}, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:heartbeat, player_id, game_id}, state) do
    state = GameLifecycle.heartbeat(state, player_id, game_id, GameLobbyRuntime.now_ms())
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    tick_ms = GameRuntimeConfig.tick_ms()
    Process.send_after(self(), :tick, tick_ms)
    now = GameLobbyRuntime.now_ms()

    {next_state, changed_game_ids, lobby_update?} =
      GameLobbyTick.run(
        state,
        now,
        tick_ms,
        @rate_limit_retention_ms,
        &GameLobbyRuntime.public_game_at/2,
        &GameLobbyRuntime.public_lobby_at/2
      )

    next_state = GameLifecycle.maintain(next_state, now)

    changed_game_ids
    |> Enum.reverse()
    |> Enum.each(fn game_id ->
      GameLobbyRuntime.broadcast_game_update(next_state.games[game_id], now)
    end)

    if lobby_update? do
      GameLobbyRuntime.broadcast_lobby_payload(next_state, now)
    end

    {:noreply, next_state}
  end

  def topic(game_id), do: GameLobbyRuntime.game_topic(game_id)
  def lobby_topic, do: GameLobbyRuntime.lobby_topic()
end
