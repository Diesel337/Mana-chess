alias ManaChessOnline.{GameRuntimeConfig, GameServer, GameSettings, GameState}

parse_positive = fn value, fallback ->
  case Integer.parse(to_string(value || "")) do
    {integer, ""} when integer > 0 -> integer
    _error -> fallback
  end
end

numeric_args =
  Enum.filter(System.argv(), fn argument ->
    match?({_integer, ""}, Integer.parse(argument))
  end)

[games_arg, duration_arg] = Enum.take(numeric_args ++ [nil, nil], 2)
game_count = parse_positive.(games_arg, 500)
duration_seconds = parse_positive.(duration_arg, 5)
tick_ms = GameRuntimeConfig.tick_ms()
parent = self()
baseline_memory = :erlang.memory(:total)
settings = GameSettings.default_settings()
history = Enum.map(1..48, &"Movimiento de referencia #{&1}")

pids =
  Enum.map(1..game_count, fn index ->
    game =
      "capacity_#{index}"
      |> GameState.private_game(settings)
      |> Map.merge(%{
        players: %{white: "white_#{index}", black: "black_#{index}"},
        status: :playing,
        first_move_pending: nil,
        log: history
      })

    tick_observer = fn _previous_game, _next_game, _now_ms ->
      send(parent, {:capacity_tick, System.monotonic_time(:millisecond)})
    end

    {:ok, pid} =
      GameServer.start_link(
        game: game,
        tick_ms: tick_ms,
        auto_tick: true,
        initial_tick_delay_ms: GameRuntimeConfig.initial_tick_delay_ms(game.id, tick_ms),
        observer: fn _previous_game, _next_game -> :ok end,
        tick_observer: tick_observer
      )

    pid
  end)

receive_ticks = fn receive_ticks, started_at_ms, deadline_ms, count ->
  remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

  if remaining_ms <= 0 do
    count
  else
    receive do
      {:capacity_tick, tick_at_ms} ->
        next_count = if tick_at_ms >= started_at_ms, do: count + 1, else: count
        receive_ticks.(receive_ticks, started_at_ms, deadline_ms, next_count)
    after
      min(remaining_ms, 100) ->
        receive_ticks.(receive_ticks, started_at_ms, deadline_ms, count)
    end
  end
end

started_at_ms = System.monotonic_time(:millisecond)
deadline_ms = started_at_ms + duration_seconds * 1_000
observed_ticks = receive_ticks.(receive_ticks, started_at_ms, deadline_ms, 0)
expected_ticks = game_count * duration_seconds * 1_000 / tick_ms

process_memory_bytes =
  Enum.reduce(pids, 0, fn pid, total ->
    case Process.info(pid, :memory) do
      {:memory, bytes} -> total + bytes
      nil -> total
    end
  end)

IO.puts("Mana Chess autonomous GameServer capacity benchmark")
IO.puts("games=#{game_count} duration_seconds=#{duration_seconds} tick_ms=#{tick_ms}")

IO.puts(
  "ticks_observed=#{observed_ticks} ticks_expected=#{round(expected_ticks)} delivery_percent=#{Float.round(observed_ticks / expected_ticks * 100, 2)}"
)

IO.puts(
  "game_process_memory_mb=#{Float.round(process_memory_bytes / 1_048_576, 2)} vm_delta_mb=#{Float.round((:erlang.memory(:total) - baseline_memory) / 1_048_576, 2)} run_queue=#{:erlang.statistics(:run_queue)}"
)

Enum.each(pids, &GenServer.stop(&1, :normal, 5_000))
