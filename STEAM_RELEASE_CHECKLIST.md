# Mana Chess Steam Release Checklist

This checklist tracks the Steam-only launch path. The public web deployment is QA/staging/backend infrastructure, not the commercial storefront for v1.

Execution and rollback steps live in [`STEAM_LAUNCH_RUNBOOK.md`](STEAM_LAUNCH_RUNBOOK.md).

Status key:

- `[ ]` Not started
- `[~]` In progress / prototype exists
- `[x]` Done for release candidate

## 1. Steamworks account and app

- [ ] Steamworks partner onboarding is complete.
- [ ] Legal/tax/bank information is accepted.
- [ ] Steam Direct app credit is paid for Mana Chess.
- [ ] Steam app ID is created.
- [ ] App name, developer, publisher, support contact, and basic metadata are final.
- [ ] Release timing accounts for Steam's required waiting/review windows.
- [ ] Internal roles and Steamworks permissions are assigned.

Official references:

- https://partner.steamgames.com/doc/gettingstarted/appfee
- https://partner.steamgames.com/doc/gettingstarted/onboarding
- https://partner.steamgames.com/doc/store/review_process

## 2. Store page

- [ ] Store page uses only launch-available features.
- [ ] Short description is final.
- [ ] Long description is detailed, coherent, and Steam-safe.
- [ ] Tags and genres match the actual game.
- [ ] Supported languages are honest.
- [ ] Supported platforms match tested builds.
- [ ] System requirements are drafted and checked on a clean Windows machine.
- [ ] Privacy policy URL exists and matches Steam-only/web-backend reality.
- [ ] Screenshots are real gameplay, not mockups or concept art.
- [ ] Trailer shows real gameplay and UI.
- [ ] Capsule images include readable Mana Chess title/logo.
- [ ] Mature content survey is completed.
- [ ] Store page is submitted to Valve review.
- [ ] Valve store feedback is resolved.
- [ ] Store page is marked ready for release.

Official references:

- https://partner.steamgames.com/doc/store/review_process
- https://partner.steamgames.com/doc/store/assets

## 3. Commercial model

Launch target should be one of these:

- [ ] Paid base game.
- [ ] Paid base game plus optional cosmetic DLC.
- [ ] Free base game with Steam DLC cosmetic pack.

For v1, avoid:

- [ ] Web checkout.
- [ ] Non-Steam payment flow.
- [ ] Pay-to-win mechanics.
- [ ] Consumables or in-game currency.
- [ ] Marketplace/trading.

Required if DLC is used:

- [ ] DLC app is created in Steamworks.
- [ ] DLC ownership can be detected in desktop/backend flow.
- [ ] Cosmetic unlocks map to Steam ownership, not local storage.
- [ ] Refund/revocation behavior is defined.

Required if in-game purchases are used later:

- [ ] Steam Wallet / Steam microtransaction flow is implemented.
- [ ] Purchase receipts are validated server-side.
- [ ] Entitlements persist server-side.
- [ ] Steam sandbox purchase testing is complete.

Official reference:

- https://partner.steamgames.com/doc/features/microtransactions

## 4. Desktop build

- [x] Electron desktop wrapper exists and produces a traceable Windows candidate.
- [x] Windows unpacked build works.
- [~] Deep links `manachess://` exist. `npm run smoke:win:deep-link` now verifies startup game links and `npm run smoke:win:second-instance` verifies runtime relaunch handoff to the existing desktop window; real Steam client/deep-link QA still pending.
- [x] Desktop bridge exists. `npm run smoke:win:bridge` verifies the packaged executable exposes `window.ManaChessDesktop`, reads/copies/resets desktop state, reads/copies diagnostics, copies share/deep links, marks desktop mode, and records bridge IPC events.
- [x] Local desktop QA state and capped diagnostics exist.
- [~] Final app icon is approved. Windows builds now embed the Mana Chess icon instead of Electron's default and expose `Mana Chess`/`Diesel337` product metadata; `npm run verify:win` and `npm run verify:win:installer` validate both automatically. Final owner visual approval still pending.
- [~] Installer is tested on a clean Windows machine. `npm run smoke:win:installer` now passes an isolated install, installed-app launch, and uninstall cycle with registry, publisher, shortcuts, protocol, and file checks; a separate clean-machine pass is still pending.
- [ ] Windows executable and installer are signed with the intended release certificate and pass SmartScreen/publisher QA. Current local candidates intentionally remain unsigned.
- [x] Automated uninstall behavior is tested. The NSIS include removes `manachess://`, and the installer smoke verifies uninstall registry, shortcuts, protocol registration, and application files are gone.
- [x] Window restore, maximize, fullscreen, and relaunch behavior are tested. `npm run smoke:win:modes` covers forced packaged launches; `npm run smoke:win:restore` verifies isolated saved bounds and windowed/maximized/fullscreen state without launch overrides; `npm run smoke:win:second-instance` covers single-instance relaunch handoff; the release preflight requires all of them.
- [~] Offline/error screen is acceptable for online-required launch. `npm run smoke:win:offline` verifies the packaged app reaches the offline path and writes QA logs; `npm run smoke:win:reconnect` verifies auto-recovery when the service comes back; `npm run release:win:preflight` includes both for release candidates. Visual/copy review still needed.
- [~] Steam launch option points to the correct executable. SteamPipe config, manifest, and docs identify `Mana Chess.exe`; Steamworks launch option still needs live app config.
- [x] Desktop build has a clear app version strategy.
- [x] Crash/error logs are accessible for QA.
- [~] Steam overlay compatibility is checked. The main process initializes `steamworks.js` and enables its Electron overlay hook when a real AppID is present; diagnostics and `npm run smoke:win:steam` cover the safe metadata path. Real Steam client overlay QA still pending.
- [~] Build can be reproduced from a clean checkout. Windows commands prepare a pinned, SHA256-verified resource-editing cache; `npm run verify:steam-session` checks bootstrap/ticket/session lifecycle; `npm run verify:win` checks syntax, build metadata, native Steam runtime files, embedded product identity, and the icon; `npm run verify:win:installer` adds Authenticode status, NSIS artifacts, and the release manifest; `npm run release:win:candidate` refuses dirty source, runs the complete preflight, and proves the manifest matches the current commit; `npm run steam:doctor` reports remaining machine/backend gates. Still needs a separate clean-machine pass and signed candidate.

