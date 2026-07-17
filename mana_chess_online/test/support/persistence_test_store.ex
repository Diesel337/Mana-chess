defmodule ManaChessOnline.PersistenceTestStore do
  @behaviour ManaChessOnline.Persistence.Store

  @impl true
  def persist(event) do
    notify({:persistence_store_event, event})
    Application.get_env(:mana_chess_online, :persistence_test_result, :ok)
  end

  @impl true
  def get_setting(key) do
    case Application.get_env(:mana_chess_online, :persistence_test_settings, %{}) do
      %{^key => value} -> {:ok, value}
      _settings -> {:error, :not_found}
    end
  end

  @impl true
  def entitlements_for(steam_id) do
    notify({:persistence_entitlements_read, steam_id})
    {:ok, Application.get_env(:mana_chess_online, :persistence_test_entitlements, [])}
  end

  @impl true
  def competitive_profile(player_id) do
    notify({:persistence_competitive_profile_read, player_id})

    {:ok,
     Application.get_env(
       :mana_chess_online,
       :persistence_test_competitive_profile,
       ManaChessOnline.CompetitiveRating.default_profile(player_id)
     )}
  end

  @impl true
  def competitive_leaderboard(player_id, limit) do
    notify({:persistence_competitive_leaderboard_read, player_id, limit})

    {:ok,
     Application.get_env(:mana_chess_online, :persistence_test_competitive_leaderboard, %{
       entries: [],
       current: nil,
       total_players: 0
     })}
  end

  @impl true
  def health, do: Application.get_env(:mana_chess_online, :persistence_test_health, :ok)

  defp notify(message) do
    case Application.get_env(:mana_chess_online, :persistence_test_pid) do
      pid when is_pid(pid) -> send(pid, message)
      _pid -> :ok
    end
  end
end

defmodule ManaChessOnline.PersistenceTestWriter do
  def record(event) do
    case Application.get_env(:mana_chess_online, :persistence_test_pid) do
      pid when is_pid(pid) -> send(pid, {:persistence_writer_event, event})
      _pid -> :ok
    end

    :ok
  end
end
