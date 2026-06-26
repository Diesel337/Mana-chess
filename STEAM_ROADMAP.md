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
- Local desktop state for QA/Steam-ready hooks.
- Cosmetic shop prototype with local unlocks and palette previews.
- Chat, private links, spectator flow, practice, tutorial, bot, local stats, sound.

Current constraint:

- `ManaChessOnline.GameLobby` is a single GenServer holding lobby, active games, practice games, private games, admin settings, chat, and bot ticks in memory. This is fine for prototype traffic, but it is not the final launch architecture for heavy multiplayer traffic.

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

Before launch, add a real Steam identity layer:

- Read Steam user identity from the desktop app.
- Send a signed/verified session token to the Phoenix backend.
- Bind local player identity to SteamID.
- Gate commercial features through Steam ownership/DLC/inventory checks.
- Keep QA/staging bypass explicit and disabled for production launch builds.

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

### Phase 1: Prepare architecture without behavior changes

Goal: make the code ready to split game state safely.

- Extract pure game state operations from `GameLobby` where possible.
- Define a `GameServer` API that mirrors current calls.
- Add tests around lobby, join/sit, private matches, chat, reset, bot, and moves.
- Keep current visible behavior stable.

### Phase 2: One process per game

Goal: remove the single global bottleneck.

- Add `ManaChessOnline.GameServer` as a GenServer per game.
- Add `ManaChessOnline.GameSupervisor` as a DynamicSupervisor.
- Add a Registry keyed by `game_id`.
- Move board state, elixir, cooldowns, queue, chat, bot timers, and match status into each `GameServer`.
- Keep a separate lobby/matchmaking process for public rooms and discovery.
- Broadcast only changed game/lobby events.

### Phase 3: Persistence

Goal: survive deploys, crashes, and real users.

- Add Postgres/Ecto.
- Persist Steam users.
- Persist entitlements/inventory.
- Persist match summaries and stats.
- Persist active match snapshots if reconnection after deploy matters.
- Move admin/global settings out of local JSON file.

### Phase 4: Horizontal scaling

Goal: multiple app instances.

- Configure distributed PubSub or Redis-backed coordination.
- Make game routing stable by `game_id`.
- Ensure only one server owns a given active game.
- Add presence tracking per room.
- Add deployment strategy that does not kill active games without warning or snapshot.

### Phase 5: Load and abuse testing

Goal: know limits before Steam traffic.

- Simulate LiveView clients in lobby and games.
- Test 100, 500, 1000 concurrent connections.
- Track CPU, memory, mailbox sizes, websocket latency, PubSub fanout, and bot CPU.
- Rate limit chat, joins, moves, private room creation, and reconnect attempts.
- Add structured logs and metrics dashboards.

## Steam-only launch implications

For launch, the Steam app can still load the online Phoenix client, but the public URL should be treated as infrastructure, not marketing.

Needed before release candidate:

- Production mode flag such as `MANA_CHESS_STEAM_REQUIRED=true`.
- Desktop/Steam-authenticated sessions can play.
- QA sessions require explicit admin/QA bypass.
- Direct public web access gets a Steam-required screen or limited non-commercial preview.
- Cosmetic paid state comes from Steam ownership/DLC/inventory, not local storage.

## Release checklist

See `STEAM_RELEASE_CHECKLIST.md` for the operational Steam release gate list.

## Suggested next cuts

1. Keep this roadmap and `STEAM_RELEASE_CHECKLIST.md` current.
2. Create the first backend safety tests around current `GameLobby` behavior.
3. Extract a `GameServer` module behind the existing `GameLobby` API.
4. Split practice/private game ownership into per-game processes.
5. Add Ecto/Postgres for Steam users and entitlement records.
6. Add a production gate for Steam-required access while preserving QA/staging access.
7. Integrate real Steamworks identity and achievements.
8. Convert local cosmetic unlocks into Steam entitlement-aware unlocks.
9. Run load tests and tune infrastructure before release.

## Non-goals for now

- No public web launch.
- No web payment flow.
- No non-Steam account system unless it supports backend QA/admin.
- No marketplace or trading.
- No gameplay advantage monetization.
- No large backend rewrite without tests around current multiplayer behavior.