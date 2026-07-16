defmodule ManaChessOnline.GameLifecycle do
  @moduledoc false

  alias ManaChessOnline.{GameCapacity, GameLobbyServers, GamePlayers, GameRuntimeConfig}

  def heartbeat(state, player_id, game_id, now_ms) do
    assignment = GamePlayers.assignment(state, player_id)
    game = Map.get(state.games, game_id)

    if assigned_to?(assignment, game_id) or private_spectator?(game) do
      touch_game(state, game_id, now_ms)
    else
      state
    end
  end

  def touch_player(state, player_id, now_ms) do
    case GamePlayers.assignment(state, player_id) do
      %{game_id: game_id} -> touch_game(state, game_id, now_ms)
      _assignment -> state
    end
  end

  def touch_game(state, game_id, now_ms) when is_binary(game_id) and is_integer(now_ms) do
    if Map.has_key?(state.games, game_id) do
      Map.update(state, :game_activity, %{game_id => now_ms}, &Map.put(&1, game_id, now_ms))
    else
      state
    end
  end

  def touch_game(state, _game_id, _now_ms), do: state

  def forget_missing_games(state) do
    activity =
      state
      |> Map.get(:game_activity, %{})
      |> Map.take(Map.keys(state.games))

    Map.put(state, :game_activity, activity)
  end

  def maintain(state, now_ms) do
    last_maintenance = Map.get(state, :last_lifecycle_at, now_ms)

    if now_ms - last_maintenance >= GameRuntimeConfig.lifecycle_interval_ms() do
      state
      |> sync_live_games()
      |> seed_dynamic_activity(now_ms)
      |> remove_idle_dynamic_games(now_ms)
      |> Map.put(:last_lifecycle_at, now_ms)
      |> forget_missing_games()
    else
      state
    end
  end

  defp sync_live_games(state) do
    %{state | games: GameLobbyServers.server_backed_games(state.games)}
  end

  defp seed_dynamic_activity(state, now_ms) do
    activity = Map.get(state, :game_activity, %{})

    activity =
      Enum.reduce(state.games, activity, fn {game_id, game}, activity ->
        if GameCapacity.dynamic_game?(game) do
          Map.put_new(activity, game_id, now_ms)
        else
          activity
        end
      end)

    Map.put(state, :game_activity, activity)
  end

  defp remove_idle_dynamic_games(state, now_ms) do
    cutoff = now_ms - GameRuntimeConfig.dynamic_idle_ttl_ms()
    activity = Map.get(state, :game_activity, %{})

    stale_game_ids =
      state.games
      |> Enum.filter(fn {game_id, game} ->
        GameCapacity.dynamic_game?(game) and Map.get(activity, game_id, now_ms) <= cutoff
      end)
      |> Enum.map(&elem(&1, 0))

    Enum.each(stale_game_ids, &GameLobbyServers.stop_game_server/1)

    state
    |> Map.update!(:games, &Map.drop(&1, stale_game_ids))
    |> Map.update!(:players, fn players ->
      Map.reject(players, fn {_player_id, assignment} ->
        Map.get(assignment, :game_id) in stale_game_ids
      end)
    end)
    |> Map.update(:game_activity, %{}, &Map.drop(&1, stale_game_ids))
    |> record_cleanup(length(stale_game_ids))
  end

  defp record_cleanup(state, 0), do: state

  defp record_cleanup(state, count) do
    Map.update(
      state,
      :capacity_stats,
      %{rejected_count: 0, cleaned_count: count},
      &Map.update(&1, :cleaned_count, count, fn cleaned -> cleaned + count end)
    )
  end

  defp assigned_to?(%{game_id: game_id}, game_id) when is_binary(game_id), do: true
  defp assigned_to?(_assignment, _game_id), do: false
  defp private_spectator?(%{private?: true}), do: true
  defp private_spectator?(_game), do: false
end
