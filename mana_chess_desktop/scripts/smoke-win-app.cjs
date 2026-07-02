const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")
const http = require("node:http")
const {execFileSync, spawn} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const smokeModes = ["windowed", "maximized", "fullscreen"]
const allowedModes = new Set(smokeModes)
const modes = readFlag("--all-modes")
  ? smokeModes
  : [normalizeMode(readArg("--mode") || process.env.MANA_CHESS_SMOKE_MODE || "windowed")]
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "12000")
const simulateSteamEnv = readFlag("--steam-env")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || (simulateSteamEnv ? "desktop-steam-smoke" : "desktop-smoke")
const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming")
const logPath = path.join(appData, "Mana Chess", "desktop-log.jsonl")
const fakeSteamId = "111111"
const fakeSteamKeys = ["SteamAppId", "SteamGameId", "SteamOverlayGameId", "SteamClientLaunch", "SteamEnv"]

let child = null
let server = null

function readFlag(name) {
  return process.argv.includes(name)
}

function readArg(name) {
  const withEquals = process.argv.find(arg => typeof arg === "string" && arg.startsWith(`${name}=`))
  if (withEquals) return withEquals.slice(name.length + 1)

  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : ""
}

function normalizeMode(value) {
  const normalized = String(value || "").trim().toLowerCase()
  if (allowedModes.has(normalized)) return normalized
  throw new Error(`Unsupported smoke mode "${value}". Use windowed, maximized, or fullscreen.`)
}

function normalizeTimeout(value) {
  const timeout = Number(value)
  if (!Number.isFinite(timeout) || timeout < 3000) return 12000
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

function isFreshSmokeSession(entry, startTime) {
  if (!entry || entry.name !== "desktop.session_started") return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

function isFreshModeSmoke(entry, startTime, mode) {
  if (!entry || entry.name !== "desktop.mode_smoke") return false
  if (entry.channel !== channel) return false
  if (entry.payload?.mode !== mode) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForSessionLog(startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshSmokeSession(entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.session_started in ${logPath}`)
}

async function waitForModeSmokeLog(startTime, mode) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshModeSmoke(entry, startTime, mode))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.mode_smoke ${mode} in ${logPath}`)
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
    // The app may have exited on its own after handing off to an existing instance.
  }
}

function modeSmokePage() {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mana Chess Desktop Mode Smoke</title>
  </head>
  <body>
    <script>
      const expectedMode = new URLSearchParams(window.location.search).get("mode") || "";

      function modeMatchesWindow(mode, windowInfo) {
        if (!windowInfo?.exists) return false;
        if (mode === "fullscreen") return windowInfo.isFullScreen === true;
        if (mode === "maximized") return windowInfo.isMaximized === true && windowInfo.isFullScreen !== true;
        if (mode === "windowed") return windowInfo.isMaximized !== true && windowInfo.isFullScreen !== true;
        return false;
      }

      async function modeDiagnostics(bridge) {
        let lastDiagnostics = {};

        for (let attempt = 0; attempt < 20; attempt += 1) {
          try {
            lastDiagnostics = await bridge?.getDiagnostics?.() || {};
            if (modeMatchesWindow(expectedMode, lastDiagnostics.window)) break;
          } catch (_error) {}

          await new Promise((resolve) => setTimeout(resolve, 250));
        }

        return lastDiagnostics;
      }

      window.addEventListener("DOMContentLoaded", async () => {
        const bridge = window.ManaChessDesktop;
        const diagnostics = await modeDiagnostics(bridge);
        const windowInfo = diagnostics.window || {};

        bridge?.sendEvent?.("desktop.mode_smoke", {
          mode: expectedMode,
          bridge: Boolean(bridge),
          datasetDesktop: document.documentElement.dataset.desktop === "true",
          modeOk: modeMatchesWindow(expectedMode, windowInfo),
          window: {
            exists: windowInfo.exists === true,
            isMaximized: windowInfo.isMaximized === true,
            isFullScreen: windowInfo.isFullScreen === true,
            isMinimized: windowInfo.isMinimized === true,
            bounds: windowInfo.bounds || {}
          }
        });
      });
    </script>
  </body>
</html>`
}

function startModeServer() {
  return new Promise((resolve, reject) => {
    server = http.createServer((_request, response) => {
      response.writeHead(200, {"content-type": "text/html; charset=utf-8"})
      response.end(modeSmokePage())
    })

    server.once("error", reject)
    server.listen(0, "127.0.0.1", () => {
      const address = server.address()
      resolve(`http://127.0.0.1:${address.port}/`)
    })
  })
}

