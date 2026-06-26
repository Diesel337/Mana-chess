defmodule ManaChessOnline.GameSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias ManaChessOnline.{GameRegistry, GameServer}

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  def start_game(game, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:game, game)
      |> Keyword.put_new(:id, {GameServer, game.id})
      |> Keyword.put_new(:name, GameRegistry.via(game.id))

    DynamicSupervisor.start_child(__MODULE__, {GameServer, opts})
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

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
