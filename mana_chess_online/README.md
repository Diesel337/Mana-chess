# ManaChessOnline

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Steam launch access gate

Mana Chess remains open by default for web QA/staging:

```bash
MANA_CHESS_LAUNCH_ACCESS=open
```

For a Steam-only launch rehearsal, set:

```bash
MANA_CHESS_LAUNCH_ACCESS=steam_required
MANA_CHESS_QA_BYPASS_KEY=<private qa key>
MANA_CHESS_STEAM_APP_ID=<steam app id>
MANA_CHESS_STEAM_WEB_API_PUBLISHER_KEY=<publisher key>
```

Optional Steam settings are `MANA_CHESS_STEAM_TICKET_IDENTITY` (default `mana-chess-desktop-v1`) and `MANA_CHESS_STEAM_SESSION_TTL_SECONDS` (default `86400`). The ticket identity must match the desktop runtime. The publisher key belongs only on the Phoenix/Railway service and must never be packaged in Electron.

The desktop first reads `GET /auth/steam/config` with its desktop header. This versioned bootstrap exposes only readiness, AppID, ticket identity, and whether launch access is required; it never exposes the publisher key. Electron verifies that contract and AppID before it requests a ticket. It then posts the one-use hexadecimal ticket to `POST /auth/steam`. Phoenix verifies it with `AuthenticateUserTicket`, checks the active base-app license with `CheckAppOwnership`, renews the signed browser session, and stores only SteamID/owner/AppID/ownership metadata. Raw tickets and publisher keys are not stored in the cookie.

In `steam_required` mode, public lobby/game routes return a Steam-required page unless the request has a current verified Steam session or the QA bypass key is provided with `?qa_key=...` or `x-mana-chess-qa-key`. Verified player identity becomes `steam_<steamid>`. `/admin` remains reachable for its existing admin login. Keep the launch gate `open` until the real AppID/publisher key flow has passed a Steam-client rehearsal.

## Optional Postgres persistence

Production automatically enables the Ecto layer when `DATABASE_URL` is present. It can also be controlled explicitly:

```bash
DATABASE_URL=postgresql://...
MANA_CHESS_PERSISTENCE_ENABLED=true
POOL_SIZE=10
```

`MANA_CHESS_DATABASE_SSL=true` enables TLS when the selected Postgres endpoint requires it. `ECTO_IPV6=true` enables IPv6 socket resolution. Database URLs and credentials belong only in environment variables.

Railway runs `sh /app/bin/migrate` as a pre-deploy command, then checks `GET /health` before routing traffic. With no database configured, the migration is a no-op and health reports ready `memory` mode, so the current production behavior remains available. With Postgres enabled, health returns `503` until the database answers.

The persistence boundary stores verified Steam users, Steam entitlements, terminal match summaries, competitive player ratings, and versioned global game settings. Public matches between two distinct human players update rating and W/L/D records in the same transaction as the terminal match summary. Authentication and `GameServer` state changes enqueue writes through a separate supervised worker; database write errors do not crash those caller processes. `GET /auth/steam/entitlements` requires both the desktop header and a current verified Steam session, and fails closed when durable entitlement state is unavailable.

Quick match prefers an already waiting opponent and, when several are available, chooses the smallest rating difference. The lobby leaderboard shows the top rated players plus the current player's position, but replaces every stored player identity with a server-keyed public alias. `MANA_CHESS_LEADERBOARD_ALIAS_SECRET` can provide a dedicated alias key; production otherwise derives it from `SECRET_KEY_BASE`. Private and practice games never change competitive rating.

The four fixed public rooms remain visible for manual seating. They are no longer the quick-match ceiling: once those rooms have no waiting seat, the lobby creates hidden `match_*` public rooms, pairs the next closest-rated opponent, and starts the existing five-second countdown. Empty queue rooms stop immediately; inactive rooms also expire through the dynamic-room TTL.

```bash
MANA_CHESS_MAX_DYNAMIC_GAMES=250
```

That default is a shared admission ceiling for competitive queue, private, and practice rooms. Together with the four fixed rooms it permits at most 254 admitted game processes, but it is not a throughput guarantee. Isolated Railway staging has passed private and competitive WebSocket scenarios through 500 matches and 1,000 clients; production remains at 250 while launch telemetry and real Steam-client rehearsals are completed. See `bench/README.md` for the measured baseline.

See [`PERSISTENCE.md`](PERSISTENCE.md) for schema ownership, Railway activation, rollback, backup, and remaining active-match snapshot work.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

## Lobby stress smoke

Run a local logical-client stress pass against the in-app lobby process:

```bash
mix run scripts/lobby_stress.exs -- --profile 100
mix run scripts/lobby_stress.exs -- --profile 500
```

Useful options:

```bash
mix run scripts/lobby_stress.exs -- --players 100 --practice 20 --private-pairs 40 --concurrency 32 --settle-ms 500
mix run scripts/lobby_stress.exs -- --players 100 --practice 20 --competitive-pairs 25 --private-pairs 10 --concurrency 32
mix run scripts/lobby_stress.exs -- --profile 500 --max-total-ms 90000 --max-mailbox 10 --max-run-queue 20
mix run scripts/lobby_stress.exs -- --profile 100 --operation-timeout-ms 30000 --json
```

Profiles are local logical-client runs. Profile `500` uses 100 practice players, 75 competitive matches, 75 private matches, and 100 watchers. This is an internal OTP/lobby smoke, not a replacement for real WebSocket or Steam-client load tests.

## LiveView/WebSocket smoke

With Phoenix running locally, exercise the real competitive queue with two LiveView sessions per match:

```bash
pnpm --dir bench liveview -- --mode competitive --matches 10 --ramp-per-second 5 --hold-seconds 15 --output bench/reports/local-competitive-10.json
```

The runner verifies that each pair lands in one fixed or dynamic public room and reports HTTP, assignment, WebSocket join, event, and health latency. See [`bench/README.md`](bench/README.md) for private-room mode, larger local tiers, remote safeguards, and report interpretation.
