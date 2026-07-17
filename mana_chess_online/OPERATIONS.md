# Mana Chess operations runbook

Mana Chess emits low-volume operational events for launch monitoring while keeping routine HTTP and LiveView connection logs disabled outside development. Production uses one-line JSON for both application events and standard OTP/Elixir logs.

## Modules

- `ManaChessOnline.Operations.EventLog`: supervised, bounded event history and deduplication counters.
- `ManaChessOnline.Operations.Telemetry`: Phoenix, LiveView, and Ecto exception/latency handlers.
- `ManaChessOnline.Operations.LogFormatter`: one-line JSON formatter used in production.
- `ManaChessOnline.Persistence.Verifier`: read-only migration, table, and aggregate-count verification for a live or restored Postgres database.

`EventLog` only accepts a fixed metadata allowlist. It does not accept request bodies, query parameters, game IDs, player IDs, Steam tickets, cookies, passwords, publisher keys, or database URLs.

## Log contract

Operational records use `message=operational_event` and add an `event` field. A production line has this shape:

```json
{"timestamp":"2026-07-17T20:01:02.345Z","level":"error","service":"mana_chess_online","environment":"production","release":"abc123","message":"operational_event","event":"database_query_failed","component":"postgres","reason_class":"DBConnection.ConnectionError"}
```

The formatter also converts normal OTP crash reports into JSON with a bounded message. Runtime metadata comes from `RAILWAY_ENVIRONMENT_NAME` and `RAILWAY_GIT_COMMIT_SHA`; local releases fall back to their Mix environment and `local`.

Current operational events:

| Event | Level | Meaning |
| --- | --- | --- |
| `application_started` | info | The supervised application tree started. |
| `web_request_exception` | error | A Phoenix route raised or exited. |
| `web_request_slow` | warning | A routed request exceeded its threshold. |
| `socket_connection_refused` | warning | Phoenix rejected a socket connection. |
| `socket_connection_slow` | warning | Socket connection setup exceeded its threshold. |
| `channel_join_refused` | warning | A LiveView/channel join was rejected. |
| `channel_join_slow` | warning | A LiveView/channel join exceeded its threshold. |
| `channel_event_slow` | warning | A channel event exceeded its threshold. |
| `database_query_failed` | error | Ecto returned a query error. |
| `database_query_slow` | warning | Ecto query time exceeded its threshold. |
| `persistence_health_failed` | error | The Postgres readiness query failed. |
| `persistence_write_failed` | warning | The asynchronous writer could not persist an event. |
| `game_server_recovered` | warning | A gameplay path recreated a missing GameServer. |
| `game_server_recovery_failed` | error | A gameplay path had to use its in-memory fallback. |

Identical event fingerprints are logged once per deduplication window. The health counters still count every report, and the next emitted record includes `suppressed_since_last`.

## Runtime settings

| Variable | Default | Maximum | Purpose |
| --- | ---: | ---: | --- |
| `MANA_CHESS_OPERATION_EVENT_LIMIT` | 100 | 500 | Safe events retained in memory. |
| `MANA_CHESS_OPERATION_DEDUPE_SECONDS` | 60 | 3,600 | Repeat-log suppression window. |
| `MANA_CHESS_SLOW_REQUEST_MS` | 2,000 | 60,000 | Phoenix route warning threshold. |
| `MANA_CHESS_SLOW_QUERY_MS` | 1,000 | 60,000 | Ecto query warning threshold. |
| `MANA_CHESS_SLOW_SOCKET_MS` | 2,000 | 60,000 | Socket/channel warning threshold. |

Do not lower thresholds during a large load run without watching Railway log volume.

## Health and Railway

`GET /health` includes an `operations` summary with environment/release identity, process status, severity counters, emitted/suppressed counts, and the last safe event name. Historical errors do not make readiness fail; current Postgres unavailability still returns `503`.

Useful Railway queries:

```powershell
railway logs --service Mana-chess --environment production --since 30m --filter "@level:error"
railway logs --service Mana-chess --environment production --since 30m --filter '"database_query_failed"'
railway logs --service Mana-chess --environment production --since 30m --filter '"game_server_recovery_failed"'
```

Create Railway notifications for deployment failures and service crashes before launch. The structured events remain available in deployment logs even when no external error-reporting provider is configured.

## Persistence verification

Run the verifier inside a deployed service. It is read-only and outputs migration counts plus aggregate row counts, never row contents:

```powershell
railway ssh --service Mana-chess --environment staging -- sh /app/bin/verify-persistence
```

A successful line contains `"ready":true`, zero pending migrations, and counts for `steam_users`, `steam_entitlements`, `match_summaries`, `player_ratings`, and `system_settings`. Any database exception is reduced to a stable error code.

## Restore rehearsal

1. Run the verifier against production and record its timestamp, release, migration count, and table counts in the private release ticket.
2. Create a Railway Postgres backup according to the active database plan and retention policy.
3. Restore that backup into a disposable recovery environment with its own Postgres service and credentials. Never repoint normal staging or production at each other's database.
4. Deploy the same application commit to the recovery environment and run `verify-persistence` there.
5. Compare migration and row counts. If production remained writable between snapshots, account for the timestamp difference instead of assuming exact equality.
6. Exercise health, global settings, leaderboard reads, and one non-rated QA match. Do not use real publisher credentials unless the rehearsal explicitly includes Steam authentication.
7. Record evidence and only then remove the disposable recovery environment.

The verifier prepares this rehearsal; it does not replace a real provider backup, restore, retention policy, or launch-owner sign-off.
