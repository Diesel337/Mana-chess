defmodule ManaChessOnline.LoadLobbySmoke do
  @moduledoc false

  alias ManaChessOnline.GameLobby

  @default_players 100
  @default_settle_ms 300
  @default_metrics_timeout_ms 30_000
  @default_operation_timeout_ms 30_000

  @profile_defaults %{
    "100" => %{
      players: 100,
      practice: 20,
      competitive_pairs: 20,
      private_pairs: 15,
      concurrency: 32,
      settle_ms: 300
    },
    "500" => %{
      players: 500,
      practice: 100,
      competitive_pairs: 75,
      private_pairs: 75,
      concurrency: 64,
      settle_ms: 500
    }
  }

  def run(argv) do
    config = parse_config(argv)
    total_start = System.monotonic_time(:millisecond)
    run_id = "load-" <> Integer.to_string(System.system_time(:millisecond))
    players = Enum.map(1..config.players, &"#{run_id}-p#{&1}")

    {practice_players, competitive_players, private_players, watch_players} =
      split_players(players, config)

    private_pairs = Enum.chunk_every(private_players, 2)

    baseline = metrics(config)

    {join_summary, join_ms} =
      timed(fn -> concurrent(players, config.concurrency, &join_player(&1, config)) end)

    after_join = metrics(config)

    {practice_summary, practice_ms} =
      timed(fn ->
        concurrent(practice_players, config.concurrency, &practice_player(&1, config))
      end)

    after_practice = metrics(config)

    {competitive_summary, competitive_ms} =
      timed(fn -> competitive_matches(competitive_players, config.concurrency, config) end)

    after_competitive = metrics(config)

    {private_summary, private_ms} =
      timed(fn -> private_matches(private_pairs, config.concurrency, config) end)

    after_private = metrics(config)

    {watch_summary, watch_ms} =
      timed(fn ->
        watch_games(watch_players, private_summary.game_ids, config.concurrency, config)
      end)

    after_watch = metrics(config)
    Process.sleep(config.settle_ms)
    after_settle = metrics(config)

    {cleanup_summary, cleanup_ms, after_cleanup} =
      if config.cleanup? do
        {summary, ms} =
          timed(fn -> concurrent(players, config.concurrency, &leave_player(&1, config)) end)

        Process.sleep(50)
        {summary, ms, metrics(config)}
      else
        {%{ok: 0, error: 0, errors: []}, 0, nil}
      end

    total_ms = System.monotonic_time(:millisecond) - total_start

    result = %{
      config:
        Map.take(config, [
          :profile,
          :players,
          :practice,
          :competitive_pairs,
          :private_pairs,
          :concurrency,
          :moves,
          :settle_ms,
          :metrics_timeout_ms,
          :operation_timeout_ms,
          :cleanup?,
          :thresholds
        ]),
      timings_ms: %{
        total: total_ms,
        join: join_ms,
        practice: practice_ms,
        competitive_matches: competitive_ms,
        private_matches: private_ms,
        watch: watch_ms,
        cleanup: cleanup_ms
      },
      summaries: %{
        join: join_summary,
        practice: practice_summary,
        competitive_matches: Map.delete(competitive_summary, :game_ids),
        private_matches: Map.delete(private_summary, :game_ids),
        watch: watch_summary,
        cleanup: cleanup_summary
      },
      metrics: %{
        baseline: compact_metrics(baseline),
        after_join: compact_metrics(after_join),
        after_practice: compact_metrics(after_practice),
        after_competitive: compact_metrics(after_competitive),
        after_private: compact_metrics(after_private),
        after_watch: compact_metrics(after_watch),
        after_settle: compact_metrics(after_settle),
        after_cleanup: compact_metrics(after_cleanup)
      }
    }

    result = Map.put(result, :checks, checks(result, config))
    print_result(result, config.json?)

    if result.checks.ok, do: :ok, else: System.halt(1)
  end

  defp parse_config(["--" | argv]), do: parse_config(argv)

  defp parse_config(argv) do
    {opts, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          profile: :string,
          players: :integer,
          practice: :integer,
          competitive_pairs: :integer,
          private_pairs: :integer,
          concurrency: :integer,
          moves: :integer,
          settle_ms: :integer,
          metrics_timeout_ms: :integer,
          operation_timeout_ms: :integer,
          max_total_ms: :integer,
          max_phase_ms: :integer,
          max_mailbox: :integer,
          max_run_queue: :integer,
          max_games: :integer,
          max_game_servers: :integer,
          allow_dirty_cleanup: :boolean,
          no_cleanup: :boolean,
          json: :boolean
        ],
        aliases: [p: :players, c: :concurrency]
      )

    if invalid != [] do
      raise ArgumentError, "invalid options: #{inspect(invalid)}"
    end

    opts = Map.new(opts)
    profile = opts[:profile]
    defaults = profile_defaults(profile)
    players = positive(option(opts, :players, defaults.players), :players)
    practice_default = Map.get(defaults, :practice, min(players, 20))

    practice =
      clamp(non_negative(option(opts, :practice, practice_default), :practice), 0, players)

    remaining = players - practice
    competitive_pairs_default = Map.get(defaults, :competitive_pairs, 0)

    competitive_pairs =
      clamp(
        non_negative(
          option(opts, :competitive_pairs, competitive_pairs_default),
          :competitive_pairs
        ),
        0,
        div(remaining, 2)
      )

    remaining = remaining - competitive_pairs * 2
    private_pairs_default = Map.get(defaults, :private_pairs, div(remaining, 2))

    private_pairs =
      clamp(
        non_negative(option(opts, :private_pairs, private_pairs_default), :private_pairs),
        0,
        div(remaining, 2)
      )

    %{
      profile: profile || "custom",
      players: players,
      practice: practice,
      competitive_pairs: competitive_pairs,
      private_pairs: private_pairs,
      concurrency: positive(option(opts, :concurrency, defaults.concurrency), :concurrency),
      moves: positive(option(opts, :moves, 1), :moves),
      settle_ms: non_negative(option(opts, :settle_ms, defaults.settle_ms), :settle_ms),
      metrics_timeout_ms:
        positive(
          option(opts, :metrics_timeout_ms, @default_metrics_timeout_ms),
          :metrics_timeout_ms
        ),
      operation_timeout_ms:
        positive(
          option(opts, :operation_timeout_ms, @default_operation_timeout_ms),
          :operation_timeout_ms
        ),
      cleanup?: !Map.get(opts, :no_cleanup, false),
      allow_dirty_cleanup?: Map.get(opts, :allow_dirty_cleanup, false),
      json?: Map.get(opts, :json, false),
      thresholds: thresholds(opts)
    }
  end

  defp profile_defaults(nil) do
    %{
      players: @default_players,
      concurrency: min(@default_players, System.schedulers_online() * 8),
      settle_ms: @default_settle_ms
    }
  end

  defp profile_defaults(profile) do
    case Map.fetch(@profile_defaults, profile) do
      {:ok, defaults} -> defaults
      :error -> raise ArgumentError, "unknown profile #{inspect(profile)}. Use 100 or 500."
    end
  end

  defp option(opts, key, default), do: Map.get(opts, key) || default

  defp thresholds(opts) do
    %{
      max_total_ms: positive_or_nil(opts[:max_total_ms], :max_total_ms),
      max_phase_ms: positive_or_nil(opts[:max_phase_ms], :max_phase_ms),
      max_mailbox: non_negative_or_nil(opts[:max_mailbox], :max_mailbox),
      max_run_queue: non_negative_or_nil(opts[:max_run_queue], :max_run_queue),
      max_games: positive_or_nil(opts[:max_games], :max_games),
      max_game_servers: positive_or_nil(opts[:max_game_servers], :max_game_servers)
    }
  end

  defp positive(value, _name) when is_integer(value) and value > 0, do: value

  defp positive(value, name),
    do: raise(ArgumentError, "#{name} must be a positive integer, got #{inspect(value)}")

  defp positive_or_nil(nil, _name), do: nil
  defp positive_or_nil(value, name), do: positive(value, name)

  defp non_negative(value, _name) when is_integer(value) and value >= 0, do: value

  defp non_negative(value, name),
    do: raise(ArgumentError, "#{name} must be zero or greater, got #{inspect(value)}")

  defp non_negative_or_nil(nil, _name), do: nil
  defp non_negative_or_nil(value, name), do: non_negative(value, name)

  defp clamp(value, min, max), do: value |> Kernel.max(min) |> Kernel.min(max)

  defp split_players(players, config) do
    {practice_players, rest} = Enum.split(players, config.practice)
    {competitive_players, rest} = Enum.split(rest, config.competitive_pairs * 2)
    {private_players, watch_players} = Enum.split(rest, config.private_pairs * 2)
    {practice_players, competitive_players, private_players, watch_players}
  end

  defp metrics(config), do: GameLobby.metrics(config.metrics_timeout_ms)

  defp lobby_call(request, config),
    do: GenServer.call(GameLobby, request, config.operation_timeout_ms)

  defp timed(fun) do
    start = System.monotonic_time(:millisecond)
    value = fun.()
    {value, System.monotonic_time(:millisecond) - start}
  end

  defp concurrent(items, concurrency, fun) do
    items
    |> Task.async_stream(&safe_call(fun, &1),
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce(%{ok: 0, error: 0, errors: []}, &accumulate_result/2)
  end

  defp private_matches(pairs, concurrency, config) do
    pairs
    |> Task.async_stream(&safe_private_match(&1, config),
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce(%{ok: 0, error: 0, errors: [], game_ids: []}, fn
      {:ok, {:ok, game_id}}, acc -> %{acc | ok: acc.ok + 1, game_ids: [game_id | acc.game_ids]}
      result, acc -> accumulate_result(result, acc)
    end)
    |> update_in([:game_ids], &Enum.reverse/1)
  end

  defp competitive_matches(players, concurrency, config) do
    players
    |> Task.async_stream(&safe_competitive_player(&1, config),
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Enum.reduce(%{ok: 0, error: 0, errors: [], game_ids: []}, fn
      {:ok, {:ok, game_id}}, acc ->
        %{acc | ok: acc.ok + 1, game_ids: [game_id | acc.game_ids]}

      result, acc ->
        accumulate_result(result, acc)
    end)
    |> then(fn summary ->
      game_ids = summary.game_ids |> Enum.uniq() |> Enum.sort()

      summary
      |> Map.put(:game_ids, game_ids)
      |> Map.put(:match_count, length(game_ids))
    end)
  end

  defp watch_games(players, [], concurrency, config),
    do: concurrent(players, concurrency, &watch_player(&1, "game_1", config))

  defp watch_games(players, game_ids, concurrency, config) do
    players
    |> Enum.with_index()
    |> concurrent(concurrency, fn {player_id, index} ->
      game_id = Enum.at(game_ids, rem(index, length(game_ids)))
      watch_player(player_id, game_id, config)
    end)
  end

  defp safe_call(fun, item) do
    case fun.(item) do
      {:error, reason} -> {:error, inspect(reason)}
      _result -> :ok
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp safe_private_match([white_id, black_id], config) do
    case lobby_call({:create_private, white_id}, config) do
      {:ok, view} ->
        lobby_call({:sit, black_id, view.game_id, :black}, config)
        lobby_call({:start_game, white_id}, config)
        lobby_call({:ready_to_start, black_id}, config)
        lobby_call({:enqueue, white_id, {6, 4}, {5, 4}}, config)
        {:ok, view.game_id}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp safe_private_match(pair, _config), do: {:error, "invalid private pair #{inspect(pair)}"}

  defp safe_competitive_player(player_id, config) do
    case lobby_call({:sit_anywhere, player_id, 1_200}, config) do
      %{game_id: game_id} when is_binary(game_id) -> {:ok, game_id}
      _view -> {:error, "competitive queue did not assign #{player_id}"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp accumulate_result({:ok, :ok}, acc), do: %{acc | ok: acc.ok + 1}
  defp accumulate_result({:ok, {:ok, _value}}, acc), do: %{acc | ok: acc.ok + 1}
  defp accumulate_result({:ok, {:error, reason}}, acc), do: add_error(acc, reason)
  defp accumulate_result({:exit, reason}, acc), do: add_error(acc, inspect(reason))

  defp add_error(acc, reason) do
    %{acc | error: acc.error + 1, errors: Enum.take([reason | acc.errors], 8)}
  end

  defp join_player(player_id, config), do: lobby_call({:join, player_id}, config)
  defp leave_player(player_id, config), do: lobby_call({:leave, player_id}, config)

  defp watch_player(player_id, game_id, config),
    do: lobby_call({:watch, player_id, game_id}, config)

  defp practice_player(player_id, config) do
    lobby_call({:start_practice, player_id}, config)

    for _ <- 1..config.moves do
      lobby_call({:enqueue, player_id, {6, 4}, {5, 4}}, config)
    end

    :ok
  end

  defp compact_metrics(nil), do: nil

  defp compact_metrics(metrics) do
    Map.take(metrics, [
      :game_count,
      :public_game_count,
      :matchmaking_game_count,
      :private_game_count,
      :practice_game_count,
      :playing_game_count,
      :bot_game_count,
      :queued_move_count,
      :rate_limit_bucket_count,
      :game_server_count,
      :game_server_mailbox_total,
      :game_server_mailbox_max,
      :game_server_memory_kb,
      :dynamic_game_count,
      :max_dynamic_games,
      :dynamic_capacity_available,
      :capacity_rejected_count,
      :cleaned_dynamic_game_count,
      :process_count,
      :memory_total_kb,
      :run_queue
    ])
  end

  defp checks(result, config) do
    check_map = %{
      summaries:
        boolean_check(
          !summaries_failed?(result.summaries),
          "all operation summaries have zero errors"
        ),
      cleanup: cleanup_check(result, config),
      max_total_ms: threshold_check(result.timings_ms.total, config.thresholds.max_total_ms),
      max_phase_ms:
        threshold_check(max_phase_ms(result.timings_ms), config.thresholds.max_phase_ms),
      max_mailbox:
        threshold_check(
          peak_metric(result.metrics, :game_server_mailbox_max),
          config.thresholds.max_mailbox
        ),
      max_run_queue:
        threshold_check(peak_metric(result.metrics, :run_queue), config.thresholds.max_run_queue),
      max_games:
        threshold_check(peak_metric(result.metrics, :game_count), config.thresholds.max_games),
      max_game_servers:
        threshold_check(
          peak_metric(result.metrics, :game_server_count),
          config.thresholds.max_game_servers
        )
    }

    %{ok: Enum.all?(check_map, fn {_name, check} -> check.ok end), checks: check_map}
  end

  defp boolean_check(ok?, detail), do: %{ok: ok?, detail: detail}

  defp threshold_check(value, nil), do: %{ok: true, skipped: true, value: value, max: nil}
  defp threshold_check(value, max), do: %{ok: value <= max, value: value, max: max}

  defp cleanup_check(_result, %{cleanup?: false}),
    do: %{ok: true, skipped: true, detail: "cleanup disabled"}

  defp cleanup_check(_result, %{allow_dirty_cleanup?: true}),
    do: %{ok: true, skipped: true, detail: "dirty cleanup allowed"}

  defp cleanup_check(%{metrics: %{baseline: baseline, after_cleanup: after_cleanup}}, _config) do
    ok? =
      baseline.game_count == after_cleanup.game_count and
        baseline.private_game_count == after_cleanup.private_game_count and
        baseline.practice_game_count == after_cleanup.practice_game_count and
        baseline.game_server_count == after_cleanup.game_server_count

    %{ok: ok?, baseline: baseline, after_cleanup: after_cleanup}
  end

  defp max_phase_ms(timings) do
    timings
    |> Map.drop([:total])
    |> Map.values()
    |> Enum.max(fn -> 0 end)
  end

  defp peak_metric(metrics_by_phase, key) do
    metrics_by_phase
    |> Map.values()
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Map.get(&1, key, 0))
    |> Enum.max(fn -> 0 end)
  end

  defp print_result(result, true), do: IO.puts(Jason.encode!(result))

  defp print_result(result, false) do
    IO.puts("Mana Chess lobby stress smoke")
    IO.puts("config: #{inspect(result.config)}")
    IO.puts("timings_ms: #{inspect(result.timings_ms)}")
    IO.puts("summaries: #{inspect(result.summaries)}")
    IO.puts("checks: #{format_checks(result.checks)}")

    Enum.each(result.metrics, fn {label, metrics} ->
      IO.puts("#{label}: #{format_metrics(metrics)}")
    end)
  end

  defp format_checks(%{ok: ok?, checks: checks}) do
    failed =
      checks
      |> Enum.reject(fn {_name, check} -> check.ok end)
      |> Enum.map(fn {name, check} -> {name, Map.drop(check, [:ok])} end)

    if failed == [], do: "ok=#{ok?}", else: "ok=#{ok?} failed=#{inspect(failed)}"
  end

  defp format_metrics(nil), do: "n/a"

  defp format_metrics(metrics) do
    "games=#{metrics.game_count} public=#{metrics.public_game_count} matchmaking=#{metrics.matchmaking_game_count} " <>
      "private=#{metrics.private_game_count} " <>
      "practice=#{metrics.practice_game_count} playing=#{metrics.playing_game_count} bots=#{metrics.bot_game_count} " <>
      "dynamic=#{metrics.dynamic_game_count}/#{metrics.max_dynamic_games} " <>
      "servers=#{metrics.game_server_count} mailbox=#{metrics.game_server_mailbox_total}/#{metrics.game_server_mailbox_max} " <>
      "rate_buckets=#{metrics.rate_limit_bucket_count} mem=#{metrics.memory_total_kb}KB run_queue=#{metrics.run_queue}"
  end

  defp summaries_failed?(summaries) do
    summaries
    |> Map.values()
    |> Enum.any?(&(Map.get(&1, :error, 0) > 0))
  end
end

ManaChessOnline.LoadLobbySmoke.run(System.argv())
