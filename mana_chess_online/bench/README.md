# Mana Chess capacity checks

Run the autonomous `GameServer` benchmark without starting Phoenix:

```powershell
mix run --no-start bench/game_server_capacity.exs -- 500 5
```

The first argument is the number of active games and the second is the sample duration in seconds. The benchmark reports expected versus observed 250 ms ticks, process memory, VM memory growth, and the BEAM run queue.

This measures the game-process core only. Steam launch certification must also exercise two LiveView/WebSocket clients per online match at 100, 250, and 500 concurrent matches.
