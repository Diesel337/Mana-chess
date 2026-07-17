defmodule ManaChessOnline.GameCapacity do
  @moduledoc false

  alias ManaChessOnline.{GameLobbyServers, GamePlayers, GameRooms, GameRuntimeConfig}

  def dynamic_game?(%{practice?: true}), do: true

  def dynamic_game?(game) do
    Map.get(game, :private?, false) == true or Map.get(game, :matchmaking?, false) == true
  end

  def dynamic_game_count(games) when is_map(games) do
    Enum.count(games, fn {_game_id, game} -> dynamic_game?(game) end)
  end

  def available?(state) do
    state
    |> live_games()
    |> dynamic_game_count()
    |> Kernel.<(GameRuntimeConfig.max_dynamic_games())
  end

  def available_after_leaving?(state, player_id) do
    available?(state) or leaving_releases_dynamic_game?(state, player_id)
  end

  def record_rejection(state) do
    Map.update(
      state,
      :capacity_stats,
      %{rejected_count: 1, cleaned_count: 0},
      &Map.update(&1, :rejected_count, 1, fn count -> count + 1 end)
    )
  end

  def snapshot(state) do
    games = live_games(state)
    dynamic_count = dynamic_game_count(games)
    stats = Map.get(state, :capacity_stats, %{})
    maximum = GameRuntimeConfig.max_dynamic_games()

    %{
      dynamic_game_count: dynamic_count,
      max_dynamic_games: maximum,
      dynamic_capacity_available: max(maximum - dynamic_count, 0),
      capacity_rejected_count: Map.get(stats, :rejected_count, 0),
      cleaned_dynamic_game_count: Map.get(stats, :cleaned_count, 0)
    }
  end

  defp leaving_releases_dynamic_game?(state, player_id) do
    with %{game_id: game_id} <- GamePlayers.assignment(state, player_id),
         game when not is_nil(game) <- GameLobbyServers.game_snapshot(game_id, state.games),
         true <- dynamic_game?(game) do
      releasable_by?(game, player_id)
    else
      _error -> false
    end
  end

  defp releasable_by?(%{practice?: true}, _player_id), do: true

  defp releasable_by?(%{matchmaking?: true} = game, player_id) do
    case GameRooms.seated_players(game) do
      [^player_id] -> true
      _players -> false
    end
  end

  defp releasable_by?(%{private?: true} = game, player_id) do
    case GameRooms.seated_players(game) do
      [^player_id] -> true
      _players -> false
    end
  end

  defp releasable_by?(_game, _player_id), do: false

  defp live_games(%{games: games}), do: GameLobbyServers.server_backed_games(games)
end
