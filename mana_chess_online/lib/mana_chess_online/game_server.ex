defmodule ManaChessOnline.GameServer do
  @moduledoc false

  use GenServer

  alias ManaChessOnline.{GamePersistence, GameTick}

  @default_tick_ms 250
  @default_cooldown_seconds 1.0

  def child_spec(opts) do
    game = Keyword.get(opts, :game)
    game_id = if is_map(game), do: Map.get(game, :id), else: Keyword.get(opts, :game_id)

    %{
      id: Keyword.get(opts, :id, {__MODULE__, game_id}),
      start: {__MODULE__, :start_link, [opts]},
      restart: Keyword.get(opts, :restart, :temporary)
    }
  end

  def start_link(opts) do
    name_opts =
      case Keyword.get(opts, :name) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, name_opts)
  end

  def snapshot(server), do: GenServer.call(server, :snapshot)
  def replace(server, game), do: GenServer.call(server, {:replace, game})
  def update(server, fun) when is_function(fun, 1), do: GenServer.call(server, {:update, fun})

  def enqueue(server, action, now_ms \\ nil),
    do: GenServer.call(server, {:enqueue, action, now_ms})

  def tick(server, now_ms \\ nil), do: GenServer.call(server, {:tick, now_ms})

  @impl true
  def init(opts) do
    {:ok,
     %{
       game: Keyword.fetch!(opts, :game),
       tick_ms: Keyword.get(opts, :tick_ms, @default_tick_ms),
       default_cooldown_seconds:
         Keyword.get(opts, :default_cooldown_seconds, @default_cooldown_seconds),
       observer: Keyword.get(opts, :observer, &GamePersistence.observe/2),
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state.game, state}

  def handle_call({:replace, game}, _from, state) do
    {:reply, game, commit_game(state, game)}
  end

  def handle_call({:update, fun}, _from, state) do
    game = fun.(state.game)
    {:reply, game, commit_game(state, game)}
  end

  def handle_call({:enqueue, action, now_ms}, _from, state) do
    now_ms = now_ms(state, now_ms)

    game =
      state.game
      |> Map.update!(:queue, &(&1 ++ [action]))
      |> GameTick.after_bot(now_ms, state.default_cooldown_seconds)

    {:reply, game, commit_game(state, game)}
  end

  def handle_call({:tick, now_ms}, _from, state) do
    now_ms = now_ms(state, now_ms)

    game = GameTick.tick(state.game, now_ms, state.tick_ms, state.default_cooldown_seconds)

    {:reply, game, commit_game(state, game)}
  end

  defp commit_game(state, game) do
    observe(state.observer, state.game, game)
    %{state | game: game}
  end

  defp observe(observer, previous_game, next_game) do
    try do
      observer.(previous_game, next_game)
    rescue
      _error -> :ok
    catch
      _kind, _reason -> :ok
    end
  end

  defp now_ms(%{clock: clock}, nil), do: clock.()
  defp now_ms(_state, now_ms) when is_integer(now_ms), do: now_ms
end
