const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")
const http = require("node:http")
const {execFileSync, spawn} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "15000")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop-bridge-smoke"
const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming")
const logPath = path.join(appData, "Mana Chess", "desktop-log.jsonl")
const qaBypassKey = "bridge-qa-smoke"
const fakeSteamId = "111111"
const fakeSteamKeys = ["SteamAppId", "SteamGameId", "SteamOverlayGameId", "SteamClientLaunch", "SteamEnv"]

let child = null
let server = null

function readArg(name) {
  const withEquals = process.argv.find(arg => typeof arg === "string" && arg.startsWith(`${name}=`))
  if (withEquals) return withEquals.slice(name.length + 1)

  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : ""
}

function normalizeTimeout(value) {
  const timeout = Number(value)
  if (!Number.isFinite(timeout) || timeout < 3000) return 15000
  return Math.round(timeout)
}

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function readLogEntries() {
  try {
    return fs.readFileSync(logPath, "utf8")
      .trim()
      .split(/\r?\n/)
      .filter(Boolean)
      .map(line => {
        try {
          return JSON.parse(line)
        } catch (_error) {
          return null
        }
      })
      .filter(Boolean)
  } catch (_error) {
    return []
  }
}

function isFreshBridgeEvent(entry, startTime) {
  if (!entry || entry.name !== "desktop.bridge_smoke") return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForBridgeLog(startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshBridgeEvent(entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.bridge_smoke in ${logPath}`)
}

function bridgeSmokePage() {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mana Chess Desktop Bridge Smoke</title>
  </head>
  <body>
    <script>
      window.addEventListener("DOMContentLoaded", async () => {
        const bridge = window.ManaChessDesktop;
        const info = bridge?.getInfo?.() || {};
        let stateOk = false;
        let diagnosticsOk = false;
        let copyStateOk = false;
        let copyDiagnosticsOk = false;
        let copyShareLinkOk = false;
        let copyShareLinkUrl = "";
        let copyDeepLinkOk = false;
        let copyDeepLinkUrl = "";
        let resetStateOk = false;
        let resetSessionOk = false;
        let infoSnapshotOk = false;
        let largePayloadCappedOk = false;
        const steam = info.steam || {};
        const steamInfoOk = Boolean(
          steam.detected === true &&
          steam.appId === ${JSON.stringify(fakeSteamId)} &&
          steam.gameId === ${JSON.stringify(fakeSteamId)} &&
          steam.overlayGameId === ${JSON.stringify(fakeSteamId)} &&
          steam.clientLaunch === true &&
          steam.steamEnv === true &&
          ${JSON.stringify(fakeSteamKeys)}.every((key) => Array.isArray(steam.presentKeys) && steam.presentKeys.includes(key))
        );
        const qaKeyApplied = new URLSearchParams(window.location.search).get("qa_key") === ${JSON.stringify(qaBypassKey)};
        const shareTarget = new URL("/game/private_bridge_smoke?desktop=1&qa_key=${qaBypassKey}", window.location.origin).toString();

        try {
          if (Array.isArray(info.steam?.presentKeys)) info.steam.presentKeys.push("mutated-by-smoke");
          if (info.steam) info.steam.detected = false;
          if (info.build) info.build.commit = "mutated-by-smoke";

          const nextInfo = bridge?.getInfo?.() || {};
          infoSnapshotOk = Boolean(
            nextInfo.steam?.detected === true &&
            !nextInfo.steam?.presentKeys?.includes?.("mutated-by-smoke") &&
            nextInfo.build?.commit !== "mutated-by-smoke"
          );
        } catch (_error) {}

        try {
          const state = await bridge?.getState?.();
          stateOk = Boolean(state && typeof state === "object");
        } catch (_error) {}

        try {
          const diagnostics = await bridge?.getDiagnostics?.();
          diagnosticsOk = Boolean(diagnostics?.window);
        } catch (_error) {}

        try {
          const result = await bridge?.copyState?.();
          copyStateOk = result?.ok === true && Boolean(result?.state);
        } catch (_error) {}

        try {
          const result = await bridge?.copyDiagnostics?.();
          copyDiagnosticsOk = result?.ok === true && Boolean(result?.diagnostics?.window);
        } catch (_error) {}

        try {
          const result = await bridge?.copyShareLink?.(shareTarget);
          copyShareLinkOk = result?.ok === true;
          copyShareLinkUrl = result?.url || "";
        } catch (_error) {}

        try {
          const result = await bridge?.copyDeepLink?.(shareTarget);
          copyDeepLinkOk = result?.ok === true;
          copyDeepLinkUrl = result?.url || "";
        } catch (_error) {}

        try {
          const state = await bridge?.resetState?.();
          resetStateOk = state?.version === 1 && Boolean(state?.presence);
          resetSessionOk = Boolean(
            state?.counters?.sessions >= 1 &&
            state?.lastEvents?.some?.((event) => event?.name === "desktop.session_started" && event?.payload?.reset === true)
          );
        } catch (_error) {}

        try {
          bridge?.sendEvent?.("desktop.bridge_large_payload", {text: "x".repeat(9000)});
          await new Promise((resolve) => setTimeout(resolve, 500));

          const state = await bridge?.getState?.();
          largePayloadCappedOk = Boolean(
            state?.lastEvents?.some?.((event) =>
              event?.name === "desktop.bridge_large_payload" &&
              event?.payload?.truncated === true &&
              event?.payload?.originalBytes > event?.payload?.maxBytes &&
              event?.payload?.maxBytes === 4096 &&
              event?.payload?.text === undefined
            )
          );
        } catch (_error) {}

        bridge?.sendEvent?.("desktop.bridge_smoke", {
          bridge: Boolean(bridge),
          isDesktop: info.isDesktop === true,
          channel: info.channel || "",
          version: info.version || "",
          steamInfoOk,
          infoSnapshotOk,
          stateOk,
          diagnosticsOk,
          copyStateOk,
          copyDiagnosticsOk,
          copyShareLinkOk,
          copyShareLinkUrl,
          copyDeepLinkOk,
          copyDeepLinkUrl,
          resetStateOk,
          resetSessionOk,
          largePayloadCappedOk,
          qaKeyApplied,
          datasetDesktop: document.documentElement.dataset.desktop === "true"
        });
      });
    </script>
  </body>
</html>`
}

function startBridgeServer() {
  return new Promise((resolve, reject) => {
    server = http.createServer((_request, response) => {
      response.writeHead(200, {"content-type": "text/html; charset=utf-8"})
      response.end(bridgeSmokePage())
    })

    server.once("error", reject)
    server.listen(0, "127.0.0.1", () => {
      const address = server.address()
      resolve(`http://127.0.0.1:${address.port}/`)
    })
  })
}

function validateBridgePayload(entry) {
  const payload = entry?.payload || {}

  if (payload.bridge !== true) throw new Error("Expected ManaChessDesktop bridge to exist.")
  if (payload.isDesktop !== true) throw new Error("Expected bridge info isDesktop=true.")
  if (payload.channel !== channel) throw new Error(`Expected channel ${channel}, received ${payload.channel || "empty"}.`)
  if (payload.steamInfoOk !== true) throw new Error("Expected bridge getInfo().steam to expose simulated Steam launch context.")
  if (payload.infoSnapshotOk !== true) throw new Error("Expected bridge getInfo() to return an immutable snapshot per call.")
  if (payload.stateOk !== true) throw new Error("Expected bridge getState() to return desktop state.")
  if (payload.diagnosticsOk !== true) throw new Error("Expected bridge getDiagnostics() to return window diagnostics.")
  if (payload.copyStateOk !== true) throw new Error("Expected bridge copyState() to return desktop state.")
  if (payload.copyDiagnosticsOk !== true) throw new Error("Expected bridge copyDiagnostics() to return diagnostics.")
  if (payload.copyShareLinkOk !== true) throw new Error("Expected bridge copyShareLink() to succeed.")
  if (!String(payload.copyShareLinkUrl || "").endsWith("/game/private_bridge_smoke")) {
    throw new Error(`Expected share link without desktop or qa_key query, received ${payload.copyShareLinkUrl || "empty"}.`)
  }
  if (String(payload.copyShareLinkUrl || "").includes("qa_key")) {
    throw new Error(`Expected share link to strip qa_key, received ${payload.copyShareLinkUrl || "empty"}.`)
  }
  if (payload.copyDeepLinkOk !== true) throw new Error("Expected bridge copyDeepLink() to succeed.")
  if (payload.copyDeepLinkUrl !== "manachess://game/private_bridge_smoke") {
    throw new Error(`Expected private game deep link, received ${payload.copyDeepLinkUrl || "empty"}.`)
  }
  if (payload.resetStateOk !== true) throw new Error("Expected bridge resetState() to return normalized desktop state.")
  if (payload.resetSessionOk !== true) throw new Error("Expected bridge resetState() to record a reset session event.")
  if (payload.largePayloadCappedOk !== true) throw new Error("Expected bridge sendEvent() to cap oversized payloads.")
  if (payload.qaKeyApplied !== true) throw new Error("Expected desktop URL to include QA bypass key for protected launch smoke.")
  if (payload.datasetDesktop !== true) throw new Error("Expected preload to mark documentElement dataset.desktop=true.")
}

function stopLaunchedProcess() {
  if (!child?.pid) return

  try {
    if (process.platform === "win32") {
      execFileSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], {stdio: "ignore"})
    } else {
      child.kill("SIGTERM")
    }
  } catch (_error) {
    // The app may have exited on its own.
  }
}

