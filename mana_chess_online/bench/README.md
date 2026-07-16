# Mana Chess capacity checks

Run the autonomous `GameServer` benchmark without starting Phoenix:

```powershell
mix run --no-start bench/game_server_capacity.exs -- 500 5
```

The first argument is the number of active games and the second is the sample duration in seconds. The benchmark reports expected versus observed 250 ms ticks, process memory, VM memory growth, and the BEAM run queue.

This measures the game-process core only. Steam launch certification must also exercise two LiveView/WebSocket clients per online match at 100, 250, and 500 concurrent matches.

## LiveView/WebSocket capacity

Install the isolated benchmark dependencies once:

```powershell
pnpm --dir bench install --frozen-lockfile
```

Start Mana Chess locally and run a ten-match smoke test:

```powershell
pnpm --dir bench liveview -- --matches 10 --hold-seconds 15 --output bench/reports/local-10.json
```

Remote targets are blocked unless explicitly acknowledged:

```powershell
pnpm --dir bench liveview -- --url https://mana-chess-production.up.railway.app --allow-remote --matches 100 --ramp-per-second 10 --hold-seconds 30 --output bench/reports/production-100.json
```

The runner requires a successful `/health` preflight before the ramp begins. Each accepted match creates two independent HTTP sessions, performs the real Phoenix LiveView WebSocket handshake, seats both players, starts the match, sends one move per player, holds the sockets open, samples `/health`, and leaves both seats during cleanup. Use `--allow-capacity-rejections` for an overload run that intentionally attempts more rooms than the configured admission limit.

### Local baseline

The July 16, 2026 Windows development run used Phoenix 1.8.9, Bandit 1.12.0, and a local server with `MANA_CHESS_MAX_DYNAMIC_GAMES=600`. Every attempted room was accepted, every health sample passed, and cleanup returned the active dynamic-room count to zero.

| Matches | Clients | Ramp/s | Hold | Join p95 | Event p95 | Health p95 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 200 | 20 | 10 s | 4.24 ms | 182.18 ms | 21.16 ms |
| 250 | 500 | 25 | 15 s | 4.98 ms | 213.70 ms | 18.39 ms |
| 500 | 1,000 | 25 | 15 s | 14.26 ms | 217.63 ms | 28.31 ms |

These results establish local engineering margin, not Railway production capacity. Keep the production admission limit at 250 dynamic matches until the same scenarios pass against a dedicated Railway staging service with production-sized CPU, memory, database, and network settings.
