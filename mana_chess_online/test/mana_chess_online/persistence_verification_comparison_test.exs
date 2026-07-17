defmodule ManaChessOnline.Persistence.VerificationComparisonTest do
  use ExUnit.Case, async: true

  alias ManaChessOnline.Persistence.{VerificationComparison, Verifier}

  test "accepts matching aggregate reports" do
    baseline = report(%{"checked_at" => "2026-07-17T20:42:23Z"})
    recovery = report(%{"checked_at" => "2026-07-17T21:42:23Z"})

    assert {:ok, comparison} = VerificationComparison.compare(baseline, recovery)
    assert comparison.ready
    assert comparison.code == "reports_match"
    assert comparison.applied_migration_count == 2
    assert comparison.pending_migration_count == 0
    assert comparison.matched_table_count == 5
    assert comparison.table_counts == baseline["table_counts"]
  end

  test "reports only aggregate migration and table mismatches" do
    baseline =
      report(%{
        "database_url" => "postgres://private",
        "row_data" => [%{"steam_id" => "private-player"}]
      })

    recovery =
      report(%{
        "applied_migration_count" => 1,
        "table_counts" => Map.put(table_counts(), "player_ratings", 2)
      })

    assert {:error, comparison} = VerificationComparison.compare(baseline, recovery)
    refute comparison.ready
    assert comparison.code == "report_mismatch"
    assert comparison.mismatch_count == 2

    assert %{
             field: "applied_migration_count",
             baseline: 2,
             recovery: 1
           } in comparison.mismatches

    assert %{
             field: "table_count",
             table: "player_ratings",
             baseline: 0,
             recovery: 2
           } in comparison.mismatches

    refute inspect(comparison) =~ "postgres://"
    refute inspect(comparison) =~ "private-player"
  end

  test "rejects reports that are not successful verifier output" do
    recovery = report(%{"pending_migration_count" => 1})

    assert {:error, %{code: "invalid_recovery_report", ready: false}} =
             VerificationComparison.compare(report(), recovery)
  end

  test "reads UTF-8 BOM and PowerShell UTF-16 report files" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "mana-chess-restore-#{System.unique_integer([:positive])}"
      )

    baseline_path = Path.join(directory, "baseline.json")
    recovery_path = Path.join(directory, "recovery.json")
    File.mkdir_p!(directory)

    on_exit(fn -> File.rm_rf!(directory) end)

    json = Jason.encode!(report())
    utf16 = :unicode.characters_to_binary(json, :utf8, {:utf16, :little})

    File.write!(baseline_path, <<0xEF, 0xBB, 0xBF>> <> json)
    File.write!(recovery_path, <<0xFF, 0xFE>> <> utf16)

    assert {:ok, %{code: "reports_match"}} =
             VerificationComparison.compare_files(baseline_path, recovery_path)
  end

  test "release overlay invokes the aggregate comparison" do
    root = Path.expand("../..", __DIR__)
    script = File.read!(Path.join(root, "rel/overlays/bin/compare-persistence-reports"))
    dockerfile = File.read!(Path.join(root, "Dockerfile"))

    assert script =~ "ManaChessOnline.Release.compare_persistence_reports()"
    assert dockerfile =~ "/app/bin/compare-persistence-reports"
  end

  defp report(overrides \\ %{}) do
    Map.merge(
      %{
        "ready" => true,
        "checked_at" => "2026-07-17T20:42:23Z",
        "applied_migration_count" => 2,
        "pending_migration_count" => 0,
        "table_counts" => table_counts()
      },
      overrides
    )
  end

  defp table_counts do
    Map.new(Verifier.expected_tables(), &{&1, 0})
  end
end