## 5. SteamPipe and depots

- [ ] SteamCMD is installed for release build upload. It is not present on the current machine; install it from the latest Steamworks SDK after onboarding and set `STEAMWORKS_SDK_PATH`.
- [~] Windows depot is configured. Generated SteamPipe config points at `mana_chess_desktop/dist/win-unpacked`, requires the executable, app archive, `steam_api64.dll`, and the Steamworks N-API binding, excludes updater/installer-only files and QA state, and records a per-file SHA256 manifest; real Steamworks app/depot IDs still pending.
- [x] Build scripts are created and stored outside secrets. `steam:verify`, `steam:prepare:preview`, `steam:prepare:upload`, `steam:preview`, and `steam:upload` validate the payload, keep generated VDF/log/output files ignored, default to no-upload preview, and gate real upload with an AppID-bound confirmation.
- [ ] Internal branch receives first uploaded build.
- [~] Launch branch policy is defined in tooling. Preview cannot set a branch, `default` is never auto-assigned, and the first real build should be assigned manually to a private internal branch; final Steamworks branch names/permissions remain pending.
- [ ] Steam build launches successfully from Steam client.
- [ ] Build is submitted to Valve review.
- [ ] Valve build feedback is resolved.
- [ ] Product build is marked ready for release.

Official reference:

- https://partner.steamgames.com/doc/sdk/uploading

## 6. Steam identity and access gate

- [~] Desktop app can read Steam identity. `steamworks.js` is initialized only in Electron's main process; Electron negotiates protocol/AppID/ticket identity from Phoenix before ticket issuance and exposes only sanitized SteamID/owner/license diagnostics. Live validation with the real AppID is pending.
- [~] Backend can verify a Steam-authenticated session. Phoenix authenticates one-use Web API tickets, checks current app ownership, renews a signed session, and rejects malformed/expired/legacy markers; live publisher-key QA is pending.
- [~] Player identity binds to SteamID. Verified sessions map to stable `steam_<steamid>` player IDs; a real Steam-client multiplayer rehearsal is pending.
- [~] Web QA bypass is explicit and protected. `MANA_CHESS_LAUNCH_ACCESS=steam_required` accepts only current signed Steam sessions or `MANA_CHESS_QA_BYPASS_KEY`; real Steam-client rehearsal is pending.
- [~] Production launch mode blocks full commercial play without Steam context. The launch gate and Steam session wiring are implemented but remain `open` until real AppID/publisher-key QA passes.
- [~] Public web URL shows Steam-required or limited QA-safe surface. The launch gate returns a Steam-required page in `steam_required` mode; final launch copy and live Steam rehearsal still pending.
- [ ] Steam ownership/DLC/inventory state controls paid cosmetics.
- [ ] Local cosmetic unlocks are marked preview/dev only or disabled in launch mode.

## 7. Gameplay release candidate

- [ ] Lobby flow works from Steam build.
- [ ] Quick online match works from Steam build.
- [ ] Private link match works from Steam build.
- [ ] Practice mode works.
- [ ] Tutorial works.
- [ ] Bot behavior is acceptable.
- [ ] Drag and click movement work.
- [ ] Legal move highlights work.
- [ ] Invalid move feedback is clear.
- [ ] Sound toggle and volume work.
- [ ] Chat works and is rate-limited.
- [ ] Reconnect works after reload.
- [ ] Spectator flow works.
- [ ] Cosmetic preview works.
- [ ] Premium cosmetics are gated correctly.
- [ ] No known layout overlap in desktop, web QA, and mobile QA.

