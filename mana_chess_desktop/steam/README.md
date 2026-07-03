# Mana Chess SteamPipe

This folder holds non-secret SteamPipe templates for the Windows desktop build.

The packaged payload is:

```text
../dist/win-unpacked
```

The Steam launch executable should be:

```text
Mana Chess.exe
```

## Local upload flow

Install SteamCMD outside this repository, then run the full Windows release preflight:

```powershell
npm run release:win:preflight
```

The preflight validates syntax, SteamPipe templates, icons, the unpacked Windows executable, the NSIS installer, launch window modes, simulated Steam environment data, deep links, second-instance handoff, desktop bridge IPC, reconnect, and offline recovery.

Steam uploads use the unpacked payload in `../dist/win-unpacked`. The NSIS installer and release manifest are QA/release evidence and are not the Steam depot payload.

Copy the templates to local, ignored VDF files:

```powershell
cd steam
copy app_build_steam_app.vdf.example app_build_steam_app.vdf
copy depot_build_windows.vdf.example depot_build_windows.vdf
```

Edit the copied files locally with the real Steamworks app ID and Windows depot ID.
Do not commit real app IDs, depot IDs, Steam credentials, SteamCMD logs, or generated build output.

Upload with SteamCMD from this folder:

```powershell
steamcmd +login <steam_username> +run_app_build .\app_build_steam_app.vdf +quit
```

## Launch mode notes

The default Steam launch option should point to `Mana Chess.exe` without extra arguments.
For QA-only launch options, the packaged app also accepts:

```text
--windowed
--maximized
--fullscreen
```

Keep the public Steam branch on the default launch option unless a QA branch is intentionally testing one of those modes.
