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
- [~] Windows unpacked build works.
- [~] Deep links `manachess://` exist.
- [~] Desktop bridge exists.
- [~] Local desktop QA state exists.
- [ ] Final app icon is approved.
- [ ] Installer is tested on a clean Windows machine.
- [ ] Uninstall behavior is tested.
- [ ] Window restore, maximize, fullscreen, and relaunch behavior are tested.
- [ ] Offline/error screen is acceptable for online-required launch.
- [ ] Steam launch option points to the correct executable.
- [ ] Desktop build has a clear app version strategy.
- [ ] Crash/error logs are accessible for QA.
- [ ] Steam overlay compatibility is checked.
- [ ] Build can be reproduced from a clean checkout.

## 5. SteamPipe and depots

- [ ] SteamCMD is installed for release build upload.
- [ ] Windows depot is configured.
- [ ] Build scripts are created and stored outside secrets.
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
- [ ] Web QA bypass is explicit and protected.
- [ ] Production launch mode blocks full commercial play without Steam context.
- [ ] Public web URL shows Steam-required or limited QA-safe surface.
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
- [~] Split lobby discovery from per-game state.
- [ ] Move bot ticks into per-game processes or workers.
- [ ] Broadcast only changed game/lobby state.
- [ ] Add rate limits for chat, joins, moves, private room creation, and reconnects.
- [ ] Add metrics for websocket latency, process mailbox sizes, game count, memory, CPU, PubSub fanout, and bot CPU.
- [ ] Load test 100 concurrent connections.
- [ ] Load test 500 concurrent connections.
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