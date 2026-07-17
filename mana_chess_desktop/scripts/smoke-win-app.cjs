const fs = require("node:fs")
const path = require("node:path")
const http = require("node:http")
const {execFileSync, spawn} = require("node:child_process")
const {desktopLogPath, smokeLaunchEnv, smokeUserDataDir} = require("./smoke-user-data.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const configuredExePath = readArg("--exe") || process.env.MANA_CHESS_SMOKE_EXE
const exePath = configuredExePath
  ? path.resolve(desktopRoot, configuredExePath)
  : path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const userDataDir = smokeUserDataDir("app")
const smokeModes = ["windowed", "maximized", "fullscreen"]
const allowedModes = new Set(smokeModes)
const allowedModeSources = new Set(["flag", "env", "window-mode-arg", "saved"])
const modes = readFlag("--all-modes")
  ? smokeModes
  : [normalizeMode(readArg("--mode") || process.env.MANA_CHESS_SMOKE_MODE || "windowed")]
const modeSource = normalizeModeSource(readArg("--mode-source") || process.env.MANA_CHESS_SMOKE_MODE_SOURCE || "flag")
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "12000")
const simulateSteamEnv = readFlag("--steam-env")
const registerProtocol = readFlag("--register-protocol")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || (simulateSteamEnv ? "desktop-steam-smoke" : "desktop-smoke")
const logPath = desktopLogPath(userDataDir)
const windowStatePath = path.join(userDataDir, "window-state.json")
const savedWindowBounds = {width: 1000, height: 700}
const savedBoundsTolerance = 48
const fakeSteamId = "111111"
const fakeSteamKeys = [
  "SteamAppId",
  "SteamGameId",
  "SteamOverlayGameId",
  "SteamClientLaunch",
  "SteamEnv",
  "SteamPath",
  "SteamDeck",
  "SteamTenfoot"
]

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

