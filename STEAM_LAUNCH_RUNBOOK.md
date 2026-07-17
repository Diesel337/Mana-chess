# Mana Chess Steam Launch Runbook

This runbook turns the release checklist into an executable path. It does not contain credentials, real Steam IDs, or signing material.

## Current hard blockers

The repository and local Windows pipeline are ready for an internal candidate. The remaining external inputs are:

1. Steamworks partner onboarding, Steam Direct payment, and a real Mana Chess AppID.
2. A distinct Windows depot ID and a restricted Steam build account.
3. The current Steamworks SDK, including SteamCMD.
4. A Steam Web API publisher key configured only in Railway.
5. A Windows Authenticode certificate and timestamping configuration.
6. A dedicated Railway staging environment, a clean Windows test machine, and two Steam test accounts.

Do not store any of these values in Git, Electron, generated VDF examples, screenshots, or QA logs.

## 1. Source freeze

Run from the repository root:

```powershell
git status --short
git pull --ff-only origin main
```

The release candidate must start from a clean `main`. Record the commit, intended version, release owner, backend owner, and rollback owner in the private release ticket.

## 2. Backend staging

Never run a large competitive queue benchmark against the public production lobby.

Create or refresh a dedicated Railway `staging` environment from `production`, then verify all of the following before deploying:

- The service root remains `mana_chess_online`.
- Staging has its own Postgres service and volume. It must not point at the production database URL.
- Staging has a separate domain and QA bypass key.
- `MANA_CHESS_MAX_DYNAMIC_GAMES` matches the test tier.
- Steam publisher credentials are used only when staging a real Steam authentication rehearsal.
- `/health` reports `ready: true` and the expected persistence mode.

Run both private and competitive WebSocket scenarios from `mana_chess_online`:

```powershell
pnpm --dir bench liveview -- --url https://<staging-domain> --allow-remote --mode private --matches 100 --ramp-per-second 20 --hold-seconds 15 --output bench/reports/staging-private-100.json
pnpm --dir bench liveview -- --url https://<staging-domain> --allow-remote --mode competitive --matches 100 --ramp-per-second 20 --hold-seconds 15 --output bench/reports/staging-competitive-100.json
```

Advance to 250 and 500 matches only after the previous tier passes. Competitive staging must be isolated from human players. Keep production at its current admission limit until staging CPU, memory, health, join latency, event latency, and cleanup are acceptable.

## 3. Windows candidate

From `mana_chess_desktop`:

```powershell
npm ci
npm run release:win:candidate
npm run steam:doctor
```

The candidate gate must confirm:

- The manifest commit matches the clean repository commit.
- The packaged Steam DLL and N-API binding exist.
- Installer install, launch, uninstall, shortcuts, protocol, and executable metadata pass.
- Windowed, maximized, fullscreen, deep-link, second-instance, bridge, reconnect, and offline smokes pass.
- `dist/release-manifest.json` contains the expected artifact hashes.

For a release build, configure signing outside Git and require it:

```powershell
$env:MANA_CHESS_REQUIRE_SIGNED="1"
npm run release:win:candidate
npm run steam:doctor:release
```

Both `Mana Chess.exe` and the installer must report valid Authenticode signatures.

## 4. Steam authentication rehearsal

Configure matching values in the Steam client build and Railway staging:

- `MANA_CHESS_STEAM_APP_ID`
- `MANA_CHESS_STEAM_WEB_API_PUBLISHER_KEY` on Railway only
- `MANA_CHESS_STEAM_TICKET_IDENTITY`
- `MANA_CHESS_LAUNCH_ACCESS=steam_required`
- A private `MANA_CHESS_QA_BYPASS_KEY` for non-Steam staging diagnostics

Use two licensed Steam test accounts. Verify ticket exchange, ownership, stable SteamID identity, reconnect, quick match, private link, spectator flow, and a completed rated result. Confirm raw tickets and the publisher key never appear in browser state, desktop diagnostics, Railway logs, or database records.

