defmodule ManaChessOnline.GameLobbyServers do
  @moduledoc false

  alias ManaChessOnline.GameSupervisor

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

  def stop_game_server(game_id), do: GameSupervisor.stop_game(game_id)
end
