# Mana Chess architecture map

This file is the human entry point for the repo. It explains where the main pieces live, what owns game state, and which modules are the next candidates for decomposition.

## Repository layout

- `mana_chess_online/`: Phoenix web app, online lobby, game runtime, admin, assets, deploy target.
- `mana_chess_desktop/`: Electron desktop wrapper for Steam-oriented releases.
- `STEAM_ROADMAP.md`: Steam launch roadmap and staged work.
- `STEAM_RELEASE_CHECKLIST.md`: release checklist for Steam candidates.

Railway deploys from `mana_chess_online/`, not from the repository root.

## Online app

The Phoenix app is the production game service.

- `lib/mana_chess_online/`: domain/runtime modules.
- `lib/mana_chess_online_web/`: router, controllers, LiveViews, components, plugs.
- `assets/`: source CSS and browser JS.
- `priv/static/`: served static assets. Until a JS bundling step exists, standalone files in `assets/js` must be mirrored in `priv/static/assets/js`.
- `test/`: ExUnit coverage for game logic, lobby/runtime behavior, routes, and LiveViews.

Useful docs:

- `mana_chess_online/README.md`: Phoenix commands, launch access gate, stress smoke.
- `mana_chess_online/GAME_DESIGN.md`: game design notes.
- `mana_chess_online/assets/js/README.md`: browser JS module map and asset checklist.
- `mana_chess_online/AGENTS.md`: Phoenix/Elixir coding rules generated for the app.

## Backend runtime map

Live `GameServer` processes are the source of truth for active matches. New runtime decisions must read or mutate the live game process rather than stale lobby mirrors.

- `game_server.ex`: per-game GenServer wrapper and live state owner.
- `game_supervisor.ex`: starts and supervises game processes.
- `game_registry.ex`: names game processes.
- `game_directory.ex`: lookup helpers for active game processes.
- `game_lobby_actions.ex`: lobby-facing game actions for reset requests, start countdowns, ready confirmations, and promotions.
- `game_broadcast.ex`: PubSub topics, broadcast-change predicates, and emitters for room/lobby payloads.
- `game_chat.ex`: room chat sanitization, player names, roles, and lobby log labels.
- `game_lobby_chat.ex`: lobby chat flow and its rate limit for sanitizing and appending room chat entries.
- `game_control.ex`: turn/color/bot-control predicates and basic move-gate validation.
- `game_lobby_servers.ex`: helpers for syncing, listing, reading, replacing, enqueueing, ticking, updating, assignment lookup, and stopping live game servers.
- `game_lobby_runtime.ex`: boundary for live snapshots, public views, runtime topics, metrics process lists, and lobby/game broadcasts.
- `game_lobby_presence.ex`: join/watch/leave flows, presence rate limits, and public-lobby change detection.
- `game_lobby_matchmaking.ex`: requested seating, open-seat matchmaking, private-room creation, and their rate limits.
- `game_lobby_rooms.ex`: lobby-state room lifecycle operations for seating, leaving, authorized clearing, resetting, practice rooms, and private rooms.
- `game_lobby_settings.ex`: lobby/admin settings flow for global settings, practice refreshes, and player-controlled room settings.
- `game_lobby_tick.ex`: lobby tick reducer for live game ticking, changed-game detection, lobby-change detection, and rate-limit pruning.
- `game_lobby_moves.ex`: rate-limited move enqueue/rejection flow that validates player control, cooldowns, legal destinations, and logs rejected moves.
- `game_lobby_practice.ex`: lobby practice-mode flow for starting practice games, toggling bots, and swapping player/BOT sides.
- `game_lobby_view.ex`: public lobby/game/player/spectator payload and current-view builders.
- `game_rooms.ex`: room constructors, occupancy/open-slot helpers, readiness/status helpers, room permissions, seat/private-room lifecycle, and room reset/clear states.
- `game_promotion.ex`: promotion choice normalization by color.
- `game_lobby.ex`: public API and GenServer callback coordinator. It delegates rules, live reads, state transitions, views, and broadcasts to focused modules.
- `game_state.ex`: game state struct and state helpers.
- `game_settings.ex`: global/default settings sanitization, migration, persistence, and elixir helpers.
- `game_engine.ex`: move application, turns, mana, cooldown, and core mutations.
- `game_rules.ex`: movement legality and board rules.
- `game_bot.ex`: practice bot behavior.
- `game_tick.ex`: tick/cooldown helpers.
- `game_metrics.ex`: metrics and snapshots.
- `game_players.ex`: player assignment map helpers.
- `rate_limiter.ex`: request/action throttling and rate-limit state updates.

