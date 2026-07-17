defmodule ManaChessOnline.CompetitiveRatingTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.CompetitiveRating

  test "rates a provisional decisive result and updates both records" do
    result =
      CompetitiveRating.rate_pair(
        CompetitiveRating.default_profile("white"),
        CompetitiveRating.default_profile("black"),
        "white_win"
      )

    assert result.white.rating == 1_220
    assert result.black.rating == 1_180
    assert result.white_change == 20
    assert result.black_change == -20
    assert result.white.games_played == 1
    assert result.white.wins == 1
    assert result.black.losses == 1
  end

  test "an underdog gains rating from a draw" do
    white = %{CompetitiveRating.default_profile("white") | rating: 1_400}
    black = %{CompetitiveRating.default_profile("black") | rating: 1_200}

    result = CompetitiveRating.rate_pair(white, black, "draw")

    assert result.white.rating < 1_400
    assert result.black.rating > 1_200
    assert result.white.draws == 1
    assert result.black.draws == 1
    assert result.white_change == -result.black_change
  end

  test "only public games between two distinct players are rated" do
    summary = %{
      mode: "public",
      white_player_id: "white",
      black_player_id: "black",
      result: "draw"
    }

    assert CompetitiveRating.eligible_match?(summary)
    refute CompetitiveRating.eligible_match?(%{summary | mode: "private"})
    refute CompetitiveRating.eligible_match?(%{summary | black_player_id: "white"})
    refute CompetitiveRating.eligible_match?(%{summary | black_player_id: nil})
  end
end