function stopModeServer() {
  return new Promise(resolve => {
    if (!server) return resolve()
    server.close(() => resolve())
    server = null
  })
}

function fakeSteamEnv() {
  if (!simulateSteamEnv) return {}

  return {
    SteamAppId: fakeSteamId,
    SteamGameId: fakeSteamId,
    SteamOverlayGameId: fakeSteamId,
    SteamClientLaunch: "1",
    SteamEnv: "1"
  }
}

function validateSteamPayload(entry) {
  if (!simulateSteamEnv) return

  const steam = entry?.payload?.steam || {}
  if (steam.detected !== true) {
    throw new Error("Expected desktop.session_started payload.steam.detected to be true.")
  }

  for (const field of ["appId", "gameId", "overlayGameId"]) {
    if (steam[field] !== fakeSteamId) {
      throw new Error(`Expected simulated Steam ${field} ${fakeSteamId}, received ${steam[field] || "empty"}.`)
    }
  }

  if (steam.clientLaunch !== true) {
    throw new Error("Expected desktop.session_started payload.steam.clientLaunch to be true.")
  }

  if (steam.steamEnv !== true) {
    throw new Error("Expected desktop.session_started payload.steam.steamEnv to be true.")
  }

  const presentKeys = new Set(Array.isArray(steam.presentKeys) ? steam.presentKeys : [])
  for (const key of fakeSteamKeys) {
    if (!presentKeys.has(key)) {
      throw new Error(`Expected desktop.session_started payload.steam.presentKeys to include ${key}.`)
    }
  }
}

function validateLaunchModePayload(entry, mode) {
  const launchMode = entry?.payload?.launchMode || ""
  if (launchMode !== mode) {
    throw new Error(`Expected desktop.session_started payload.launchMode ${mode}, received ${launchMode || "empty"}.`)
  }
}

function validateModeSmokePayload(entry, mode) {
  const payload = entry?.payload || {}
  const windowInfo = payload.window || {}

  if (payload.bridge !== true) throw new Error("Expected ManaChessDesktop bridge to exist during mode smoke.")
  if (payload.datasetDesktop !== true) throw new Error("Expected preload to mark documentElement dataset.desktop=true.")
  if (payload.modeOk !== true) {
    throw new Error(`Expected ${mode} window diagnostics, received maximized=${windowInfo.isMaximized} fullscreen=${windowInfo.isFullScreen}.`)
  }
}

async function smokeMode(mode, serverUrl) {
  const startTime = Date.now()
  const smokeUrl = `${serverUrl}?mode=${encodeURIComponent(mode)}`
  child = spawn(exePath, [`--${mode}`], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_URL: smokeUrl,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: process.env.MANA_CHESS_OFFLINE_RETRY_SECONDS || "0",
      ...fakeSteamEnv()
    }
  })

  child.unref()

  try {
    const entry = await waitForSessionLog(startTime)
    validateSteamPayload(entry)
    validateLaunchModePayload(entry, mode)
    const modeEntry = await waitForModeSmokeLog(startTime, mode)
    validateModeSmokePayload(modeEntry, mode)
    console.log(`Smoke launched ${path.relative(desktopRoot, exePath)} in ${mode} mode.`)
    console.log(`Log: ${entry.name} ${entry.version || ""} ${entry.commit || ""} ${entry.channel}`)
    console.log(`Window: maximized=${modeEntry.payload.window.isMaximized} fullscreen=${modeEntry.payload.window.isFullScreen}`)
    if (simulateSteamEnv) console.log(`Steam env: appId ${entry.payload.steam.appId} detected=${entry.payload.steam.detected}`)
  } finally {
    stopLaunchedProcess()
    child = null
    await wait(750)
  }
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const serverUrl = await startModeServer()

  try {
    for (const mode of modes) {
      await smokeMode(mode, serverUrl)
    }
  } finally {
    await stopModeServer()
  }

  console.log(`Smoke completed for ${modes.join(", ")}.`)
}

main().catch(async error => {
  stopLaunchedProcess()
  await stopModeServer()
  console.error(error.message || error)
  process.exit(1)
})
