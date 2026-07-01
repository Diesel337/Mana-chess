# Mana Chess Desktop

Desktop wrapper for Mana Chess.

## What this is

This is the Steam-oriented desktop build path. It opens the current online game inside a desktop window with desktop layout enabled.

Current game URL:

```text
https://mana-chess-production.up.railway.app/
```

Override the URL for local testing:

```powershell
$env:MANA_CHESS_URL="http://localhost:4000/"
npm start
```

Force a launch window mode for Steam/QA:

```powershell
$env:MANA_CHESS_WINDOW_MODE="fullscreen"
npm start
```

Supported modes are `fullscreen`, `maximized`, and `windowed`. Launch args are also supported:

```powershell
npm start -- --window-mode=windowed
npm start -- --fullscreen
```

Tune the offline retry loop for Steam/QA:

```powershell
$env:MANA_CHESS_OFFLINE_RETRY_SECONDS="20"
npm start
```

Use `0` to disable automatic retry. Launch args are also supported:

```powershell
npm start -- --offline-retry-seconds=0
```

## Commands

Install dependencies:

```powershell
npm install
```

Run locally:

```powershell
npm start
```

Check the Electron entry files:

```powershell
npm run check
```

Create a Windows installer:

```powershell
npm run dist:win
```

Verify the Windows installer artifact without launching it:

```powershell
npm run verify:win:installer
```

`verify:win:installer` checks the icon assets, Electron entry files, writes build metadata, creates the unpacked app plus NSIS installer, verifies `dist/win-unpacked/Mana Chess.exe`, `dist/Mana Chess Setup <version>.exe`, `dist/latest.yml`, and the installer block map, then writes `dist/release-manifest.json` with sizes and SHA256 hashes.

Create an unpacked Windows app for quick testing:

```powershell
npm run pack:win
```

Run the desktop release sanity check:

```powershell
npm run verify:win
```

`verify:win` checks the Electron entry files, writes build metadata, creates the unpacked Windows build, and verifies `dist/win-unpacked/Mana Chess.exe`.

Smoke-test the unpacked app startup:

```powershell
npm run smoke:win
npm run smoke:win -- --mode=maximized
npm run smoke:win -- --mode=fullscreen
npm run smoke:win:steam
npm run smoke:win:modes
npm run smoke:win:deep-link
npm run smoke:win:bridge
npm run smoke:win:offline
```

`smoke:win` launches `dist/win-unpacked/Mana Chess.exe`, waits for a fresh `desktop.session_started` log entry, and closes the launched process. It defaults to the `desktop-smoke` channel so QA can spot smoke runs in `desktop-log.jsonl`.
`smoke:win:steam` launches one windowed smoke with simulated Steam environment variables and verifies they are captured in the session diagnostics.
`smoke:win:modes` runs the same startup smoke through `windowed`, `maximized`, and `fullscreen` in sequence.
`smoke:win:deep-link` launches the packaged app with a `manachess://game/private_smoke_deep_link` URL and verifies the launcher resolves it to a game route in the desktop QA log.
`smoke:win:bridge` launches the packaged app against a local QA page and verifies `window.ManaChessDesktop` can report desktop info, read local desktop state, read diagnostics, mark desktop mode, and send an IPC event back to the main process.
`smoke:win:offline` launches the app against an unreachable local URL, disables auto-retry, waits for `desktop.offline`, and closes the process.

Run the full Windows release preflight before a Steam candidate:

```powershell
npm run release:win:preflight
```

`release:win:preflight` validates the non-secret SteamPipe templates, builds and verifies the unpacked app plus NSIS installer with `verify:win:installer`, then runs the window mode, Steam environment, and offline smoke tests.

## SteamPipe templates

Non-secret upload templates live in `steam/`. They assume the packaged Windows payload is `dist/win-unpacked` and the Steam launch executable is `Mana Chess.exe`.

```powershell
npm run verify:win
cd steam
copy app_build_steam_app.vdf.example app_build_steam_app.vdf
copy depot_build_windows.vdf.example depot_build_windows.vdf
# Edit placeholders with Steamworks app/depot IDs, then:
steamcmd +login <steam_username> +run_app_build .\app_build_steam_app.vdf +quit
```

The real `.vdf` files, SteamCMD logs, and Steam build output are ignored locally. Keep Steam credentials and unpublished app/depot IDs outside git.

## Desktop v2 notes

