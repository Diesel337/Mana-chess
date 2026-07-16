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
mix run scripts/lobby_stress.exs -- --profile 500 --max-total-ms 90000 --max-mailbox 10 --max-run-queue 20
mix run scripts/lobby_stress.exs -- --profile 100 --operation-timeout-ms 30000 --json
```

Profiles are local logical-client runs. Profile `500` uses 100 practice players, 150 private matches, and 100 watchers. This is an internal OTP/lobby smoke, not a replacement for real WebSocket or Steam-client load tests.
