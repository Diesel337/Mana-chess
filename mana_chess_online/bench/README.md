# Mana Chess capacity checks

Run the autonomous `GameServer` benchmark without starting Phoenix:

```powershell
mix run --no-start bench/game_server_capacity.exs -- 500 5
```

The first argument is the number of active games and the second is the sample duration in seconds. The benchmark reports expected versus observed 250 ms ticks, process memory, VM memory growth, and the BEAM run queue.

This measures the game-process core only. Steam launch certification must also exercise two LiveView/WebSocket clients per online match at 100, 250, and 500 concurrent matches.

## Logical lobby and matchmaking smoke

Run the in-app lobby path, including practice, rating-aware quick match, private matches, spectators, metrics, and cleanup:

```powershell
mix run scripts/lobby_stress.exs -- --profile 100 --max-total-ms 30000 --max-mailbox 10 --max-run-queue 20
mix run scripts/lobby_stress.exs -- --profile 500 --max-total-ms 90000 --max-mailbox 10 --max-run-queue 20
```

The July 17, 2026 local `500` profile completed 500 joins, 100 practice games, 75 competitive matches, 75 private matches, and 100 spectators with zero operation errors. It reached 250 live `GameServer` processes, including 71 hidden `match_*` rooms, with mailbox peak `0`, run queue peak `3`, and cleanup back to the four fixed rooms. Total wall time was 37.378 seconds. This validates serialized lobby admission and cleanup, not network/WebSocket capacity.

## LiveView/WebSocket capacity

Install the isolated benchmark dependencies once:

```powershell
pnpm --dir bench install --frozen-lockfile
```

Start Mana Chess locally and run a ten-match smoke test:

```powershell
pnpm --dir bench liveview -- --matches 10 --hold-seconds 15 --output bench/reports/local-10.json
```

The default `private` mode creates directly addressed private rooms. The `competitive` mode drives the actual quick-match button with two independent browser sessions, confirms that both players received the same room, reports fixed versus dynamic `match_*` usage, declares both players ready, exercises moves, and cleans up through LiveView:

```powershell
pnpm --dir bench liveview -- --mode competitive --matches 10 --ramp-per-second 5 --hold-seconds 15 --output bench/reports/local-competitive-10.json
```

Run the benchmark parser and report-helper tests with:

```powershell
pnpm --dir bench test
```

Remote targets are blocked unless explicitly acknowledged:

```powershell
pnpm --dir bench liveview -- --url https://mana-chess-production.up.railway.app --allow-remote --matches 100 --ramp-per-second 10 --hold-seconds 30 --output bench/reports/production-private-100.json
```

The runner requires a successful `/health` preflight before the ramp begins. Each accepted match creates two independent HTTP sessions, performs the real Phoenix LiveView WebSocket handshake, seats both players, starts the match, sends one move per player, holds the sockets open, samples `/health`, and leaves both seats during cleanup. Use `--allow-capacity-rejections` for an overload run that intentionally attempts more rooms than the configured admission limit.

Competitive pairing is serialized only around each synthetic pair's two queue clicks so concurrent benchmark pairs cannot cross-match each other. Use this mode on an isolated local or staging service. If a tightly controlled production smoke is necessary, keep it small and add `--no-moves`; never run a large competitive ramp against a lobby serving real players.

### Local baseline

The July 16, 2026 Windows development run used Phoenix 1.8.9, Bandit 1.12.0, and a local server with `MANA_CHESS_MAX_DYNAMIC_GAMES=600`. Every attempted room was accepted, every health sample passed, and cleanup returned the active dynamic-room count to zero.

| Matches | Clients | Ramp/s | Hold | Join p95 | Event p95 | Health p95 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 200 | 20 | 10 s | 4.24 ms | 182.18 ms | 21.16 ms |
| 250 | 500 | 25 | 15 s | 4.98 ms | 213.70 ms | 18.39 ms |
| 500 | 1,000 | 25 | 15 s | 14.26 ms | 217.63 ms | 28.31 ms |

The July 17, 2026 competitive-queue runs also completed without setup, health, or cleanup errors. Every client used the real quick-match event, every pair resolved to the same public room, and every match exercised opening moves.

| Matches | Clients | Fixed | Dynamic | Join p95 | Assignment p95 | Event p95 | Health p95 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 200 | 4 | 96 | 4.25 ms | 20.93 ms | 216.08 ms | 16.86 ms |
| 250 | 500 | 4 | 246 | 39.48 ms | 44.19 ms | 277.50 ms | 16.91 ms |
| 500 | 1,000 | 4 | 496 | 58.20 ms | 68.20 ms | 289.11 ms | 18.73 ms |

The 100- and 250-match runs used the production-default `MANA_CHESS_MAX_DYNAMIC_GAMES=250`; the 500-match margin run used `600`. These local results establish engineering margin, not Railway production capacity. Keep the production admission limit at 250 dynamic matches until both private and competitive scenarios pass against a dedicated Railway staging service with production-sized CPU, memory, database, and network settings.
