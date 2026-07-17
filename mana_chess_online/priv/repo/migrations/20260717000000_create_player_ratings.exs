defmodule ManaChessOnline.Repo.Migrations.CreatePlayerRatings do
  use Ecto.Migration

  def change do
    create table(:player_ratings) do
      add(:player_id, :string, null: false)
      add(:rating, :integer, null: false, default: 1_200)
      add(:games_played, :integer, null: false, default: 0)
      add(:wins, :integer, null: false, default: 0)
      add(:losses, :integer, null: false, default: 0)
      add(:draws, :integer, null: false, default: 0)
      add(:last_match_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:player_ratings, [:player_id]))
    create(index(:player_ratings, [:rating, :games_played]))

    create(
      constraint(:player_ratings, :player_ratings_rating_valid,
        check: "rating >= 100 AND rating <= 4000"
      )
    )

    create(
      constraint(:player_ratings, :player_ratings_counts_valid,
        check: "games_played >= 0 AND wins >= 0 AND losses >= 0 AND draws >= 0"
      )
    )

    create(
      constraint(:player_ratings, :player_ratings_total_valid,
        check: "games_played = wins + losses + draws"
      )
    )
  end
end