## Lobby modularization checkpoint

The Steam-launch backend modularization pass is complete. `GameLobby` intentionally keeps the public API and callback order visible in one place, but it no longer owns private matchmaking, presence, room-clear, live-read, view, broadcast, chat-limit, or move-limit helpers.

The normal request path is:

1. `GameLobby` receives the synchronous call and coordinates the reply/effects.
2. A focused `GameLobby*` flow module applies policy and state transitions.
3. `GameLobbyServers` reads or mutates the live `GameServer` process.
4. `GameLobbyRuntime` builds public payloads and emits updates when required.

Keep new game rules out of `GameLobby` callbacks. Add them to the focused flow/domain module and cover that module directly, then retain an integration assertion in `game_lobby_test.exs` for cross-process behavior.

Current large UI module:

- `game_live.ex`: still the broadest LiveView module. Split it along event/assign/component boundaries only while implementing the next responsive game UX; it is no longer a prerequisite for returning to Steam packaging.

## Web/UI map

- `router.ex`: public game routes and admin route.
- `live/game_live.ex`: main lobby/game LiveView.
- `live/admin_live.ex`: admin UI for configuration and runtime controls.
- `components/layouts/root.html.heex`: root layout and browser JS load order.
- `components/core_components.ex`: shared Phoenix components.
- `controllers/page_controller.ex`: non-LiveView page endpoints.
- `plugs/`: request gates such as Steam launch access.

Browser JS is intentionally modular. Start with `mana_chess_online/assets/js/README.md` before changing frontend behavior.

## Desktop app

The desktop app is an Electron wrapper around the production or local Phoenix app.

- `mana_chess_desktop/src/`: Electron main/preload/runtime code.
- `mana_chess_desktop/scripts/`: checks, packaging verification, and smoke scripts.
- `mana_chess_desktop/build/`: app icons and build assets.
- `mana_chess_desktop/steam/`: non-secret SteamPipe templates.
- `mana_chess_desktop/dist/`: generated local build artifacts; do not treat as source.

Windows packaging goes through `scripts/run-electron-builder.cjs`, which prepares the pinned resource-editing tool cache before invoking electron-builder. `scripts/verify-win-executable-resources.cjs` verifies the product metadata and Mana Chess icon embedded in the generated executable.

Useful commands are documented in `mana_chess_desktop/README.md`.

## Change workflow

For backend-only changes:

```powershell
cd mana_chess_online
$env:PATH = "$env:USERPROFILE\.elixir-install\installs\otp\28.1\bin;$env:USERPROFILE\.elixir-install\installs\elixir\1.19.5-otp-28\bin;$env:PATH"
mix test
```

For frontend JS changes:

- Edit `mana_chess_online/assets/js/...`.
- Mirror the same change in `mana_chess_online/priv/static/assets/js/...`.
- Update the cache-buster in `lib/mana_chess_online_web/components/layouts/root.html.heex` when browser assets need a forced refresh.
- Update the cache-buster expectation in tests.
- Run syntax checks for touched JS files and `mix test`.
- For new visual behavior, verify resize/fit before deploy.

For desktop changes:

```powershell
cd mana_chess_desktop
npm run check
```

Use the stronger desktop smoke/build commands from `mana_chess_desktop/README.md` when touching packaging, window mode, deep links, offline recovery, Steam bridge, icons, or release artifacts.

## Deployment notes

- Production URL: `https://mana-chess-production.up.railway.app`
- Railway root: `mana_chess_online`
- Production-bound changes should be pushed and deployed.
- After deploy, verify production responds successfully.
- Backend-only changes do not require resize/fit checks.
- Visual changes require responsive fit checks before deploy.

## Next engineering priorities

1. Treat backend lobby modularization as complete unless a concrete behavior exposes a missing boundary.
2. Resume the Steam roadmap with desktop build verification, production/offline launch flow, real executable icon, and window/fullscreen behavior.
3. Modularize `game_live.ex` opportunistically while implementing the responsive board and compact match layout.
4. Keep frontend browser modules aligned with `assets/js/README.md` and desktop release work inside `mana_chess_desktop/`.