- The app keeps one Mana Chess window open and focuses it when launched again.
- Window size, position, maximized state, and fullscreen state are restored between sessions.
- Steam/QA can force startup with `MANA_CHESS_WINDOW_MODE`, `--window-mode`, `--fullscreen`, `--maximized`, or `--windowed`.
- `npm run smoke:win:modes` verifies the packaged executable can start and write QA logs in `windowed`, `maximized`, and `fullscreen` launch modes.
- `npm run smoke:win:steam` verifies the packaged executable records Steam launch context when Steam-like environment variables are present.
- `npm run smoke:win:deep-link` verifies the packaged executable resolves a startup `manachess://` game link to the expected desktop route.
- `npm run smoke:win:bridge` verifies the packaged executable exposes the desktop bridge to renderer code and records bridge IPC events.
- Desktop mode is forced with `?desktop=1` on every in-app navigation.
- `manachess://` deep links can open lobby or game routes inside the desktop app.
- External links open in the user's browser; Mana Chess links stay in the app window.
- The offline/error screen offers automatic retry, pause/resume, lobby, copy-link, and browser fallback actions.
- `npm run smoke:win:offline` verifies the packaged executable reaches the offline/error path and writes a QA log entry.
- The Windows build uses the shared Mana Chess icon, app id `com.diesel337.manachess`, and explicit shortcut/uninstall metadata.
- `npm run verify:win:installer` verifies `build/icon.png`, `build/icon.ico`, and package icon wiring before creating release artifacts.
- `npm run verify:win:installer` verifies the NSIS installer artifact exists and has a Windows executable header, without installing it, and writes a local release manifest with artifact hashes.
- The web game can read `window.ManaChessDesktop.getInfo()` for desktop version, channel, platform, origin, and Steam launch detection.
- The window title follows local presence, such as lobby, active match, playing, or result states.
- The desktop menu can copy, open, or reset local desktop QA state.
- The desktop menu can copy QA diagnostics and open the local log folder.
- The desktop menu can copy the current `manachess://` deep link and open the current clean web link in the browser.
- Windows builds include generated release metadata with app version, channel, git commit, dirty state, and optional build time.

Deep link examples:

```text
manachess://lobby
manachess://game/game_1
manachess://game/private_abc123
manachess://private_abc123
```

Shortcuts:

- `Ctrl+L`: back to lobby.
- `Ctrl+Shift+C`: copy the current share link without `desktop=1`.
- Menu `Mana Chess > Copiar deep link desktop`: copy the current `manachess://` route.
- `Ctrl+R`: reload.
- `F11`: fullscreen.
- `Esc`: leave fullscreen.

## Desktop bridge

The preload exposes a small, future-safe API to the remote game:

```js
window.ManaChessDesktop.getInfo()
window.ManaChessDesktop.getState()
window.ManaChessDesktop.getDiagnostics()
window.ManaChessDesktop.copyState()
window.ManaChessDesktop.copyDiagnostics()
window.ManaChessDesktop.openStateFolder()
window.ManaChessDesktop.openLogFolder()
window.ManaChessDesktop.resetState()
window.ManaChessDesktop.copyShareLink(window.location.href)
window.ManaChessDesktop.openShareLink(window.location.href)
window.ManaChessDesktop.copyDeepLink(window.location.href)
window.ManaChessDesktop.sendEvent("match.finished", {result: "win"})
```

`sendEvent` is intentionally a no-op sink for now. It gives us a stable place to attach Steamworks achievements, rich presence, and cloud-save hooks later.

Emitted event names currently include `screen.viewed`, `desktop.offline`, `desktop.offline_screen_viewed`, `desktop.reconnected`, `match.opened`, `match.status_changed`, `match.started`, and `match.finished`.

Desktop state is stored locally in Electron user data as `desktop-state.json`. It tracks session counters, a small event log, current presence, and local achievement flags that can later map to Steamworks achievements. Use the Desktop menu to copy the state, open the data folder, or reset the local state during QA.

Desktop diagnostics are stored in the same Electron user data folder as `desktop-log.jsonl`. The log is capped at 512 KB and records session events, Steam launch context when present, offline load failures, renderer process exits, window unresponsive/responsive events, and renderer console errors. Use `Mana Chess > Desktop > Copiar diagnostico QA` for a clipboard bundle with app/window/state/log context.

## Version and build metadata

The app version comes from `package.json` and Electron's `app.getVersion()`. Before `pack:win`, `dist:win`, or `verify:win`, `scripts/write-build-info.cjs` writes `src/build-info.generated.json` with:

- `version`: the package version.
- `channel`: `MANA_CHESS_DESKTOP_CHANNEL` or `desktop`.
- `commit`: the current git commit, or `MANA_CHESS_BUILD_COMMIT`.
- `dirty`: whether the checkout had local changes, or `MANA_CHESS_BUILD_DIRTY`.
- `builtAt`: empty by default for reproducible output, or `MANA_CHESS_BUILD_TIME` / `SOURCE_DATE_EPOCH`.

The generated file is ignored by git but packaged into release builds. At runtime, this data is available through `window.ManaChessDesktop.getInfo().build` and in QA diagnostics. Release artifact hashes are written separately to ignored `dist/release-manifest.json` by `npm run verify:win:installer`.

## Notes

- This version requires internet.
- Practice, tutorial, bot, online rooms, admin settings, and local browser stats keep using the deployed web game.
- Later we can add Steamworks, achievements, cloud saves, rich presence, splash art, and an offline mode if needed.