## 5. SteamPipe preview and upload

Set the real values only in the release shell:

```powershell
$env:STEAMWORKS_SDK_PATH="C:\steamworks_sdk"
$env:MANA_CHESS_STEAM_APP_ID="<app-id>"
$env:MANA_CHESS_STEAM_DEPOT_ID="<windows-depot-id>"
$env:MANA_CHESS_STEAM_USERNAME="<restricted-build-account>"
```

Then run:

```powershell
npm run steam:doctor:strict
npm run steam:prepare:preview
npm run steam:preview
```

Inspect the generated depot inventory and SteamCMD preview. For the real upload:

```powershell
npm run steam:prepare:upload
$env:MANA_CHESS_STEAM_UPLOAD_CONFIRM="UPLOAD_$env:MANA_CHESS_STEAM_APP_ID"
npm run steam:upload
```

Assign the uploaded build manually to a private internal branch. Never let automation set the default branch.

## 6. Internal acceptance

On a clean Windows machine launched from the Steam client, complete:

- Install, first launch, overlay, fullscreen/windowed, relaunch, and uninstall.
- Lobby, practice, tutorial, bot, quick match, private match, spectator, chat, sound, cosmetics, and reconnect.
- Two-account Steam identity and ownership checks.
- Service outage and recovery behavior.
- No horizontal overflow or UI overlap at supported desktop sizes.
- SmartScreen and publisher display with the signed candidate.

Record the exact Steam build ID, app commit, backend deployment ID, database migration level, and test account results.

## 7. Launch sequence

1. Freeze source and configuration changes.
2. Confirm Railway production health, Postgres readiness, backups, capacity, and alert ownership.
3. Deploy the already-tested backend commit and wait for Railway health checks.
4. Re-run the Steam authentication rehearsal against production with private test accounts.
5. Confirm `MANA_CHESS_LAUNCH_ACCESS=steam_required` before commercial release.
6. Promote the accepted Steam build from the internal branch according to Steamworks release controls.
7. Monitor health, deploy logs, database errors, game count, mailbox pressure, reconnects, and support reports.

Do not combine a new backend deploy, a new desktop build, and a store release at the same moment unless the incident team has explicitly accepted that risk.

## 8. Rollback

### Backend

1. Stop further deploys and record the failing deployment ID.
2. Redeploy the last known-good application commit in Railway.
3. Keep migrations additive. Do not destructively roll back Postgres during an active incident.
4. Verify `/health`, home, one fixed room, Steam bootstrap, and persistence writer state.
5. Remember that active matches are memory-only and can be lost during a deployment. Communicate before forcing a restart when possible.

### Steam build

1. Keep the previous accepted build available on a private rollback branch.
2. Move the affected public branch back to that build through Steamworks.
3. Verify launch, ownership, and backend protocol compatibility before announcing recovery.

### Access failure

Do not make the commercial game publicly accessible on the web as an automatic authentication rollback. Prefer the previous backend, the previous Steam build, or a controlled maintenance window. Any temporary access-policy exception requires explicit release-owner approval and immediate follow-up.

## 9. Incident checklist

For every launch incident, capture:

- Start time, reporter, severity, affected build/deployment, and player impact.
- `/health` response and Railway deployment/instance status.
- Whether the problem is desktop, Steam authentication, network, game process, or persistence related.
- Last known-good app commit, Steam build ID, and Railway deployment ID.
- Mitigation owner, rollback decision, player communication, and next update time.
- Resolution time, evidence of recovery, and a follow-up issue with prevention work.

Severity guidance:

- `SEV-1`: launch unavailable, authentication universally broken, data integrity risk, or widespread match failure.
- `SEV-2`: major feature unavailable or elevated failures with a workaround.
- `SEV-3`: limited defect, cosmetic issue, or isolated support case.

The release owner makes the go/no-go decision. The backend owner controls Railway and database actions. The build owner controls SteamPipe and branch promotion. One person may hold multiple roles, but every role must be named before launch.
