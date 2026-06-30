# Mana Chess Steam Release Checklist

This checklist tracks the Steam-only launch path. The public web deployment is QA/staging/backend infrastructure, not the commercial storefront for v1.

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

- [~] Electron desktop wrapper exists.
- [x] Windows unpacked build works.
- [~] Deep links `manachess://` exist. `npm run smoke:win:deep-link` now verifies the packaged executable resolves a startup game link to the expected desktop route; real Steam client/deep-link QA still pending.
- [~] Desktop bridge exists.
- [~] Local desktop QA state exists.
- [~] Final app icon is approved. `npm run verify:win:installer` now validates `build/icon.png`, `build/icon.ico`, and package icon wiring; final visual approval still pending.
- [~] Installer is tested on a clean Windows machine. `npm run verify:win:installer` now builds and verifies the NSIS installer artifact without launching it and writes local SHA256 release hashes; clean-machine install pass still pending.
- [ ] Uninstall behavior is tested.
- [~] Window restore, maximize, fullscreen, and relaunch behavior are tested. `npm run smoke:win:modes` now covers packaged launch/log smoke for windowed, maximized, and fullscreen; `npm run release:win:preflight` includes it for release candidates. Manual restore and relaunch QA still needed.
- [~] Offline/error screen is acceptable for online-required launch. `npm run smoke:win:offline` verifies the packaged app reaches the offline path and writes QA logs; `npm run release:win:preflight` includes it for release candidates. Visual/copy review still needed.
- [~] Steam launch option points to the correct executable. SteamPipe docs identify `Mana Chess.exe`; Steamworks launch option still needs live app config.
- [x] Desktop build has a clear app version strategy.
- [x] Crash/error logs are accessible for QA.
- [~] Steam overlay compatibility is checked. Desktop diagnostics now record Steam launch context and `npm run smoke:win:steam` verifies the packaged app captures Steam-like environment variables; real Steam client overlay QA still pending.
- [~] Build can be reproduced from a clean checkout. `npm run verify:win` now checks entry files, writes build metadata, builds unpacked Windows, and verifies the exe; `npm run verify:win:installer` verifies the unpacked exe plus NSIS installer artifact and writes `dist/release-manifest.json`; `npm run release:win:preflight` chains installer/build verification plus window, Steam-env, and offline smokes. Still needs a clean-machine pass.

## 5. SteamPipe and depots

- [ ] SteamCMD is installed for release build upload.
- [~] Windows depot is configured. Non-secret SteamPipe templates point at `mana_chess_desktop/dist/win-unpacked`; real Steamworks app/depot IDs still pending.
- [~] Build scripts are created and stored outside secrets. Templates live in `mana_chess_desktop/steam/`, copied real `.vdf` files, logs, and build output are ignored, and `npm run release:win:preflight` validates the template shape.
- [ ] Internal branch receives first uploaded build.
- [ ] Launch branch policy is defined.
- [ ] Steam build launches successfully from Steam client.
- [ ] Build is submitted to Valve review.
- [ ] Valve build feedback is resolved.
- [ ] Product build is marked ready for release.

Official reference:

- https://partner.steamgames.com/doc/sdk/uploading

## 6. Steam identity and access gate

- [ ] Desktop app can read Steam identity.
- [ ] Backend can verify a Steam-authenticated session.
- [ ] Player identity binds to SteamID.
- [~] Web QA bypass is explicit and protected. `MANA_CHESS_LAUNCH_ACCESS=steam_required` now requires `MANA_CHESS_QA_BYPASS_KEY` for web QA access; real Steam-authenticated sessions still pending.
- [~] Production launch mode blocks full commercial play without Steam context. The launch gate is implemented but stays off by default until Steam identity is wired.
- [~] Public web URL shows Steam-required or limited QA-safe surface. The launch gate returns a Steam-required page in `steam_required` mode; final launch copy and Steam session wiring still pending.
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

Prototype constraint:

- [~] Current multiplayer state is centralized in `ManaChessOnline.GameLobby`.

Release candidate target:

- [x] Add safety tests for current `GameLobby` behavior.
- [x] Extract pure game-state/game-engine helpers where low-risk.
- [x] Add `GameServer` process per game.
- [x] Add `GameSupervisor` DynamicSupervisor.
- [x] Add Registry lookup by `game_id`.
- [~] Split lobby discovery from per-game state. Game processes are mirrored, not authoritative yet.
- [~] Move bot ticks into per-game processes or workers. GameServer now runs the shared tick pipeline and bot decisions; Lobby still mirrors state for views.
- [~] Broadcast only changed game/lobby state. Idle ticks no longer emit unchanged game/lobby payloads.
- [~] Add rate limits for chat, joins, moves, private room creation, and reconnects. Chat, move spam, private room bursts, seat spam, and reconnect/watch bursts are limited; launch tuning still needed after load tests.
- [~] Add metrics for websocket latency, process mailbox sizes, game count, memory, CPU, PubSub fanout, and bot CPU. Admin now exposes a first process/game/memory/mailbox snapshot; websocket latency, PubSub fanout, CPU detail, and bot CPU still need launch telemetry/load tooling.
- [~] Load test 100 concurrent connections. Local logical-client lobby stress script exists and runs 100 players; real WebSocket/Steam-client load still pending.
- [~] Load test 500 concurrent connections. Local logical-client profile 500 passes with 100 practice players, 150 private matches, 100 watchers, and cleanup under a 90s local gate; real WebSocket/Steam-client load and cleanup optimization still pending.
- [ ] Load test 1000 concurrent connections before launch marketing push.

## 9. Persistence and operations

- [ ] Add Postgres/Ecto.
- [ ] Persist Steam users.
- [ ] Persist entitlements/inventory.
- [ ] Persist match summaries and stats.
- [ ] Move admin/global settings out of local JSON.
- [ ] Decide whether active match snapshots are needed across deploys.
- [ ] Add backup/restore plan.
- [ ] Add environment separation for QA/staging/production.
- [ ] Add structured logs.
- [ ] Add error reporting.
- [ ] Add deploy rollback plan.
- [ ] Add incident checklist for launch day.

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
