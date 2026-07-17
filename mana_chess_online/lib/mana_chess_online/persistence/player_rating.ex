defmodule ManaChessOnline.Persistence.PlayerRating do
  use Ecto.Schema
  import Ecto.Changeset

  schema "player_ratings" do
    field(:player_id, :string)
    field(:rating, :integer, default: 1_200)
    field(:games_played, :integer, default: 0)
    field(:wins, :integer, default: 0)
    field(:losses, :integer, default: 0)
    field(:draws, :integer, default: 0)
    field(:last_match_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(player_rating, attrs) do
    player_rating
    |> cast(attrs, [
      :player_id,
      :rating,
      :games_played,
      :wins,
      :losses,
      :draws,
      :last_match_at
    ])
    |> validate_required([:player_id, :rating, :games_played, :wins, :losses, :draws])
    |> validate_length(:player_id, min: 1, max: 160)
    |> validate_number(:rating, greater_than_or_equal_to: 100, less_than_or_equal_to: 4_000)
    |> validate_number(:games_played, greater_than_or_equal_to: 0)
    |> validate_number(:wins, greater_than_or_equal_to: 0)
    |> validate_number(:losses, greater_than_or_equal_to: 0)
    |> validate_number(:draws, greater_than_or_equal_to: 0)
    |> validate_record_total()
    |> check_constraint(:rating, name: :player_ratings_rating_valid)
    |> check_constraint(:games_played, name: :player_ratings_counts_valid)
    |> check_constraint(:games_played, name: :player_ratings_total_valid)
    |> unique_constraint(:player_id)
  end

  defp validate_record_total(changeset) do
    games_played = get_field(changeset, :games_played)
    wins = get_field(changeset, :wins)
    losses = get_field(changeset, :losses)
    draws = get_field(changeset, :draws)

    if Enum.all?([games_played, wins, losses, draws], &is_integer/1) and
         games_played != wins + losses + draws do
      add_error(changeset, :games_played, "must equal wins, losses, and draws")
    else
      changeset
    end
  end
end
