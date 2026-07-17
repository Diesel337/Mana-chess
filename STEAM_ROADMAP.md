# Mana Chess Steam Roadmap

## Product stance

Mana Chess is targeting a Steam-first launch. The deployed web app remains a QA/staging surface and online service host while the commercial product is the Steam desktop app.

That means:

- Do not treat the public web URL as the product storefront.
- Do not add non-Steam checkout flows for launch.
- Do not depend on local browser storage for paid inventory at launch.
- Use the web deployment for staging, multiplayer backend, QA, admin, and online delivery behind the desktop shell.
- The Steam app should become the trusted entry point for players, identity, entitlements, achievements, and future purchases.

## Current baseline

Already in place:

- Phoenix LiveView online game deployed on Railway.
- Electron desktop wrapper for Mana Chess.
- Desktop mode via `?desktop=1`.
- `manachess://` deep links.
- Desktop bridge exposed as `window.ManaChessDesktop`.
- Reproducible Windows packaging, clean-commit candidate gate, release doctor, installer lifecycle QA, Steam depot inventory, safe SteamPipe preview, and guarded upload commands.
- A Windows 0.2.0 candidate has passed the complete local preflight, including install/uninstall, window modes, Steam environment metadata, deep links, bridge, reconnect, and offline recovery.
- Main-process Steamworks runtime, one-use Web API ticket exchange, backend ticket/ownership verification, signed Steam sessions, and SteamID-bound player identity.
- Real LiveView/WebSocket capacity runs pass locally through 500 competitive matches and 1,000 connected clients with moves, health sampling, and cleanup.
- Railway production uses Postgres with migration and readiness gates.
- Local desktop state for QA/Steam-ready hooks.
- Cosmetic shop prototype with local unlocks and palette previews.
- Chat, private links, spectator flow, practice, tutorial, bot, local stats, sound.

Current constraints:

- Active match state is owned by supervised per-game `GameServer` processes; `GameLobby` now coordinates the public API, discovery, policy flows, and global settings through focused modules.
- Active matches still live in memory on one application node. Railway Postgres covers Steam users, entitlement records, terminal match summaries, ratings, and global settings, but active-game restoration, horizontal ownership, and production-sized staging load remain launch work.

The remaining critical path is external setup: Steamworks onboarding, real app/depot IDs, publisher credentials, Steamworks SDK/SteamCMD, a restricted build account, Authenticode signing, Railway staging, and a two-account Steam-client rehearsal. See [`STEAM_LAUNCH_RUNBOOK.md`](STEAM_LAUNCH_RUNBOOK.md).

## Steam launch requirements

### Partner and store setup

- Create or finish Steamworks partner onboarding.
- Complete tax, legal, company/person identity, and bank information.
- Pay Steam Direct app credit for Mana Chess.
- Create the Steam app, package, depots, and release checklist.
- Prepare store capsules, screenshots, trailer, description, tags, languages, requirements, privacy policy, and support contact.
- Keep Steam official docs as source of truth for fee, review, wait times, and release rules:
  - https://partner.steamgames.com/doc/gettingstarted/appfee
  - https://partner.steamgames.com/doc/gettingstarted/onboarding
  - https://partner.steamgames.com/doc/store/review_process
  - https://partner.steamgames.com/doc/sdk/uploading

### Desktop build

- Keep Windows as the first target.
- Verify icon, installer, app id, deep links, fullscreen/window behavior, and uninstall behavior.
- Add a launch smoke test for:
  - lobby load
  - private match link
  - reconnect
  - sound toggle
  - cosmetics preview
  - desktop state copy/reset
  - deep link open
- Add a clear offline/error screen for failed online service load.
- Decide if launch is online-required. Current architecture implies online-required.

### Steam identity and entitlement

The base identity layer is implemented:

- Electron reads Steam identity and creates a one-use Web API ticket in the main process.
- Phoenix authenticates the ticket with Valve, verifies active ownership, and issues its own signed session.
- The session binds game player identity to SteamID and satisfies the `steam_required` launch gate.
- Tickets are canceled after one request, publisher keys remain server-only, and the auth origin is pinned to production unless an explicit loopback QA override is enabled.

Before release, run this flow with the real AppID/publisher key from an internal Steam branch, then add DLC/inventory-backed commercial entitlements and disable QA bypasses in the launch environment.

Practical launch rule:

- Web visitors without Steam context should not get the full commercial game experience in production launch mode. They can see a Steam-required screen, QA login, or limited staging access depending on environment.

## Monetization path

Preferred v1:

1. Paid Steam app, or
2. Steam DLC cosmetic pack.

Recommended first monetized content:

- Premium board skins.
- Premium piece skins.
- Premium palette/custom color editor.
- Profile/banner cosmetic later.

Avoid for v1:

- Web checkout.
- Pay-to-win mechanics.
- Consumables.
- Real-money marketplace.
- Complex in-game currency.

If in-game purchases are added later:

