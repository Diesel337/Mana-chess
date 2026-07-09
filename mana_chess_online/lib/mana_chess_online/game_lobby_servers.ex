defmodule ManaChessOnline.GameLobbyServers do
  @moduledoc false

  alias ManaChessOnline.{GameServer, GameSettings, GameSupervisor, GameTick}

  def sync_game_servers(games) do
    Enum.each(games, fn {_game_id, game} -> sync_game_server(game) end)
    :ok
  end

  def sync_game_server(nil), do: :ok

  def sync_game_server(game) do
    case GameSupervisor.lookup_game(game.id) do
      {:ok, _pid} ->
        :ok

      :error ->
        GameSupervisor.start_or_lookup_game(game)
        :ok
    end
  end

  def game_server_pids(games) do
    games
    |> Map.keys()
    |> Enum.flat_map(fn game_id ->
      case GameSupervisor.lookup_game(game_id) do
        {:ok, pid} -> [pid]
        :error -> []
      end
    end)
  end

  def game_snapshot(game_id, fallback_games) when is_binary(game_id) do
    case GameSupervisor.lookup_game(game_id) do
      {:ok, pid} -> GameServer.snapshot(pid)
      :error -> fallback_games[game_id]
    end
  end

  def game_snapshot(_game_id, _fallback_games), do: nil

  def server_backed_games(games), do: Map.merge(games, GameSupervisor.game_snapshots())

  def replace_game_state(game) do
    case GameSupervisor.upsert_game(game) do
      {:ok, pid} -> GameServer.snapshot(pid)
      _error -> game
    end
  end

  def enqueue_action(%{id: game_id} = game, action, now) do
    case GameSupervisor.lookup_game(game_id) do
      {:ok, pid} -> GameServer.enqueue(pid, action, now)
      :error -> enqueue_unregistered_action(game, action, now)
    end
  end

  def enqueue_action(game, action, now), do: enqueue_local_action(game, action, now)

  def update_state(%{id: game_id} = game, fun) when is_function(fun, 1) do
    case GameSupervisor.lookup_game(game_id) do
      {:ok, pid} -> GameServer.update(pid, fun)
      :error -> update_unregistered_state(game, fun)
    end
  end

  def update_state(game, fun) when is_function(fun, 1), do: fun.(game)

  def tick_game(game, now, tick_ms) do
    case GameSupervisor.lookup_game(game.id) do
      {:ok, pid} ->
        GameServer.tick(pid, now)

      :error ->
        case GameSupervisor.start_or_lookup_game(game) do
          {:ok, pid} -> GameServer.tick(pid, now)
          _error -> GameTick.tick(game, now, tick_ms, GameSettings.default_cooldown_seconds())
        end
    end
  end

  def stop_game_server(game_id), do: GameSupervisor.stop_game(game_id)

  defp enqueue_unregistered_action(game, action, now) do
    case GameSupervisor.start_or_lookup_game(game) do
      {:ok, pid} -> GameServer.enqueue(pid, action, now)
      _error -> enqueue_local_action(game, action, now)
    end
  end

  defp enqueue_local_action(game, action, now) do
    game
    |> Map.update!(:queue, &(&1 ++ [action]))
    |> GameTick.after_bot(now, GameSettings.default_cooldown_seconds())
  end

  defp update_unregistered_state(game, fun) do
    case GameSupervisor.start_or_lookup_game(game) do
      {:ok, pid} -> GameServer.update(pid, fun)
      _error -> fun.(game)
    end
  end
end
