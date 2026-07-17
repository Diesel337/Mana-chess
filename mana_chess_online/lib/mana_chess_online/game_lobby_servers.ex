defmodule ManaChessOnline.GameLobbyServers do
  @moduledoc false

  alias ManaChessOnline.{GameDirectory, GameServer, GameSettings, GameSupervisor, GameTick}
  alias ManaChessOnline.Operations.EventLog

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
        case GameSupervisor.start_or_lookup_game(game) do
          {:ok, _pid} ->
            :ok

          _error ->
            report_recovery_failure("sync")
            :ok
        end
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

  def assigned_game(%{game_id: game_id}, fallback_games) when is_binary(game_id),
    do: game_snapshot(game_id, fallback_games)

  def assigned_game(_assignment, _fallback_games), do: nil

  def sync_assignment_game(assignment, fallback_games) do
    assignment
    |> assigned_game(fallback_games)
    |> sync_game_server()
  end

  def server_backed_games(games), do: Map.merge(games, GameSupervisor.game_snapshots())

  def refresh_public_games(games) do
    games
    |> GameDirectory.public_games()
    |> Enum.reduce(games, fn {game_id, _game}, refreshed_games ->
      case game_snapshot(game_id, games) do
        nil -> refreshed_games
        live_game -> Map.put(refreshed_games, game_id, live_game)
      end
    end)
  end

  def replace_game_state(game) do
    case GameSupervisor.upsert_game(game) do
      {:ok, pid} ->
        GameServer.snapshot(pid)

      _error ->
        report_recovery_failure("replace")
        game
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
        report_recovery("tick")

        case GameSupervisor.start_or_lookup_game(game) do
          {:ok, pid} ->
            GameServer.tick(pid, now)

          _error ->
            report_recovery_failure("tick")
            GameTick.tick(game, now, tick_ms, GameSettings.default_cooldown_seconds())
        end
    end
  end

  def stop_game_server(game_id), do: GameSupervisor.stop_game(game_id)

  defp enqueue_unregistered_action(game, action, now) do
    report_recovery("enqueue")

    case GameSupervisor.start_or_lookup_game(game) do
      {:ok, pid} ->
        GameServer.enqueue(pid, action, now)

      _error ->
        report_recovery_failure("enqueue")
        enqueue_local_action(game, action, now)
    end
  end

  defp enqueue_local_action(game, action, now) do
    game
    |> Map.update!(:queue, &(&1 ++ [action]))
    |> GameTick.after_bot(now, GameSettings.default_cooldown_seconds())
  end

  defp update_unregistered_state(game, fun) do
    report_recovery("update")

    case GameSupervisor.start_or_lookup_game(game) do
      {:ok, pid} ->
        GameServer.update(pid, fun)

      _error ->
        report_recovery_failure("update")
        fun.(game)
    end
  end

  defp report_recovery(operation) do
    EventLog.report(:warning, "game_server_recovered", %{
      code: operation,
      component: "game_server"
    })
  end

  defp report_recovery_failure(operation) do
    EventLog.report(:error, "game_server_recovery_failed", %{
      code: operation,
      component: "game_server"
    })
  end
end
