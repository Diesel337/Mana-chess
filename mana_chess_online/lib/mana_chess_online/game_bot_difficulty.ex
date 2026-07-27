defmodule ManaChessOnline.GameBotDifficulty do
  @moduledoc false

  @levels [:apprentice, :normal, :expert]

  @profiles %{
    apprentice: %{
      label: "Aprendiz",
      description: "Decide rapido y deja oportunidades.",
      search_depth: 2,
      branch_limit: 5,
      root_branch_limit: 9,
      choice_pool: 3,
      positional_weight: 0,
      resource_weight: 4,
      delay_multiplier: 0.75
    },
    normal: %{
      label: "Normal",
      description: "Equilibrado para partidas casuales.",
      search_depth: 4,
      branch_limit: 8,
      root_branch_limit: 12,
      choice_pool: 1,
      positional_weight: 1,
      resource_weight: 8,
      delay_multiplier: 1.0
    },
    expert: %{
      label: "Experto",
      description: "Calcula mas y protege sus recursos.",
      search_depth: 5,
      branch_limit: 8,
      root_branch_limit: 14,
      choice_pool: 1,
      positional_weight: 2,
      resource_weight: 14,
      delay_multiplier: 1.35
    }
  }

  def levels, do: @levels

  def profile(level), do: Map.fetch!(@profiles, normalize(level))

  def label(level), do: profile(level).label
  def description(level), do: profile(level).description

  def normalize(level) when level in @levels, do: level
  def normalize("apprentice"), do: :apprentice
  def normalize("normal"), do: :normal
  def normalize("expert"), do: :expert
  def normalize(_level), do: :normal

  def parse(level) when level in @levels, do: {:ok, level}
  def parse("apprentice"), do: {:ok, :apprentice}
  def parse("normal"), do: {:ok, :normal}
  def parse("expert"), do: {:ok, :expert}
  def parse(_level), do: :error
end
