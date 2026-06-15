# Mana Chess Desktop

Desktop wrapper for the online Mana Chess prototype.

## What this is

This is the first Steam-oriented desktop build path. It opens the current online game inside a desktop window.

Current game URL:

```text
https://control-piezas-production-59aa.up.railway.app/
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

Create a Windows installer:

```powershell
npm run dist:win
```

## Notes

- This first version requires internet.
- Practice, tutorial, bot, online rooms, admin settings, and local browser stats keep using the deployed web game.
- Later we can add app icon, splash art, Steam assets, Steamworks, and an offline mode if needed.
