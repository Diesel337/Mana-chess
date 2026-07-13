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

The backend has been moving toward live `GameServer` processes as the source of truth for active matches. New runtime decisions should prefer the live game process over stale lobby mirrors.

- `game_server.ex`: per-game GenServer wrapper and live state owner.
- `game_supervisor.ex`: starts and supervises game processes.
- `game_registry.ex`: names game processes.
- `game_directory.ex`: lookup helpers for active game processes.
- `game_broadcast.ex`: broadcast-change predicates for room and lobby updates.
- `game_chat.ex`: room chat sanitization, player names, roles, and lobby log labels.
- `game_control.ex`: turn/color/bot-control predicates and board-square validation.
- `game_lobby_servers.ex`: helpers for syncing, listing, reading, replacing, enqueueing, ticking, updating, and stopping live game servers.
- `game_lobby_view.ex`: public lobby/game/player payload builders.
- `game_rooms.ex`: room constructors, room readiness/status helpers, room permissions, private-room predicates, and room reset/clear templates.
- `game_promotion.ex`: promotion choice normalization by color.
- `game_lobby.ex`: lobby coordination, rooms, matchmaking, player/spectator views, broadcasts, and compatibility surface.
- `game_state.ex`: game state struct and state helpers.
- `game_settings.ex`: global/default settings sanitization, migration, persistence, and elixir helpers.
- `game_engine.ex`: move application, turns, mana, cooldown, and core mutations.
- `game_rules.ex`: movement legality and board rules.
- `game_bot.ex`: practice bot behavior.
- `game_tick.ex`: tick/cooldown helpers.
- `game_metrics.ex`: metrics and snapshots.
- `game_players.ex`: player assignment map helpers.
- `rate_limiter.ex`: request/action throttling and rate-limit state updates.

Current large modules:

- `game_lobby.ex`: still the broadest backend module. Split candidates are matchmaking, private matches, room/player views, broadcast payloads, and admin/config operations.
- `game_live.ex`: still the broadest LiveView module. Split candidates are event handlers, assign builders, render helpers, chat, cosmetics, and game action dispatch.

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

## Next modularization targets

1. Continue reducing stale lobby reads by routing remaining critical decisions through live `GameServer` state.
2. Split `game_lobby.ex` into focused modules once a boundary is obvious from tests.
3. Split `game_live.ex` by event groups and assign/render helpers after backend state ownership is stable.
4. Keep frontend browser modules aligned with `assets/js/README.md`.
5. Keep desktop release work isolated inside `mana_chess_desktop/`.
