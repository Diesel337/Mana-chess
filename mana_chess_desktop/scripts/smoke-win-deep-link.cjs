const fs = require("node:fs")
const path = require("node:path")
const {execFileSync, spawn} = require("node:child_process")
const {desktopLogPath, smokeUserDataDir} = require("./smoke-user-data.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const userDataDir = smokeUserDataDir("deep-link")
const deepLink = readArg("--deep-link") || process.env.MANA_CHESS_SMOKE_DEEP_LINK || "manachess://game/private_smoke_deep_link"
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "12000")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop-deep-link-smoke"
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

function isFreshDeepLinkLog(entry, startTime) {
  if (!entry || entry.name !== "desktop.deep_link_opened") return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForDeepLinkLog(startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshDeepLinkLog(entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for desktop.deep_link_opened in ${logPath}`)
}

function expectedPathFromDeepLink(url) {
  const parsed = safeUrl(url)
  if (!parsed || parsed.protocol !== "manachess:") return "/"

  const parts = [
    parsed.hostname,
    ...parsed.pathname.split("/").filter(Boolean)
  ].filter(Boolean)

  if (parts[0] === "game" && parts[1]) return `/game/${encodeURIComponent(parts[1])}`
  if (parts[0]?.startsWith("game_") || parts[0]?.startsWith("private_")) return `/game/${encodeURIComponent(parts[0])}`
  return "/"
}

function safeUrl(url) {
  try {
    return new URL(url)
  } catch (_error) {
    return null
  }
}

function validateDeepLinkPayload(entry) {
  const payload = entry?.payload || {}
  const target = safeUrl(payload.target)
  const expectedPath = expectedPathFromDeepLink(deepLink)

  if (payload.source !== deepLink) {
    throw new Error(`Expected deep link source ${deepLink}, received ${payload.source || "empty"}.`)
  }

  if (!target) {
    throw new Error(`Expected deep link target URL, received ${payload.target || "empty"}.`)
  }

  if (target.pathname !== expectedPath) {
    throw new Error(`Expected deep link target path ${expectedPath}, received ${target.pathname}.`)
  }

  if (payload.phase !== "startup") {
    throw new Error(`Expected startup deep link phase, received ${payload.phase || "empty"}.`)
  }
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

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win:deep-link only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const startTime = Date.now()
  child = spawn(exePath, ["--windowed", deepLink], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_USER_DATA_DIR: userDataDir,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: process.env.MANA_CHESS_OFFLINE_RETRY_SECONDS || "0"
    }
  })

  child.unref()

  try {
    const entry = await waitForDeepLinkLog(startTime)
    validateDeepLinkPayload(entry)
    console.log(`Deep link smoke opened ${deepLink}`)
    console.log(`Target: ${entry.payload.target}`)
  } finally {
    stopLaunchedProcess()
    await wait(750)
  }
}

main().catch(error => {
  stopLaunchedProcess()
  console.error(error.message || error)
  process.exit(1)
})
