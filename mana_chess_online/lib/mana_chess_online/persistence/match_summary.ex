defmodule ManaChessOnline.Persistence.MatchSummary do
  use Ecto.Schema
  import Ecto.Changeset

  schema "match_summaries" do
    field(:event_id, Ecto.UUID)
    field(:game_id, :string)
    field(:mode, :string)
    field(:white_player_id, :string)
    field(:black_player_id, :string)
    field(:result, :string)
    field(:winner_color, :string)
    field(:finished_at, :utc_datetime_usec)
    field(:settings, :map, default: %{})
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :event_id,
      :game_id,
      :mode,
      :white_player_id,
      :black_player_id,
      :result,
      :winner_color,
      :finished_at,
      :settings,
      :metadata
    ])
    |> validate_required([:event_id, :game_id, :mode, :result, :finished_at])
    |> validate_inclusion(:mode, ["public", "private", "practice"])
    |> validate_inclusion(:result, ["white_win", "black_win", "draw"])
    |> validate_inclusion(:winner_color, ["white", "black"], allow_nil: true)
    |> validate_length(:game_id, max: 160)
    |> validate_length(:white_player_id, max: 160)
    |> validate_length(:black_player_id, max: 160)
    |> validate_result_winner()
    |> check_constraint(:mode, name: :match_summaries_mode_valid)
    |> check_constraint(:result, name: :match_summaries_result_valid)
    |> check_constraint(:winner_color, name: :match_summaries_winner_valid)
    |> unique_constraint(:event_id)
  end

  defp validate_result_winner(changeset) do
    case {get_field(changeset, :result), get_field(changeset, :winner_color)} do
      {"draw", nil} ->
        changeset

      {"white_win", "white"} ->
        changeset

      {"black_win", "black"} ->
        changeset

      {result, _winner} when result in ["draw", "white_win", "black_win"] ->
        add_error(changeset, :winner_color, "does not match result")

      {_result, _winner} ->
        changeset
    end
  end
end