function normalizeModeSource(value) {
  const normalized = String(value || "").trim().toLowerCase()
  if (allowedModeSources.has(normalized)) return normalized
  throw new Error(`Unsupported smoke mode source "${value}". Use flag, env, window-mode-arg, or saved.`)
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
  if (entry.payload?.source !== modeSource) return false

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
      const expectedSource = new URLSearchParams(window.location.search).get("source") || "";

      const expectedWidth = Number(new URLSearchParams(window.location.search).get("width") || 0);
      const expectedHeight = Number(new URLSearchParams(window.location.search).get("height") || 0);
      const boundsTolerance = Number(new URLSearchParams(window.location.search).get("tolerance") || 0);

      function boundsMatchWindow(mode, windowInfo) {
        if (mode !== "windowed" || expectedWidth <= 0 || expectedHeight <= 0) return true;
        const bounds = windowInfo?.bounds || {};
        return Math.abs(Number(bounds.width) - expectedWidth) <= boundsTolerance &&
          Math.abs(Number(bounds.height) - expectedHeight) <= boundsTolerance;
      }

      function modeMatchesWindow(mode, windowInfo) {
        if (!windowInfo?.exists) return false;
        let stateMatches = false;
        if (mode === "fullscreen") stateMatches = windowInfo.isFullScreen === true;
        if (mode === "maximized") stateMatches = windowInfo.isMaximized === true && windowInfo.isFullScreen !== true;
        if (mode === "windowed") stateMatches = windowInfo.isMaximized !== true && windowInfo.isFullScreen !== true;
        return stateMatches && boundsMatchWindow(mode, windowInfo);
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
          source: expectedSource,
          bridge: Boolean(bridge),
          datasetDesktop: document.documentElement.dataset.desktop === "true",
          modeOk: modeMatchesWindow(expectedMode, windowInfo),
          boundsOk: boundsMatchWindow(expectedMode, windowInfo),
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
    SteamEnv: "1",
    SteamPath: "C:\\Program Files (x86)\\Steam",
    SteamDeck: "1",
    SteamTenfoot: "1"
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

  for (const field of ["steamPath", "steamDeck", "steamTenfoot"]) {
    if (steam[field] !== true) {
      throw new Error(`Expected desktop.session_started payload.steam.${field} to be true.`)
    }
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
  const expectedMode = modeSource === "saved" ? "saved" : mode
  if (launchMode !== expectedMode) {
    throw new Error(`Expected desktop.session_started payload.launchMode ${expectedMode}, received ${launchMode || "empty"}.`)
  }
}

function validateModeSmokePayload(entry, mode) {
  const payload = entry?.payload || {}
  const windowInfo = payload.window || {}

  if (payload.source !== modeSource) throw new Error(`Expected mode smoke source ${modeSource}, received ${payload.source || "empty"}.`)
  if (payload.bridge !== true) throw new Error("Expected ManaChessDesktop bridge to exist during mode smoke.")
  if (payload.datasetDesktop !== true) throw new Error("Expected preload to mark documentElement dataset.desktop=true.")
  if (payload.modeOk !== true) {
    throw new Error(`Expected ${mode} window diagnostics, received maximized=${windowInfo.isMaximized} fullscreen=${windowInfo.isFullScreen}.`)
  }
  if (modeSource === "saved" && payload.boundsOk !== true) {
    throw new Error(`Expected saved window bounds ${savedWindowBounds.width}x${savedWindowBounds.height}.`)
  }
}

function launchArgsForMode(mode) {
  if (modeSource === "env" || modeSource === "saved") return []
  if (modeSource === "window-mode-arg") return [`--window-mode=${mode}`]
  return [`--${mode}`]
}

function launchEnvForMode(mode, smokeUrl) {
  return smokeLaunchEnv({
    MANA_CHESS_URL: smokeUrl,
    MANA_CHESS_USER_DATA_DIR: userDataDir,
    MANA_CHESS_DESKTOP_CHANNEL: channel,
    MANA_CHESS_OFFLINE_RETRY_SECONDS: process.env.MANA_CHESS_OFFLINE_RETRY_SECONDS || "0",
    MANA_CHESS_DISABLE_PROTOCOL_REGISTRATION: registerProtocol ? "0" : "1",
    ...(modeSource === "env" ? {MANA_CHESS_WINDOW_MODE: mode} : {}),
    ...(modeSource === "saved" ? {MANA_CHESS_WINDOW_MODE: ""} : {}),
    ...fakeSteamEnv()
  })
}

function seedSavedWindowState(mode) {
  if (modeSource !== "saved") return

  const state = {
    bounds: {...savedWindowBounds},
    isMaximized: mode === "maximized",
    isFullScreen: mode === "fullscreen"
  }

  fs.mkdirSync(userDataDir, {recursive: true})
  fs.writeFileSync(windowStatePath, `${JSON.stringify(state, null, 2)}\n`)
}

function validateSavedWindowState(mode) {
  if (modeSource !== "saved") return

  const state = JSON.parse(fs.readFileSync(windowStatePath, "utf8"))
  const expectedMaximized = mode === "maximized"
  const expectedFullScreen = mode === "fullscreen"
  const widthMatches = Math.abs(Number(state?.bounds?.width) - savedWindowBounds.width) <= savedBoundsTolerance
  const heightMatches = Math.abs(Number(state?.bounds?.height) - savedWindowBounds.height) <= savedBoundsTolerance

  if (state?.isMaximized !== expectedMaximized || state?.isFullScreen !== expectedFullScreen) {
    throw new Error(`Saved ${mode} state changed before relaunch verification.`)
  }
  if (!widthMatches || !heightMatches) {
    throw new Error(`Saved bounds changed from ${savedWindowBounds.width}x${savedWindowBounds.height}.`)
  }
}

async function smokeMode(mode, serverUrl) {
  seedSavedWindowState(mode)
  const startTime = Date.now()
  const smokeUrl = new URL(serverUrl)
  smokeUrl.searchParams.set("mode", mode)
  smokeUrl.searchParams.set("source", modeSource)
  if (modeSource === "saved") {
    smokeUrl.searchParams.set("width", String(savedWindowBounds.width))
    smokeUrl.searchParams.set("height", String(savedWindowBounds.height))
    smokeUrl.searchParams.set("tolerance", String(savedBoundsTolerance))
  }
  child = spawn(exePath, launchArgsForMode(mode), {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: launchEnvForMode(mode, smokeUrl.toString())
  })

  child.unref()

  try {
    const entry = await waitForSessionLog(startTime)
    validateSteamPayload(entry)
    validateLaunchModePayload(entry, mode)
    const modeEntry = await waitForModeSmokeLog(startTime, mode)
    validateModeSmokePayload(modeEntry, mode)
    await wait(400)
    validateSavedWindowState(mode)
    console.log(`Smoke launched ${path.relative(desktopRoot, exePath)} in ${mode} mode via ${modeSource}.`)
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

  console.log(`Smoke completed for ${modes.join(", ")} via ${modeSource}.`)
}

main().catch(async error => {
  stopLaunchedProcess()
  await stopModeServer()
  console.error(error.message || error)
  process.exit(1)
})
