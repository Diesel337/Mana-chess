defmodule ManaChessOnline.GameLobbyServers do
  @moduledoc false

  alias ManaChessOnline.{GameServer, GameSupervisor}

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

  def stop_game_server(game_id), do: GameSupervisor.stop_game(game_id)
end
