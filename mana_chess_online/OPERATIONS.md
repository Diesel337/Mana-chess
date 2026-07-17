# Mana Chess operations runbook

Mana Chess emits low-volume operational events for launch monitoring while keeping routine HTTP and LiveView connection logs disabled outside development. Production uses one-line JSON for both application events and standard OTP/Elixir logs.

## Modules

- `ManaChessOnline.Operations.EventLog`: supervised, bounded event history and deduplication counters.
- `ManaChessOnline.Operations.AlertDispatcher`: bounded, serialized webhook queue with explicit retry limits.
- `ManaChessOnline.Operations.AlertWebhookClient`: HTTPS delivery with provider responses reduced to stable codes.
- `ManaChessOnline.Operations.Telemetry`: Phoenix, LiveView, and Ecto exception/latency handlers.
- `ManaChessOnline.Operations.LogFormatter`: one-line JSON formatter used in production.
- `ManaChessOnline.Persistence.Verifier`: read-only migration, table, and aggregate-count verification for a live or restored Postgres database.
- `ManaChessOnline.Persistence.VerificationComparison`: strict aggregate comparison of baseline and restored reports.

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
| `alert_delivery_failed` | error | The external webhook exhausted its bounded retries. This event is never recursively paged. |
| `alert_queue_overflow` | warning | The external webhook queue was full and dropped an alert. This event is never recursively paged. |

Identical event fingerprints are logged once per deduplication window. The health counters still count every report, and the next emitted record includes `suppressed_since_last`.

## Runtime settings

| Variable | Default | Maximum | Purpose |
| --- | ---: | ---: | --- |
| `MANA_CHESS_OPERATION_EVENT_LIMIT` | 100 | 500 | Safe events retained in memory. |
| `MANA_CHESS_OPERATION_DEDUPE_SECONDS` | 60 | 3,600 | Repeat-log suppression window. |
| `MANA_CHESS_SLOW_REQUEST_MS` | 2,000 | 60,000 | Phoenix route warning threshold. |
| `MANA_CHESS_SLOW_QUERY_MS` | 1,000 | 60,000 | Ecto query warning threshold. |
| `MANA_CHESS_SLOW_SOCKET_MS` | 2,000 | 60,000 | Socket/channel warning threshold. |
| `MANA_CHESS_ALERT_QUEUE_LIMIT` | 50 | 500 | Alerts waiting behind the single in-flight delivery. |
| `MANA_CHESS_ALERT_MAX_ATTEMPTS` | 3 | 5 | Total webhook attempts per emitted event. |
| `MANA_CHESS_ALERT_RETRY_DELAY_MS` | 500 | 60,000 | Base delay between bounded attempts. |

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

## External alert delivery

Alert delivery is disabled unless `MANA_CHESS_ALERT_WEBHOOK_URL` contains an HTTPS URL. Configure these secrets and settings only in Railway:

| Variable | Default | Purpose |
| --- | --- | --- |
| `MANA_CHESS_ALERT_WEBHOOK_URL` | empty | HTTPS receiver. Userinfo and URL fragments are rejected at startup. |
| `MANA_CHESS_ALERT_WEBHOOK_TOKEN` | empty | Optional bearer token sent in the `Authorization` header. |
| `MANA_CHESS_ALERT_LEVELS` | `error` | Comma-separated `error` or `warning,error`. Info events cannot page. |

The receiver must return a `2xx` response quickly. Redirects and Req's implicit retries are disabled; the supervised dispatcher owns the retry budget. EventLog calls the dispatcher only when an event escapes log deduplication, and the dispatcher sends one request at a time. Queue overflow and final delivery failure are counted but cannot recursively page themselves.

The request body is a provider-neutral JSON object:

```json
{"schema":"mana_chess.operational_alert.v1","service":"mana_chess_online","environment":"production","release":"abc123","level":"error","event":"database_query_failed","occurred_at":"2026-07-17T20:01:02.345Z","metadata":{"component":"postgres","reason_class":"DBConnection.ConnectionError"}}
```

The metadata uses the same fixed allowlist as operational logs. The URL, bearer token, request bodies, player/game identifiers, Steam tickets, cookies, database URLs, and provider response bodies are never included. `GET /health` exposes only aggregate state under `operations.alerting`: enabled/running, levels, queue use, delivered/failed/dropped counts, and stable last-failure data.

Before launch, point staging at the intended receiver, trigger a controlled synthetic error in a private maintenance window, confirm routing and ownership, then configure production. A configured receiver does not replace Railway deployment/crash notifications.

## Persistence verification

Run the verifier inside a deployed service. It is read-only and outputs migration counts plus aggregate row counts, never row contents:

```powershell
railway ssh --service Mana-chess --environment staging -- sh /app/bin/verify-persistence
```

A successful line contains `"ready":true`, zero pending migrations, and counts for `steam_users`, `steam_entitlements`, `match_summaries`, `player_ratings`, and `system_settings`. Any database exception is reduced to a stable error code.

Capture the verifier output for the backup baseline and disposable recovery database, then compare them from the Phoenix project:

```powershell
mix mana_chess.compare_persistence_reports baseline.json recovery.json
```

The task accepts UTF-8, UTF-8 BOM, and PowerShell UTF-16 JSON files. It exits non-zero for unreadable/invalid reports, migration drift, or any expected table-count mismatch. A matching report contains `"code":"reports_match"`. A packaged release can run the same check when `MANA_CHESS_PERSISTENCE_BASELINE_REPORT` and `MANA_CHESS_PERSISTENCE_RECOVERY_REPORT` point at the two files:

```sh
bin/compare-persistence-reports
```

## Restore rehearsal

1. Run the verifier against production and record its timestamp, release, migration count, and table counts in the private release ticket.
2. Create a Railway Postgres backup according to the active database plan and retention policy.
3. Restore that backup into a disposable recovery environment with its own Postgres service and credentials. Never repoint normal staging or production at each other's database.
4. Deploy the same application commit to the recovery environment and run `verify-persistence` there.
5. Run `mana_chess.compare_persistence_reports` against the report captured from the backup baseline and the restored database. Do not compare a later live-production report and assume writes after the backup should exist in the restore.
6. Exercise health, global settings, leaderboard reads, and one non-rated QA match. Do not use real publisher credentials unless the rehearsal explicitly includes Steam authentication.
7. Record evidence and only then remove the disposable recovery environment.

The verifier prepares this rehearsal; it does not replace a real provider backup, restore, retention policy, or launch-owner sign-off.
