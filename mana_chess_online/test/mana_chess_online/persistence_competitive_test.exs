defmodule ManaChessOnline.PersistenceCompetitiveTest do
  use ExUnit.Case, async: false

  alias ManaChessOnline.Persistence

  setup do
    original_config = Application.get_env(:mana_chess_online, :persistence)

    original_profile =
      Application.get_env(:mana_chess_online, :persistence_test_competitive_profile)

    original_leaderboard =
      Application.get_env(:mana_chess_online, :persistence_test_competitive_leaderboard)

    original_pid = Application.get_env(:mana_chess_online, :persistence_test_pid)

    on_exit(fn ->
      restore_env(:persistence, original_config)
      restore_env(:persistence_test_competitive_profile, original_profile)
      restore_env(:persistence_test_competitive_leaderboard, original_leaderboard)
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

  test "reads a bounded leaderboard and strips private player identifiers" do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: true,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    Application.put_env(:mana_chess_online, :persistence_test_pid, self())

    Application.put_env(:mana_chess_online, :persistence_test_competitive_leaderboard, %{
      entries: [
        %{
          player_id: "leader-private-id",
          rank: 1,
          rating: 1_410,
          games_played: 12,
          wins: 8,
          losses: 3,
          draws: 1
        }
      ],
      current: %{
        player_id: "current-private-id",
        rank: 9,
        rating: 1_220,
        games_played: 2,
        wins: 1,
        losses: 1,
        draws: 0
      },
      total_players: 18
    })

    leaderboard = Persistence.competitive_leaderboard("current-private-id", 99)

    assert_receive {:persistence_competitive_leaderboard_read, "current-private-id", 10}
    assert leaderboard.available?
    assert leaderboard.total_players == 18
    assert leaderboard.current.rank == 9
    assert leaderboard.current.name == "Tu"
    refute inspect(leaderboard) =~ "private-id"
  end

  test "returns an unavailable empty leaderboard without persistence" do
    Application.put_env(:mana_chess_online, :persistence,
      enabled: false,
      store: ManaChessOnline.PersistenceTestStore,
      writer: ManaChessOnline.PersistenceTestWriter
    )

    leaderboard = Persistence.competitive_leaderboard("new-player")

    refute leaderboard.available?
    assert leaderboard.entries == []
    assert leaderboard.current == nil
    assert leaderboard.total_players == 0
  end

  defp restore_env(key, nil), do: Application.delete_env(:mana_chess_online, key)
  defp restore_env(key, value), do: Application.put_env(:mana_chess_online, key, value)
end
