defmodule ManaChessOnline.CompetitiveLeaderboardTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.CompetitiveLeaderboard

  test "publishes stable aliases without leaking player identifiers" do
    current_player_id = "steam_76561198000000001"

    leaderboard =
      CompetitiveLeaderboard.normalize(
        %{
          entries: [
            profile("private-player-one", 1, 1_420, 16, 10, 4, 2),
            profile("private-player-two", 2, 1_390, 8, 4, 3, 1)
          ],
          current: profile(current_player_id, 8, 1_215, 3, 1, 1, 1),
          total_players: 24
        },
        current_player_id
      )

    assert leaderboard.available?
    assert leaderboard.total_players == 24
    assert Enum.map(leaderboard.entries, & &1.rank) == [1, 2]
    assert Enum.all?(leaderboard.entries, &String.starts_with?(&1.name, "Jugador "))
    assert leaderboard.current.name == "Tu"
    assert leaderboard.current.rank == 8
    assert leaderboard.current.provisional?

    rendered = inspect(leaderboard)
    refute rendered =~ current_player_id
    refute rendered =~ "private-player-one"
    refute rendered =~ "private-player-two"
  end

  test "aliases are deterministic and compact" do
    alias_one = CompetitiveLeaderboard.alias_for("player-one")

    assert alias_one == CompetitiveLeaderboard.alias_for("player-one")
    assert alias_one != CompetitiveLeaderboard.alias_for("player-two")
    assert alias_one =~ ~r/^Jugador [0-9A-F]{8}$/
  end

  test "aliases are keyed and reject an empty effective secret" do
    first = CompetitiveLeaderboard.alias_for("player", "server-secret-one")
    second = CompetitiveLeaderboard.alias_for("player", "server-secret-two")

    assert first != second

    assert CompetitiveLeaderboard.alias_for("player", "") ==
             CompetitiveLeaderboard.alias_for("player", "mana-chess-local-leaderboard-v1")
  end

  test "returns a safe empty board for malformed payloads" do
    assert CompetitiveLeaderboard.normalize(nil, "player") == CompetitiveLeaderboard.default()

    leaderboard =
      CompetitiveLeaderboard.normalize(%{entries: [%{rank: 0}], total_players: -1}, "player")

    assert leaderboard.entries == []
    assert leaderboard.current == nil
    assert leaderboard.total_players == 0
  end

  defp profile(player_id, rank, rating, games, wins, losses, draws) do
    %{
      player_id: player_id,
      rank: rank,
      rating: rating,
      games_played: games,
      wins: wins,
      losses: losses,
      draws: draws
    }
  end
end
