defmodule ManaChessOnline.PersistenceCompetitiveTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.Persistence

  setup do
    original_config = Application.get_env(:mana_chess_online, :persistence)

    original_profile =
      Application.get_env(:mana_chess_online, :persistence_test_competitive_profile)

    original_pid = Application.get_env(:mana_chess_online, :persistence_test_pid)

    on_exit(fn ->
      restore_env(:persistence, original_config)
      restore_env(:persistence_test_competitive_profile, original_profile)
      restore_env(:persistence_test_pid, original_pid)
    end)

    :ok
  end

  test "reads and normalizes the persistent competitive profile" do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_pid, self())

    Application.put_env(:mana_chess_online, :persistence_test_competitive_profile, %{
      rating: 1_337,
      games_played: 12,
      wins: 7,
      losses: 3,
      draws: 2
    })

    profile = Persistence.competitive_profile("rated-player")

    assert_receive {:persistence_competitive_profile_read, "rated-player"}
    assert profile.rating == 1_337
    assert profile.games_played == 12
    assert profile.available?
    refute profile.provisional?
  end

  test "returns a safe provisional profile when persistence is disabled" do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: false,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    profile = Persistence.competitive_profile("new-player")

    assert profile.rating == 1_200
    assert profile.games_played == 0
    assert profile.provisional?
    refute profile.available?
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