function stopBridgeServer() {
  return new Promise(resolve => {
    if (!server) return resolve()
    server.close(() => resolve())
    server = null
  })
}

function fakeSteamEnv() {
  return {
    SteamAppId: fakeSteamId,
    SteamGameId: fakeSteamId,
    SteamOverlayGameId: fakeSteamId,
    SteamClientLaunch: "1",
    SteamEnv: "1"
  }
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win:bridge only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const smokeUrl = await startBridgeServer()
  const startTime = Date.now()

  child = spawn(exePath, ["--windowed"], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_URL: smokeUrl,
      MANA_CHESS_QA_BYPASS_KEY: qaBypassKey,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: "0",
      ...fakeSteamEnv()
    }
  })

  child.unref()

  try {
    const entry = await waitForBridgeLog(startTime)
    validateBridgePayload(entry)
    console.log(`Bridge smoke loaded ${smokeUrl}`)
    console.log(`Bridge: isDesktop=${entry.payload.isDesktop} channel=${entry.payload.channel} stateOk=${entry.payload.stateOk}`)
    console.log(`Bridge copy: share=${entry.payload.copyShareLinkUrl} deep=${entry.payload.copyDeepLinkUrl}`)
  } finally {
    stopLaunchedProcess()
    await stopBridgeServer()
    child = null
    await wait(750)
  }
}

main().catch(async error => {
  stopLaunchedProcess()
  await stopBridgeServer()
  console.error(error.message || error)
  process.exit(1)
})
