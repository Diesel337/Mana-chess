defmodule Mix.Tasks.ManaChess.ComparePersistenceReports do
  use Mix.Task

  alias ManaChessOnline.Persistence.VerificationComparison

  @shortdoc "Compares aggregate baseline and restored Postgres reports"

  @impl Mix.Task
  def run([baseline_path, recovery_path]) do
    case VerificationComparison.compare_files(baseline_path, recovery_path) do
      {:ok, report} ->
        Mix.shell().info(Jason.encode!(report))

      {:error, report} ->
        Mix.raise(Jason.encode!(report))
    end
  end

  def run(_args) do
    Mix.raise("usage: mix mana_chess.compare_persistence_reports BASELINE_JSON RECOVERY_JSON")
  end
end
