defmodule ManaChessOnline.Persistence.VerifierTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Persistence.Verifier

  test "verifies migrations and returns aggregate counts without row contents" do
    counts =
      Verifier.expected_tables()
      |> Enum.with_index(1)
      |> Map.new()

    assert {:ok, report} =
             Verifier.verify(:repo,
               query: successful_query(counts),
               migrations: fn :repo ->
                 [
                   {:up, 20_260_716_000_000, "create persistence foundation"},
                   {:up, 20_260_717_000_000, "create player ratings"}
                 ]
               end
             )

    assert report.ready
    assert report.applied_migration_count == 2
    assert report.pending_migration_count == 0
    assert report.table_counts == counts
    refute inspect(report) =~ "player-row"
  end

  test "fails closed when a migration is pending" do
    assert {:error, report} =
             Verifier.verify(:repo,
               query: successful_query(%{}),
               migrations: fn :repo ->
                 [{:down, 20_260_717_000_000, "create player ratings"}]
               end
             )

    refute report.ready
    assert report.code == "pending_migrations"
  end

  test "reports a missing table without returning database details" do
    missing_table = "steam_entitlements"

    query = fn _repo, sql, params, _opts ->
      cond do
        sql == "SELECT 1" ->
          {:ok, %{rows: [[1]]}}

        sql == "SELECT to_regclass($1)::text" and params == [missing_table] ->
          {:ok, %{rows: [[nil]]}}

        sql == "SELECT to_regclass($1)::text" ->
          {:ok, %{rows: [[List.first(params)]]}}

        String.starts_with?(sql, "SELECT COUNT(*)") ->
          {:ok, %{rows: [[0]]}}
      end
    end

    assert {:error, report} =
             Verifier.verify(:repo,
               query: query,
               migrations: fn :repo -> [] end
             )

    refute report.ready
    assert report.code == "missing_table"
    refute inspect(report) =~ "postgres://"
  end

  test "release overlay invokes the read-only verifier" do
    root = Path.expand("../..", __DIR__)
    script = File.read!(Path.join(root, "rel/overlays/bin/verify-persistence"))
    dockerfile = File.read!(Path.join(root, "Dockerfile"))

    assert script =~ "ManaChessOnline.Release.verify_persistence()"
    assert dockerfile =~ "/app/bin/verify-persistence"
  end

  defp successful_query(counts) do
    fn _repo, sql, params, _opts ->
      cond do
        sql == "SELECT 1" ->
          {:ok, %{rows: [[1]]}}

        sql == "SELECT to_regclass($1)::text" ->
          {:ok, %{rows: [[List.first(params)]]}}

        String.starts_with?(sql, "SELECT COUNT(*)::bigint FROM ") ->
          table = String.replace_prefix(sql, "SELECT COUNT(*)::bigint FROM ", "")
          {:ok, %{rows: [[Map.get(counts, table, 0)]]}}
      end
    end
  end
end
