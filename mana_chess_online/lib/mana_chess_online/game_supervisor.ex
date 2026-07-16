defmodule ManaChessOnline.GameSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ManaChessOnline.{GameRegistry, GameRuntimeConfig, GameServer, GameServerRuntime}

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_game(game, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:game, game)
      |> Keyword.put_new(:tick_ms, GameRuntimeConfig.tick_ms())
      |> Keyword.put_new(:auto_tick, GameRuntimeConfig.auto_tick?())
      |> Keyword.put_new(:tick_observer, &GameServerRuntime.after_tick/3)
      |> Keyword.put_new(
        :initial_tick_delay_ms,
        GameRuntimeConfig.initial_tick_delay_ms(
          game.id,
          Keyword.get(opts, :tick_ms, GameRuntimeConfig.tick_ms())
        )
      )
      |> Keyword.put_new(:id, {GameServer, game.id})
      |> Keyword.put_new(:name, GameRegistry.via(game.id))

    DynamicSupervisor.start_child(__MODULE__, {GameServer, opts})
  end

  def start_or_lookup_game(game) do
    case start_game(game) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def upsert_game(game) do
    case lookup_game(game.id) do
      {:ok, pid} ->
        GameServer.replace(pid, game)
        {:ok, pid}

      :error ->
        case start_game(game) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            GameServer.replace(pid, game)
            {:ok, pid}

          error ->
            error
        end
    end
  end

  def stop_game(game_id) do
    case lookup_game(game_id) do
      {:ok, pid} ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
        wait_until_unregistered(game_id, 10)

      :error ->
        :ok
    end
  end

  def lookup_game(game_id), do: GameRegistry.lookup(game_id)
  def game_pid(game_id), do: GameRegistry.whereis(game_id)

  def child_count, do: DynamicSupervisor.count_children(__MODULE__)

  def game_snapshots do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.reduce(%{}, fn
      {_id, pid, :worker, _modules}, games when is_pid(pid) ->
        case safe_game_snapshot(pid) do
          %{id: game_id} = game when is_binary(game_id) -> Map.put(games, game_id, game)
          _game -> games
        end

      _child, games ->
        games
    end)
  end

  defp wait_until_unregistered(_game_id, 0), do: :ok

  defp wait_until_unregistered(game_id, attempts) do
    case lookup_game(game_id) do
      :error ->
        :ok

      {:ok, _pid} ->
        Process.sleep(10)
        wait_until_unregistered(game_id, attempts - 1)
    end
  end

  defp safe_game_snapshot(pid) do
    try do
      GameServer.snapshot(pid)
    catch
      :exit, _reason -> nil
    end
  end

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
