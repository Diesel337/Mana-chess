# Mana Chess Desktop

Desktop wrapper for Mana Chess.

## What this is

This is the first Steam-oriented desktop build path. It opens the current online game inside a desktop window with desktop layout enabled.

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

## Notes

- This first version requires internet.
- Desktop mode is forced with `?desktop=1`.
- Shortcuts:
  - `Ctrl+L`: back to lobby.
  - `Ctrl+R`: reload.
  - `F11`: fullscreen.
- Practice, tutorial, bot, online rooms, admin settings, and local browser stats keep using the deployed web game.
- External links open in the user's browser; Mana Chess links stay in the app window.
- The Windows build uses `build/icon.ico` and the `manachess://` protocol reservation for future Steam/deep-link work.
- Later we can add Steamworks, achievements, cloud saves, rich presence, splash art, and an offline mode if needed.
