# Mana Chess persistence runbook

Mana Chess can run in two explicit modes:

- `memory`: current QA-compatible mode. Active games and global settings keep their existing in-memory/file behavior.
- `postgres`: durable Steam identities, entitlements, match summaries, and global settings through Ecto.

Active match snapshots are not restored from Postgres yet. Enabling this layer does not make an in-progress game survive a deploy.

## Modules

- `ManaChessOnline.Persistence`: public boundary and sanitized health state.
- `ManaChessOnline.Persistence.Writer`: supervised, non-blocking write worker. Database write failures never crash authentication or a `GameServer`.
- `ManaChessOnline.Persistence.Event`: validates and converts runtime values into database-safe events.
- `ManaChessOnline.Persistence.EctoStore`: Postgres reads and idempotent upserts.
- `ManaChessOnline.Repo`: Ecto repository.
- `ManaChessOnline.Release`: release migration entry point.
- `ManaChessOnline.GamePersistence`: detects the first transition into a terminal match state.

## Tables

- `steam_users`: one row per verified SteamID, current owner/license metadata, first and last authentication timestamps.
- `steam_entitlements`: active/revoked Steam DLC or inventory grants. The unique key is user, source, and external ID.
- `match_summaries`: one immutable row per observed terminal match transition.
- `system_settings`: versioned operational settings. `global_game_settings` replaces the JSON file as the primary read when Postgres is enabled.

Raw Steam tickets, publisher keys, QA bypass keys, cookies, and database URLs are never persisted in these tables.

## Railway activation

1. Add a PostgreSQL service to the Mana Chess Railway project.
2. Expose its connection string to the Phoenix service as `DATABASE_URL` through a Railway reference variable.
3. Keep `MANA_CHESS_PERSISTENCE_ENABLED=true` explicit for launch environments. In production it also auto-enables when `DATABASE_URL` is non-empty.
4. Optionally set `POOL_SIZE` between 1 and 50. The default is 10.
5. Set `MANA_CHESS_DATABASE_SSL=true` only when the selected Postgres endpoint requires TLS.
6. Deploy. Railway runs `sh /app/bin/migrate` before it starts the server.
7. Confirm `GET /health` reports `persistence.mode=postgres` and `persistence.ready=true`.

Do not paste `DATABASE_URL` into source, logs, tickets, or chat.

## Local commands

PowerShell example:

```powershell
$env:DATABASE_URL="postgresql://user:password@localhost/mana_chess_dev"
$env:MANA_CHESS_PERSISTENCE_ENABLED="true"
mix ecto.create
mix ecto.migrate
mix phx.server
```

Release migration:

```sh
bin/migrate
```

The migration command exits successfully without touching a database when persistence is disabled.

## Failure behavior

- Steam authentication issues its signed session before any database result is needed.
- Match completion is sent to the writer after the `GameServer` commits its live state.
- Global settings always keep the current JSON fallback; Postgres becomes the preferred read only when enabled.
- Entitlement reads fail closed with `503` if persistence is disabled or unavailable.
- `/health` returns `503` when Postgres is enabled but cannot answer `SELECT 1`; Railway will not route a failed deployment.

## Rollback and backup

Before a destructive migration, take a Railway/Postgres backup and test restore in a non-production environment. Application rollback should normally deploy the previous Git commit without rolling the schema back because the initial migration is additive.

For an intentional schema rollback from a release console:

```elixir
ManaChessOnline.Release.rollback(ManaChessOnline.Repo, migration_version)
```

Never roll back a schema that contains production entitlements or match history without a verified backup and an explicit data migration plan.

## Remaining work

- Provision and verify the real Railway Postgres service.
- Sync real Steam DLC/inventory ownership into `steam_entitlements`.
- Make paid cosmetics consume the entitlement endpoint instead of local unlock state.
- Decide, design, and test active-match snapshot restoration.
- Add scheduled backups, restore rehearsal, retention, and production alerting.
