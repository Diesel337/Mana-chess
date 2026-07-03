const fs = require("node:fs")
const path = require("node:path")
const {execFileSync, spawn} = require("node:child_process")
const {desktopLogPath, smokeUserDataDir} = require("./smoke-user-data.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const userDataDir = smokeUserDataDir("offline")
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "15000")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop-offline-smoke"
const offlineUrl = readArg("--url") || process.env.MANA_CHESS_SMOKE_OFFLINE_URL || "http://127.0.0.1:65535/"
const logPath = desktopLogPath(userDataDir)

let child = null

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

function isFreshOfflineEvent(entry, startTime) {
  if (!entry || entry.name !== "desktop.offline") return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForOfflineLog(startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshOfflineEvent(entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.offline in ${logPath}`)
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
    // The process may already be gone after an early load failure.
  }
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win:offline only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const startTime = Date.now()
  child = spawn(exePath, ["--windowed"], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_URL: offlineUrl,
      MANA_CHESS_USER_DATA_DIR: userDataDir,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: "0"
    }
  })

  child.unref()

  try {
    const entry = await waitForOfflineLog(startTime)
    const payload = entry.payload || {}
    console.log(`Offline smoke loaded ${offlineUrl}`)
    console.log(`Log: ${entry.name} ${entry.version || ""} ${entry.commit || ""} ${entry.channel}`)
    console.log(`Failure: ${payload.errorDescription || "load failed"} ${payload.errorCode || ""}`.trim())
  } finally {
    stopLaunchedProcess()
    child = null
    await wait(750)
  }
}

main().catch(error => {
  stopLaunchedProcess()
  console.error(error.message || error)
  process.exit(1)
})
