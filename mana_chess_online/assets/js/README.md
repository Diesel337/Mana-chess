# Mana Chess JS modules

This folder is the source map for the browser-side Mana Chess code. Until the app has a real JS bundling step, every standalone file here must have an identical copy in `priv/static/assets/js`.

## Entry point

- `app.js` is only the Phoenix LiveView bootstrap and hook registry.
- `LocalStats` is registered from `local_stats_hook.js`.
- `BoardDrag` is registered from `board_drag_hook.js`.

## Hook facades

- `local_stats_hook.js` exposes the Phoenix `LocalStats` hook methods and keeps backward-compatible method names used by the smaller helpers.
- `board_drag_hook.js` exposes the Phoenix `BoardDrag` hook methods.

## Feature modules

- `board_drag.js`: pointer drag, legal move previews, drag ghost, invalid drag feedback.
- `chat.js`: chat timestamps and sticky scroll behavior.
- `cosmetics.js`: modular cosmetic UI controller when the richer cosmetic system is active.
- `cosmetic_actions.js`: DOM action handlers for unlocks, skins, palettes, packs, and sound actions.
- `cosmetic_fallback.js`: local fallback implementation for skins, packs, palettes, and previews.
- `desktop_bridge.js`: raw desktop/Steam bridge, metadata, dedupe, and event sending.
- `invite_clipboard.js`: invite link copy and desktop clipboard fallback.
- `local_stats.js`: local match stats storage and rendering.
- `navigation.js`: view-key, tab/frame persistence, and scroll-to-top helpers.
- `result_recording.js`: result-to-stats recording plus desktop `match.finished` event.
- `sound.js`: local sound storage, sound UI rendering, and tone playback.
- `sound_state.js`: derives sound state from LiveView dataset values and picks changed sounds.

## Session adapters

Adapters connect hook instances to feature modules. They keep the hook facade small and make dependency boundaries easier to read.

- `cosmetic_session.js`: connects `LocalStats` to `cosmetics`, `cosmetic_actions`, and `cosmetic_fallback`.
- `desktop_session.js`: connects hook state to `desktop_bridge`.
- `local_stats_events.js`: binds and unbinds DOM events for `LocalStats`.
- `local_stats_lifecycle.js`: owns `LocalStats` mounted/updated/destroyed flow.
- `sound_session.js`: connects hook state to `sound` and `sound_state`.
- `stats_session.js`: connects `local_stats` and `result_recording`.
- `view_session.js`: connects `chat` and `navigation`.

## Load order

The script order in `lib/mana_chess_online_web/components/layouts/root.html.heex` matters:

1. Bridges and base controllers: `desktop_bridge`, `desktop_session`, `navigation`.
2. Cosmetics: `cosmetics`, `cosmetic_actions`, `cosmetic_fallback`, `cosmetic_session`.
3. Phoenix runtime: `phoenix`, `phoenix_live_view`.
4. Stats and lifecycle: `local_stats`, `local_stats_events`, `local_stats_lifecycle`, `result_recording`, `stats_session`, `local_stats_hook`.
5. Sound, view, clipboard, board: `sound`, `sound_state`, `sound_session`, `chat`, `view_session`, `invite_clipboard`, `board_drag`, `board_drag_hook`.
6. `app.js` last.

## Change checklist

- Edit the source file in `assets/js`.
- Apply the same change to `priv/static/assets/js`.
- Update the cache-buster in `root.html.heex` when the browser needs a new asset.
- Update `test/mana_chess_online_web/controllers/page_controller_test.exs` for new cache-busters.
- Run JS syntax checks for touched files and `mix test`.
