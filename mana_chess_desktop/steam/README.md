# Mana Chess SteamPipe

This folder holds the generated local SteamPipe VDF files and their non-secret examples.
The Windows depot payload is:

```text
../dist/win-unpacked
```

The Steam launch executable is:

```text
Mana Chess.exe
```

## Prerequisites

1. Install the latest Steamworks SDK after Mana Chess has an app in Steamworks.
2. Run `tools\ContentBuilder\builder\steamcmd.exe` once so SteamCMD can bootstrap.
3. Point the release shell at the SDK and provide the real IDs:

```powershell
$env:STEAMWORKS_SDK_PATH="C:\steamworks_sdk"
$env:MANA_CHESS_STEAM_APP_ID="<app-id>"
$env:MANA_CHESS_STEAM_DEPOT_ID="<windows-depot-id>"
$env:MANA_CHESS_STEAM_USERNAME="<build-account>"
```

`STEAMCMD_PATH` can point directly to `steamcmd.exe` when the SDK lives elsewhere.
Real IDs, credentials, generated VDF files, SteamCMD logs, and build output stay outside git.
The scripts never accept or pass a Steam password; SteamCMD must already hold the build
account's SteamGuard authorization.

## Build and preview

Run the complete Windows release gate first:

```powershell
npm run release:win:preflight
```

It builds and verifies the Windows candidate, runs the installer and app smokes, then
inventories the exact Steam depot payload. The depot requires `Mana Chess.exe`,
`resources/app.asar`, `steam_api64.dll`, and the Steamworks N-API binding under
`resources/app.asar.unpacked`; it rejects symlinks and QA state, and excludes PDB/log files,
`resources/app-update.yml`, and `resources/elevate.exe`. Steam owns updates for this
payload, and the NSIS elevation helper is not needed by the unpacked Steam build.

Generate local preview VDF files and `dist/steam-depot-manifest.json`:

```powershell
npm run steam:prepare:preview
```

The manifest records every included file, size, SHA256, aggregate payload hash,
embedded Windows identity, and Authenticode status. Preview generation is the default
and writes `"Preview" "1"` to the app VDF.

Run SteamCMD's no-upload preview:

```powershell
npm run steam:preview
```

## Upload

Generate an upload-capable VDF only when the candidate is ready:

```powershell
npm run steam:prepare:upload
```

For a non-default private branch, `SetLive` can be explicit:

```powershell
npm run steam:prepare:upload -- --set-live=internal
```

The scripts reject `SetLive` in preview mode and always reject `default`. The default
branch must be assigned manually in Steamworks. For the first internal build, leaving
`SetLive` empty and assigning the uploaded build to a private branch in Steamworks is
the safest flow.

An upload requires an AppID-bound confirmation in the same shell:

```powershell
$env:MANA_CHESS_STEAM_UPLOAD_CONFIRM="UPLOAD_$env:MANA_CHESS_STEAM_APP_ID"
npm run steam:upload
```

`steam:upload` refuses preview VDFs, mismatched app/depot files, missing exclusions,
placeholders, missing confirmation, or an unavailable SteamCMD executable.

## Launch mode notes

The default Steam launch option should point to `Mana Chess.exe` without extra arguments.
Steam supplies the AppID environment used by the main-process Steamworks identity/session
flow; no publisher key or ticket belongs in a launch option.
For QA-only launch options, the packaged app also accepts:

```text
--windowed
--maximized
--fullscreen
```

Keep the public Steam branch on the default launch option unless a QA branch is
intentionally testing one of those modes.
