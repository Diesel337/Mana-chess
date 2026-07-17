defmodule ManaChessOnline.Persistence.VerificationComparison do
  @moduledoc """
  Compares aggregate persistence reports captured before and after a restore.

  Only migration counts, expected table counts, and timestamps are accepted.
  File paths, database URLs, row contents, and arbitrary report fields are
  never returned in a comparison result.
  """

  alias ManaChessOnline.Persistence.Verifier

  def compare_files(baseline_path, recovery_path)
      when is_binary(baseline_path) and is_binary(recovery_path) do
    with {:ok, baseline} <- read_report(baseline_path, "baseline_report_unreadable"),
         {:ok, recovery} <- read_report(recovery_path, "recovery_report_unreadable") do
      compare(baseline, recovery)
    else
      {:error, code} -> error(code)
    end
  end

  def compare_files(_baseline_path, _recovery_path), do: error("invalid_report_paths")

  def compare(baseline, recovery) when is_map(baseline) and is_map(recovery) do
    with {:ok, baseline} <- normalize_report(baseline, "invalid_baseline_report"),
         {:ok, recovery} <- normalize_report(recovery, "invalid_recovery_report") do
      mismatches = mismatches(baseline, recovery)

      if mismatches == [] do
        {:ok,
         %{
           ready: true,
           code: "reports_match",
           applied_migration_count: baseline.applied_migration_count,
           pending_migration_count: 0,
           matched_table_count: map_size(baseline.table_counts),
           table_counts: baseline.table_counts,
           baseline_checked_at: baseline.checked_at,
           recovery_checked_at: recovery.checked_at
         }}
      else
        {:error,
         %{
           ready: false,
           code: "report_mismatch",
           mismatch_count: length(mismatches),
           mismatches: mismatches,
           baseline_checked_at: baseline.checked_at,
           recovery_checked_at: recovery.checked_at
         }}
      end
    else
      {:error, code} -> error(code)
    end
  end

  def compare(_baseline, _recovery), do: error("invalid_reports")

  defp read_report(path, error_code) do
    with {:ok, contents} <- File.read(path),
         {:ok, contents} <- normalize_encoding(contents),
         {:ok, report} when is_map(report) <- Jason.decode(contents) do
      {:ok, report}
    else
      _error -> {:error, error_code}
    end
  rescue
    _error -> {:error, error_code}
  catch
    _kind, _reason -> {:error, error_code}
  end

  defp normalize_encoding(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: {:ok, rest}

  defp normalize_encoding(<<0xFF, 0xFE, rest::binary>>),
    do: transcode(rest, {:utf16, :little})

  defp normalize_encoding(<<0xFE, 0xFF, rest::binary>>),
    do: transcode(rest, {:utf16, :big})

  defp normalize_encoding(contents) when is_binary(contents), do: {:ok, contents}

  defp transcode(contents, encoding) do
    case :unicode.characters_to_binary(contents, encoding, :utf8) do
      result when is_binary(result) -> {:ok, result}
      _result -> {:error, "invalid_report_encoding"}
    end
  end

  defp normalize_report(report, error_code) do
    with true <- field(report, :ready) == true,
         applied when is_integer(applied) and applied >= 0 <-
           field(report, :applied_migration_count),
         0 <- field(report, :pending_migration_count),
         counts when is_map(counts) <- field(report, :table_counts),
         {:ok, counts} <- normalize_counts(counts) do
      {:ok,
       %{
         applied_migration_count: applied,
         checked_at: normalize_timestamp(field(report, :checked_at)),
         table_counts: counts
       }}
    else
      _error -> {:error, error_code}
    end
  end

  defp normalize_counts(counts) do
    Enum.reduce_while(Verifier.expected_tables(), {:ok, %{}}, fn table, {:ok, normalized} ->
      case field(counts, table) do
        count when is_integer(count) and count >= 0 ->
          {:cont, {:ok, Map.put(normalized, table, count)}}

        _value ->
          {:halt, {:error, "invalid_table_counts"}}
      end
    end)
  end

  defp mismatches(baseline, recovery) do
    migration_mismatches =
      if baseline.applied_migration_count == recovery.applied_migration_count do
        []
      else
        [
          %{
            field: "applied_migration_count",
            baseline: baseline.applied_migration_count,
            recovery: recovery.applied_migration_count
          }
        ]
      end

    table_mismatches =
      Enum.flat_map(Verifier.expected_tables(), fn table ->
        baseline_count = Map.fetch!(baseline.table_counts, table)
        recovery_count = Map.fetch!(recovery.table_counts, table)

        if baseline_count == recovery_count do
          []
        else
          [
            %{
              field: "table_count",
              table: table,
              baseline: baseline_count,
              recovery: recovery_count
            }
          ]
        end
      end)

    migration_mismatches ++ table_mismatches
  end

  defp field(map, key) when is_atom(key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(map, key) when is_binary(key), do: Map.get(map, key, Map.get(map, safe_atom(key)))

  defp safe_atom("steam_users"), do: :steam_users
  defp safe_atom("steam_entitlements"), do: :steam_entitlements
  defp safe_atom("match_summaries"), do: :match_summaries
  defp safe_atom("player_ratings"), do: :player_ratings
  defp safe_atom("system_settings"), do: :system_settings
  defp safe_atom(_key), do: nil

  defp normalize_timestamp(value) when is_binary(value), do: String.slice(value, 0, 80)
  defp normalize_timestamp(_value), do: nil

  defp error(code), do: {:error, %{ready: false, code: code}}
end
