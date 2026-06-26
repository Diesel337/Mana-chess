defmodule ManaChessOnline.LoadLobbySmoke do
  @moduledoc false

  alias ManaChessOnline.GameLobby

  @default_players 100
  @default_settle_ms 300

  def run(argv) do
    config = parse_config(argv)
    run_id = "load-" <> Integer.to_string(System.system_time(:millisecond))
    players = Enum.map(1..config.players, &"#{run_id}-p#{&1}")
    {practice_players, private_players, watch_players} = split_players(players, config)
    private_pairs = Enum.chunk_every(private_players, 2)

    baseline = GameLobby.metrics()

    {join_summary, join_ms} =
      timed(fn -> concurrent(players, config.concurrency, &join_player/1) end)

    after_join = GameLobby.metrics()

    {practice_summary, practice_ms} =
      timed(fn ->
        concurrent(practice_players, config.concurrency, &practice_player(&1, config.moves))
      end)

    after_practice = GameLobby.metrics()

    {private_summary, private_ms} =
      timed(fn -> private_matches(private_pairs, config.concurrency) end)

    after_private = GameLobby.metrics()

    {watch_summary, watch_ms} =
      timed(fn -> watch_games(watch_players, private_summary.game_ids, config.concurrency) end)

    after_watch = GameLobby.metrics()
    Process.sleep(config.settle_ms)
    after_settle = GameLobby.metrics()

    {cleanup_summary, cleanup_ms, after_cleanup} =
      if config.cleanup? do
        {summary, ms} = timed(fn -> concurrent(players, config.concurrency, &leave_player/1) end)
        Process.sleep(50)
        {summary, ms, GameLobby.metrics()}
      else
        {%{ok: 0, error: 0, errors: []}, 0, nil}
      end

    result = %{
      config:
        Map.take(config, [
          :players,
          :practice,
          :private_pairs,
          :concurrency,
          :moves,
          :settle_ms,
          :cleanup?
        ]),
      timings_ms: %{
        join: join_ms,
        practice: practice_ms,
        private_matches: private_ms,
        watch: watch_ms,
        cleanup: cleanup_ms
      },
      summaries: %{
        join: join_summary,
        practice: practice_summary,
        private_matches: Map.delete(private_summary, :game_ids),
        watch: watch_summary,
        cleanup: cleanup_summary
      },
      metrics: %{
        baseline: compact_metrics(baseline),
        after_join: compact_metrics(after_join),
        after_practice: compact_metrics(after_practice),
        after_private: compact_metrics(after_private),
        after_watch: compact_metrics(after_watch),
        after_settle: compact_metrics(after_settle),
        after_cleanup: compact_metrics(after_cleanup)
      }
    }

    print_result(result, config.json?)

    if failed?(result.summaries), do: System.halt(1), else: :ok
  end

  defp parse_config(["--" | argv]), do: parse_config(argv)

  defp parse_config(argv) do
    {opts, _rest, invalid} =
      OptionParser.parse(argv,
        strict: [
          players: :integer,
          practice: :integer,
          private_pairs: :integer,
          concurrency: :integer,
          moves: :integer,
          settle_ms: :integer,
          no_cleanup: :boolean,
          json: :boolean
        ],
        aliases: [p: :players, c: :concurrency]
      )

    if invalid != [] do
      raise ArgumentError, "invalid options: #{inspect(invalid)}"
    end

    opts = Map.new(opts)
    players = positive(opts[:players] || @default_players, :players)
    practice = clamp(non_negative(opts[:practice] || min(players, 20), :practice), 0, players)
    remaining = players - practice

    private_pairs =
      clamp(
        non_negative(opts[:private_pairs] || div(remaining, 2), :private_pairs),
        0,
        div(remaining, 2)
      )

    %{
      players: players,
      practice: practice,
      private_pairs: private_pairs,
      concurrency:
        positive(opts[:concurrency] || min(players, System.schedulers_online() * 8), :concurrency),
      moves: positive(opts[:moves] || 1, :moves),
      settle_ms: non_negative(opts[:settle_ms] || @default_settle_ms, :settle_ms),
      cleanup?: !Map.get(opts, :no_cleanup, false),
      json?: Map.get(opts, :json, false)
    }
  end

  defp positive(value, _name) when is_integer(value) and value > 0, do: value

  defp positive(value, name),
    do: raise(ArgumentError, "#{name} must be a positive integer, got #{inspect(value)}")

  defp non_negative(value, _name) when is_integer(value) and value >= 0, do: value

  defp non_negative(value, name),
    do: raise(ArgumentError, "#{name} must be zero or greater, got #{inspect(value)}")

  defp clamp(value, min, max), do: value |> Kernel.max(min) |> Kernel.min(max)

  defp split_players(players, config) do
    {practice_players, rest} = Enum.split(players, config.practice)
    {private_players, watch_players} = Enum.split(rest, config.private_pairs * 2)
    {practice_players, private_players, watch_players}
  end

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

  defp private_matches(pairs, concurrency) do
    pairs
    |> Task.async_stream(&safe_private_match/1,
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

  defp watch_games(players, [], concurrency),
    do: concurrent(players, concurrency, &GameLobby.watch(&1, "game_1"))

  defp watch_games(players, game_ids, concurrency) do
    players
    |> Enum.with_index()
    |> concurrent(concurrency, fn {player_id, index} ->
      game_id = Enum.at(game_ids, rem(index, length(game_ids)))
      GameLobby.watch(player_id, game_id)
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

  defp safe_private_match([white_id, black_id]) do
    case GameLobby.create_private(white_id) do
      {:ok, view} ->
        GameLobby.sit(black_id, view.game_id, :black)
        GameLobby.start_game(white_id)
        GameLobby.ready_to_start(black_id)
        GameLobby.enqueue(white_id, {6, 4}, {5, 4})
        {:ok, view.game_id}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp safe_private_match(pair), do: {:error, "invalid private pair #{inspect(pair)}"}

  defp accumulate_result({:ok, :ok}, acc), do: %{acc | ok: acc.ok + 1}
  defp accumulate_result({:ok, {:ok, _value}}, acc), do: %{acc | ok: acc.ok + 1}
  defp accumulate_result({:ok, {:error, reason}}, acc), do: add_error(acc, reason)
  defp accumulate_result({:exit, reason}, acc), do: add_error(acc, inspect(reason))

  defp add_error(acc, reason) do
    %{acc | error: acc.error + 1, errors: Enum.take([reason | acc.errors], 8)}
  end

  defp join_player(player_id), do: GameLobby.join(player_id)
  defp leave_player(player_id), do: GameLobby.leave(player_id)

  defp practice_player(player_id, moves) do
    GameLobby.start_practice(player_id)

    for _ <- 1..moves do
      GameLobby.enqueue(player_id, {6, 4}, {5, 4})
    end

    :ok
  end

  defp compact_metrics(nil), do: nil

  defp compact_metrics(metrics) do
    Map.take(metrics, [
      :game_count,
      :public_game_count,
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
      :process_count,
      :memory_total_kb,
      :run_queue
    ])
  end

  defp print_result(result, true), do: IO.puts(Jason.encode!(result))

  defp print_result(result, false) do
    IO.puts("Mana Chess lobby stress smoke")
    IO.puts("config: #{inspect(result.config)}")
    IO.puts("timings_ms: #{inspect(result.timings_ms)}")
    IO.puts("summaries: #{inspect(result.summaries)}")

    Enum.each(result.metrics, fn {label, metrics} ->
      IO.puts("#{label}: #{format_metrics(metrics)}")
    end)
  end

  defp format_metrics(nil), do: "n/a"

  defp format_metrics(metrics) do
    "games=#{metrics.game_count} public=#{metrics.public_game_count} private=#{metrics.private_game_count} " <>
      "practice=#{metrics.practice_game_count} playing=#{metrics.playing_game_count} bots=#{metrics.bot_game_count} " <>
      "servers=#{metrics.game_server_count} mailbox=#{metrics.game_server_mailbox_total}/#{metrics.game_server_mailbox_max} " <>
      "rate_buckets=#{metrics.rate_limit_bucket_count} mem=#{metrics.memory_total_kb}KB run_queue=#{metrics.run_queue}"
  end

  defp failed?(summaries) do
    summaries
    |> Map.values()
    |> Enum.any?(&(Map.get(&1, :error, 0) > 0))
  end
end

ManaChessOnline.LoadLobbySmoke.run(System.argv())