- Use Steam Wallet / Steam microtransaction APIs.
- Persist purchases server-side.
- Validate receipts and entitlement state with Steam.
- Keep refund/revocation handling.
- Treat local unlocks as preview/dev only.

Official reference:

- https://partner.steamgames.com/doc/features/microtransactions

## Backend scale roadmap

### Phase 1: Prepare architecture without behavior changes (complete)

Goal: make the code ready to split game state safely.

- [x] Extract pure game state operations from `GameLobby` where possible.
- [x] Define a `GameServer` API that mirrors current calls.
- [x] Add tests around lobby, join/sit, private matches, chat, reset, bot, and moves.
- [x] Keep current visible behavior stable.

### Phase 2: One process per game (core migration complete)

Goal: remove the single global bottleneck.

- [x] Add `ManaChessOnline.GameServer` as a GenServer per game.
- [x] Add `ManaChessOnline.GameSupervisor` as a DynamicSupervisor.
- [x] Add a Registry keyed by `game_id`.
- [x] Make each `GameServer` authoritative for board state, elixir, cooldowns, queue, chat, bot ticks, and match status.
- [x] Keep lobby/matchmaking coordination separate from per-game live ownership.
- [x] Scale rating-aware quick match beyond the four visible rooms with capacity-guarded dynamic games and TTL cleanup.
- [~] Continue tuning changed-only broadcasts and launch telemetry under real-client load.

### Phase 3: Persistence

Goal: survive deploys, crashes, and real users.

- [x] Add optional Postgres/Ecto, additive migrations, a release migration command, and Railway readiness.
- [~] Persist Steam users. Verified identities enqueue safe upserts; real Railway database and AppID rehearsal remain.
- [~] Persist entitlements/inventory. Schema, idempotent upsert event, and authenticated read contract exist; Steam DLC/inventory sync remains.
- [~] Persist match summaries and stats. Terminal transitions enqueue immutable summaries; production database activation and aggregate stats remain.
- [ ] Persist active match snapshots if reconnection after deploy matters.
- [~] Move admin/global settings out of local JSON. Postgres is the preferred read when enabled and the JSON file remains a compatibility fallback.

### Phase 4: Horizontal scaling

Goal: multiple app instances.

- Configure distributed PubSub or Redis-backed coordination.
- Make game routing stable by `game_id`.
- Ensure only one server owns a given active game.
- Add presence tracking per room.
- Add deployment strategy that does not kill active games without warning or snapshot.

### Phase 5: Load and abuse testing

Goal: know limits before Steam traffic.

- [x] Simulate paired LiveView clients through private rooms and the real competitive queue.
- [~] Test 100, 500, and 1000 concurrent connections. Local private-room and competitive-queue tiers pass through 1,000 clients; production-sized Railway staging remains.
- [~] Track CPU, memory, mailbox sizes, WebSocket latency, PubSub fanout, and bot CPU. Core and client runners cover most local signals; staging dashboards remain.
- [~] Rate limit chat, joins, moves, private room creation, and reconnect attempts. Core actions are guarded; reconnect-specific validation remains.
- [ ] Add structured logs and metrics dashboards.

## Steam-only launch implications

For launch, the Steam app can still load the online Phoenix client, but the public URL should be treated as infrastructure, not marketing.

Needed before release candidate:

- `MANA_CHESS_LAUNCH_ACCESS=steam_required` is enabled only for launch rehearsals or release mode.
- Desktop/Steam-authenticated sessions can play.
- QA sessions require explicit `MANA_CHESS_QA_BYPASS_KEY` access.
- Direct public web access gets a Steam-required screen or limited non-commercial preview.
- Cosmetic paid state comes from Steam ownership/DLC/inventory, not local storage.

## Release checklist

See `STEAM_RELEASE_CHECKLIST.md` for the operational Steam release gate list.

## Suggested next cuts

1. Finish Steamworks onboarding, create the app/depot IDs and publisher key, install the latest SDK/SteamCMD, set the build account, and drive `npm run steam:doctor` to zero internal blockers.
2. Configure the matching AppID/key on desktop and Railway, then rehearse the implemented identity/ownership gate from the real Steam client.
3. Acquire the Windows release certificate, pass `MANA_CHESS_REQUIRE_SIGNED=1`, and repeat the automated installer lifecycle on a separate clean machine.
4. Upload the first candidate to a private internal branch and verify overlay, deep links, window modes, reconnect, lobby, private match, and SteamID binding.
5. Integrate the first Steam achievements and cloud-save decision.
6. Provision Railway Postgres and verify the implemented users, entitlements, match-summary, settings, migration, and health flows.
7. Convert local cosmetic unlocks into Steam entitlement-aware unlocks.
8. Decide and implement active-match recovery, then run real WebSocket/Steam-client load tests before release.

## Non-goals for now

- No public web launch.
- No web payment flow.
- No non-Steam account system unless it supports backend QA/admin.
- No marketplace or trading.
- No gameplay advantage monetization.
- No large backend rewrite without tests around current multiplayer behavior.
