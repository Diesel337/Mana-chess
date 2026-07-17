defmodule ManaChessOnline.Release do
  @moduledoc false

  @app :mana_chess_online

  def migrate do
    load_app()

    if ManaChessOnline.Persistence.enabled?() do
      Enum.each(repos(), fn repo ->
        {:ok, _migrations, _apps} =
          Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
      end)

      IO.puts("Mana Chess database migrations are current.")
    else
      IO.puts("Mana Chess persistence is disabled; database migration skipped.")
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _migration, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def verify_persistence do
    load_app()

    if ManaChessOnline.Persistence.enabled?() do
      Enum.each(repos(), &verify_repo/1)
    else
      raise "Mana Chess persistence verification requires Postgres mode"
    end
  end

  def compare_persistence_reports do
    load_app()

    with {:ok, baseline_path} <- report_path("MANA_CHESS_PERSISTENCE_BASELINE_REPORT"),
         {:ok, recovery_path} <- report_path("MANA_CHESS_PERSISTENCE_RECOVERY_REPORT") do
      case ManaChessOnline.Persistence.VerificationComparison.compare_files(
             baseline_path,
             recovery_path
           ) do
        {:ok, report} ->
          report |> Jason.encode!() |> IO.puts()

        {:error, report} ->
          raise "Mana Chess persistence report comparison failed code=#{report.code}"
      end
    else
      {:error, code} ->
        raise "Mana Chess persistence report comparison could not start code=#{code}"
    end
  end

  defp verify_repo(repo) do
    result = with_repo(repo)

    case result do
      {:ok, {:ok, report}, _apps} ->
        report
        |> Map.put(:repo, inspect(repo))
        |> Jason.encode!()
        |> IO.puts()

      {:ok, {:error, report}, _apps} ->
        raise "Mana Chess persistence verification failed code=#{report.code}"

      {:error, reason} ->
        raise "Mana Chess persistence verification could not start repo: #{sanitized_reason(reason)}"
    end
  end

  defp with_repo(repo) do
    Ecto.Migrator.with_repo(repo, fn started_repo ->
      ManaChessOnline.Persistence.Verifier.verify(started_repo)
    end)
  rescue
    _error -> {:error, :repo_unavailable}
  catch
    _kind, _reason -> {:error, :repo_unavailable}
  end

  defp sanitized_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp sanitized_reason(_reason), do: "repo_unavailable"

  defp report_path(name) do
    case System.get_env(name, "") |> String.trim() do
      "" -> {:error, "missing_report_path"}
      path -> {:ok, path}
    end
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
    end
  end
end
