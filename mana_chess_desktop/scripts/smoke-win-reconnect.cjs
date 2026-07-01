const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")
const http = require("node:http")
const {execFileSync, spawn} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "22000")
const retrySeconds = normalizeRetrySeconds(readArg("--retry-seconds") || process.env.MANA_CHESS_SMOKE_RETRY_SECONDS || "1")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop-reconnect-smoke"
const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming")
const logPath = path.join(appData, "Mana Chess", "desktop-log.jsonl")

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
  if (!Number.isFinite(timeout) || timeout < 5000) return 22000
  return Math.round(timeout)
}

function normalizeRetrySeconds(value) {
  const seconds = Number(value)
  if (!Number.isFinite(seconds) || seconds < 1) return 1
  return Math.round(seconds)
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

function isFreshEvent(name, entry, startTime) {
  if (!entry || entry.name !== name) return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForLog(name, startTime) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshEvent(name, entry, startTime))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for ${name} in ${logPath}`)
}

function smokePage() {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mana Chess Reconnect Smoke</title>
  </head>
  <body>
    <script>
      window.addEventListener("DOMContentLoaded", () => {
        window.ManaChessDesktop?.sendEvent?.("desktop.reconnect_smoke_loaded", {
          desktop: window.ManaChessDesktop?.getInfo?.()?.isDesktop === true
        });
      });
    </script>
  </body>
</html>`
}

function reservePort() {
  return new Promise((resolve, reject) => {
    const probe = http.createServer()
    probe.once("error", reject)
    probe.listen(0, "127.0.0.1", () => {
      const {port} = probe.address()
      probe.close(() => resolve(port))
    })
  })
}

function startServer(port) {
  return new Promise((resolve, reject) => {
    server = http.createServer((_request, response) => {
      response.writeHead(200, {"content-type": "text/html; charset=utf-8"})
      response.end(smokePage())
    })

    server.once("error", reject)
    server.listen(port, "127.0.0.1", () => resolve())
  })
}

function validateOffline(entry, smokeUrl) {
  const payload = entry?.payload || {}

  if (payload.retrySeconds !== retrySeconds) {
    throw new Error(`Expected retrySeconds=${retrySeconds}, received ${payload.retrySeconds}.`)
  }

  if (payload.url !== smokeUrl) {
    throw new Error(`Expected offline URL ${smokeUrl}, received ${payload.url || "empty"}.`)
  }
}

function validateReconnected(entry, smokeUrl) {
  const payload = entry?.payload || {}

  if (payload.url !== smokeUrl) {
    throw new Error(`Expected reconnected URL ${smokeUrl}, received ${payload.url || "empty"}.`)
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
    // The app may have exited on its own.
  }
}

function stopServer() {
  return new Promise(resolve => {
    if (!server) return resolve()
    server.close(() => resolve())
    server = null
  })
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win:reconnect only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const port = await reservePort()
  const smokeUrl = `http://127.0.0.1:${port}/`
  const startTime = Date.now()

  child = spawn(exePath, ["--windowed"], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env: {
      ...process.env,
      MANA_CHESS_URL: smokeUrl,
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: String(retrySeconds)
    }
  })

  child.unref()

  try {
    const offline = await waitForLog("desktop.offline", startTime)
    validateOffline(offline, smokeUrl)

    await startServer(port)

    const reconnected = await waitForLog("desktop.reconnected", startTime)
    validateReconnected(reconnected, smokeUrl)

    console.log(`Reconnect smoke recovered ${smokeUrl}`)
    console.log(`Offline: retrySeconds=${offline.payload.retrySeconds} error=${offline.payload.errorDescription || "load failed"}`)
    console.log(`Reconnected: ${reconnected.payload.url}`)
  } finally {
    stopLaunchedProcess()
    await stopServer()
    child = null
    await wait(750)
  }
}

main().catch(async error => {
  stopLaunchedProcess()
  await stopServer()
  console.error(error.message || error)
  process.exit(1)
})