## 8. Backend scalability

Current architecture:

- [x] Active match state is owned by supervised `ManaChessOnline.GameServer` processes; `GameLobby` coordinates discovery, public API calls, global settings, and focused policy flows.
- [~] Active matches remain memory-only on one application node. Optional Postgres persistence now covers durable launch records, while active-game restoration and horizontal ownership remain pending.

Release candidate target:

- [x] Add safety tests for current `GameLobby` behavior.
- [x] Extract pure game-state/game-engine helpers where low-risk.
- [x] Add `GameServer` process per game.
- [x] Add `GameSupervisor` DynamicSupervisor.
- [x] Add Registry lookup by `game_id`.
- [x] Split lobby discovery from authoritative per-game state. Live reads, decisions, mutations, snapshots, metrics, and broadcasts use `GameServer` state.
- [x] Move bot ticks into per-game processes or workers. `GameServer` runs the shared tick pipeline and bot decisions.
- [~] Broadcast only changed game/lobby state. Idle ticks no longer emit unchanged game/lobby payloads.
- [~] Add rate limits for chat, joins, moves, private room creation, and reconnects. Chat, move spam, private room bursts, seat spam, and reconnect/watch bursts are limited; launch tuning still needed after load tests.
- [~] Add metrics for websocket latency, process mailbox sizes, game count, memory, CPU, PubSub fanout, and bot CPU. Admin exposes process/game/memory/mailbox snapshots and production telemetry reports slow HTTP, socket, channel, and Ecto operations; PubSub fanout, CPU detail, bot CPU, and hosted dashboards remain.
- [x] Load test at least 100 concurrent connections locally. Real LiveView/WebSocket private and competitive runners pass above this tier with health sampling and cleanup.
- [x] Load test 500 concurrent connections locally. The competitive queue passes 250 matches, 500 clients, 246 dynamic rooms, opening moves, and cleanup with no setup or health failures.
- [x] Load test 1000 concurrent connections before launch marketing push. Local and isolated Railway staging runs pass 500 matches and 1,000 clients in both private and competitive modes, including moves, health sampling, and cleanup.

## 9. Persistence and operations

- [x] Add Postgres/Ecto. Railway production has a dedicated Postgres service, additive migrations run before deploy, and `/health` reports ready Postgres mode.
- [~] Persist Steam users. Verified authentication emits safe upserts without raw tickets; real database/AppID QA remains.
- [~] Persist entitlements/inventory. Durable model, idempotent writes, and authenticated desktop read endpoint exist; Valve ownership sync and cosmetic consumption remain.
- [~] Persist match summaries and stats. Terminal `GameServer` transitions emit immutable summaries to production Postgres; richer aggregate player stats remain.
- [~] Move admin/global settings out of local JSON. Postgres becomes primary when enabled, with JSON retained as a fail-safe fallback.
- [ ] Decide whether active match snapshots are needed across deploys.
- [~] Add backup/restore plan. `PERSISTENCE.md` and `OPERATIONS.md` define safe additive rollback, a read-only restored-database verifier, and a strict baseline/recovery report comparator; provider scheduling, retention, and the recorded restore rehearsal remain.
- [x] Add environment separation for launch QA/staging and production. Railway staging has a separate domain, Postgres service, database credentials, session secret, and leaderboard alias secret.
- [x] Add structured logs. Production emits bounded one-line JSON with release/environment metadata, while high-volume routine endpoint and socket logs remain suppressed.
- [~] Add error reporting. Phoenix, LiveView, Ecto, persistence, and GameServer recovery events are sanitized, deduplicated, counted in health, retained in Railway logs, and ready for bounded HTTPS webhook delivery; the real endpoint, routing test, and notification ownership remain.
- [~] Add deploy rollback plan. Previous application commits remain schema-compatible and explicit release rollback exists; launch-day rehearsal remains.
- [x] Add incident checklist for launch day. Roles, severity, evidence, rollback, and communication fields are defined in `STEAM_LAUNCH_RUNBOOK.md`.

## 10. Final review gate

Do not submit for release until:

- [ ] Steam-only commercial stance is reflected in product, backend, and docs.
- [ ] Build runs from Steam client on a clean Windows install.
- [ ] Store page does not promise unfinished features.
- [ ] Paid cosmetics/ownership cannot be spoofed with local storage.
- [ ] Public web access cannot bypass Steam launch rules.
- [ ] Multiplayer survives expected launch traffic.
- [ ] Privacy/support/refund-facing details are ready.
- [ ] Internal release candidate is played end-to-end by at least two accounts.
- [ ] Valve store review is ready.
- [ ] Valve build review is ready.
