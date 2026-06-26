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

Create an unpacked Windows app for quick testing:

```powershell
npm run pack:win
```

## Desktop v2 notes

- The app keeps one Mana Chess window open and focuses it when launched again.
- Window size, position, maximized state, and fullscreen state are restored between sessions.
- Desktop mode is forced with `?desktop=1` on every in-app navigation.
- `manachess://` deep links can open lobby or game routes inside the desktop app.
- External links open in the user's browser; Mana Chess links stay in the app window.
- The Windows build uses `build/icon.ico` and app id `com.diesel337.manachess`.
- The web game can read `window.ManaChessDesktop.getInfo()` for desktop version, channel, platform, and origin.
- The window title follows local presence, such as lobby, active match, playing, or result states.
- The desktop menu can copy, open, or reset local desktop QA state.
- The desktop menu can copy the current `manachess://` deep link and open the current clean web link in the browser.

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
window.ManaChessDesktop.copyState()
window.ManaChessDesktop.openStateFolder()
window.ManaChessDesktop.resetState()
window.ManaChessDesktop.copyShareLink(window.location.href)
window.ManaChessDesktop.copyDeepLink(window.location.href)
window.ManaChessDesktop.sendEvent("match.finished", {result: "win"})
```

`sendEvent` is intentionally a no-op sink for now. It gives us a stable place to attach Steamworks achievements, rich presence, and cloud-save hooks later.

Emitted event names currently include `screen.viewed`, `match.opened`, `match.status_changed`, `match.started`, and `match.finished`.

Desktop state is stored locally in Electron user data as `desktop-state.json`. It tracks session counters, a small event log, current presence, and local achievement flags that can later map to Steamworks achievements. Use the Desktop menu to copy the state, open the data folder, or reset the local state during QA.

## Notes

- This version requires internet.
- Practice, tutorial, bot, online rooms, admin settings, and local browser stats keep using the deployed web game.
- Later we can add Steamworks, achievements, cloud saves, rich presence, splash art, and an offline mode if needed.
