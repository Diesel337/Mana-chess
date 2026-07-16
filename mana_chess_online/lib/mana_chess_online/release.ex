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

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    case Application.load(@app) do
      :ok -> :ok
      {:error, {:already_loaded, @app}} -> :ok
    end
  end
end
