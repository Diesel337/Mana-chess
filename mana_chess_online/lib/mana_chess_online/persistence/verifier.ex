defmodule ManaChessOnline.Persistence.Verifier do
  @moduledoc """
  Read-only checks for a live or restored Mana Chess Postgres database.

  Reports schema state and aggregate row counts only. It never returns row
  contents, connection details, or database error messages.
  """

  @tables [
    "steam_users",
    "steam_entitlements",
    "match_summaries",
    "player_ratings",
    "system_settings"
  ]

  def verify(repo, opts \\ []) do
    query = Keyword.get(opts, :query, &Ecto.Adapters.SQL.query/4)
    migrations = Keyword.get(opts, :migrations, &Ecto.Migrator.migrations/1)
    checked_at = DateTime.utc_now() |> DateTime.to_iso8601()

    with :ok <- connectivity(repo, query),
         {:ok, migration_report} <- migration_report(repo, migrations),
         {:ok, table_counts} <- table_counts(repo, query) do
      {:ok,
       Map.merge(migration_report, %{
         checked_at: checked_at,
         ready: true,
         table_counts: table_counts
       })}
    else
      {:error, code} ->
        {:error, %{checked_at: checked_at, code: code, ready: false}}
    end
  rescue
    _error -> error_report("verification_exception")
  catch
    _kind, _reason -> error_report("verification_exit")
  end

  def expected_tables, do: @tables

  defp connectivity(repo, query) do
    case query.(repo, "SELECT 1", [], log: false, timeout: 15_000) do
      {:ok, %{rows: [[1]]}} -> :ok
      _result -> {:error, "database_unavailable"}
    end
  end

  defp migration_report(repo, migrations) do
    case migrations.(repo) do
      statuses when is_list(statuses) ->
        applied_count = Enum.count(statuses, &match?({:up, _version, _name}, &1))
        pending_count = Enum.count(statuses, &match?({:down, _version, _name}, &1))

        if pending_count == 0 do
          {:ok, %{applied_migration_count: applied_count, pending_migration_count: 0}}
        else
          {:error, "pending_migrations"}
        end

      _result ->
        {:error, "migration_status_unavailable"}
    end
  end

  defp table_counts(repo, query) do
    Enum.reduce_while(@tables, {:ok, %{}}, fn table, {:ok, counts} ->
      with :ok <- table_exists(repo, query, table),
           {:ok, count} <- row_count(repo, query, table) do
        {:cont, {:ok, Map.put(counts, table, count)}}
      else
        {:error, code} -> {:halt, {:error, code}}
      end
    end)
  end

  defp table_exists(repo, query, table) do
    case query.(repo, "SELECT to_regclass($1)::text", [table], log: false, timeout: 15_000) do
      {:ok, %{rows: [[value]]}} when is_binary(value) -> :ok
      {:ok, %{rows: [[nil]]}} -> {:error, "missing_table"}
      _result -> {:error, "table_check_failed"}
    end
  end

  defp row_count(repo, query, table) when table in @tables do
    sql = "SELECT COUNT(*)::bigint FROM " <> table

    case query.(repo, sql, [], log: false, timeout: 15_000) do
      {:ok, %{rows: [[count]]}} when is_integer(count) and count >= 0 -> {:ok, count}
      _result -> {:error, "table_count_failed"}
    end
  end

  defp error_report(code) do
    {:error,
     %{
       checked_at: DateTime.utc_now() |> DateTime.to_iso8601(),
       code: code,
       ready: false
     }}
  end
end
