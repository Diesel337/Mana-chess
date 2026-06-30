const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")
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

let child = null

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

async function waitForSessionLog(startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshSmokeSession(entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.session_started in ${logPath}`)
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

function fakeSteamEnv() {
  if (!simulateSteamEnv) return {}

  return {
    SteamAppId: "111111",
    SteamGameId: "111111",
    SteamOverlayGameId: "111111",
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

  if (steam.appId !== "111111") {
    throw new Error(`Expected simulated SteamAppId 111111, received ${steam.appId || "empty"}.`)
  }
}

async function smokeMode(mode) {
  const startTime = Date.now()
  child = spawn(exePath, [`--${mode}`], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: process.env.MANA_CHESS_OFFLINE_RETRY_SECONDS || "0",
      ...fakeSteamEnv()
    }
  })

  child.unref()

  try {
    const entry = await waitForSessionLog(startTime)
    validateSteamPayload(entry)
    console.log(`Smoke launched ${path.relative(desktopRoot, exePath)} in ${mode} mode.`)
    console.log(`Log: ${entry.name} ${entry.version || ""} ${entry.commit || ""} ${entry.channel}`)
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

  for (const mode of modes) {
    await smokeMode(mode)
  }

  console.log(`Smoke completed for ${modes.join(", ")}.`)
}

main().catch(error => {
  stopLaunchedProcess()
  console.error(error.message || error)
  process.exit(1)
})
