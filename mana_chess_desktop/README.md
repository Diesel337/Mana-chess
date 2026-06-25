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
- `Ctrl+R`: reload.
- `F11`: fullscreen.
- `Esc`: leave fullscreen.

## Desktop bridge

The preload exposes a small, future-safe API to the remote game:

```js
window.ManaChessDesktop.getInfo()
window.ManaChessDesktop.copyShareLink(window.location.href)
window.ManaChessDesktop.sendEvent("match.finished", {result: "win"})
```

`sendEvent` is intentionally a no-op sink for now. It gives us a stable place to attach Steamworks achievements, rich presence, and cloud-save hooks later.

Emitted event names currently include `screen.viewed`, `match.opened`, `match.status_changed`, `match.started`, and `match.finished`.

## Notes

- This version requires internet.
- Practice, tutorial, bot, online rooms, admin settings, and local browser stats keep using the deployed web game.
- Later we can add Steamworks, achievements, cloud saves, rich presence, splash art, and an offline mode if needed.
