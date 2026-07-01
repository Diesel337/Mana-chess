const fs = require("node:fs")
const path = require("node:path")
const os = require("node:os")
const http = require("node:http")
const {execFileSync, spawn} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const deepLink = readArg("--deep-link") || process.env.MANA_CHESS_SMOKE_DEEP_LINK || "manachess://game/private_second_instance"
const timeoutMs = normalizeTimeout(readArg("--timeout-ms") || process.env.MANA_CHESS_SMOKE_TIMEOUT_MS || "15000")
const channel = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop-second-instance-smoke"
const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming")
const logPath = path.join(appData, "Mana Chess", "desktop-log.jsonl")

let firstChild = null
let secondChild = null
let server = null

function readArg(name) {
  const withEquals = process.argv.find(arg => typeof arg === "string" && arg.startsWith(`${name}=`))
  if (withEquals) return withEquals.slice(name.length + 1)

  const index = process.argv.indexOf(name)
  return index >= 0 ? process.argv[index + 1] : ""
}

function normalizeTimeout(value) {
  const timeout = Number(value)
  if (!Number.isFinite(timeout) || timeout < 5000) return 15000
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

function isFreshEvent(name, entry, startTime) {
  if (!entry || entry.name !== name) return false
  if (entry.channel !== channel) return false

  const at = Date.parse(entry.at || "")
  return Number.isFinite(at) && at >= startTime - 1000
}

async function waitForLog(name, startTime, predicate = () => true) {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const match = readLogEntries().reverse().find(entry => isFreshEvent(name, entry, startTime) && predicate(entry))
    if (match) return match
    await wait(500)
  }

  throw new Error(`Timed out waiting for ${name} in ${logPath}`)
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

function smokePage() {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Mana Chess Second Instance Smoke</title>
  </head>
  <body>
    <script>
      window.addEventListener("DOMContentLoaded", () => {
        window.ManaChessDesktop?.sendEvent?.("desktop.second_instance_ready", {
          desktop: window.ManaChessDesktop?.getInfo?.()?.isDesktop === true
        });
      });
    </script>
  </body>
</html>`
}

function startServer() {
  return new Promise((resolve, reject) => {
    server = http.createServer((_request, response) => {
      response.writeHead(200, {"content-type": "text/html; charset=utf-8"})
      response.end(smokePage())
    })

    server.once("error", reject)
    server.listen(0, "127.0.0.1", () => {
      const address = server.address()
      resolve(`http://127.0.0.1:${address.port}/`)
    })
  })
}

function validateDeepLinkPayload(entry) {
  const payload = entry?.payload || {}
  const target = safeUrl(payload.target)
  const expectedPath = expectedPathFromDeepLink(deepLink)

  if (payload.source !== deepLink) {
    throw new Error(`Expected second instance source ${deepLink}, received ${payload.source || "empty"}.`)
  }

  if (!target) {
    throw new Error(`Expected second instance target URL, received ${payload.target || "empty"}.`)
  }

  if (target.pathname !== expectedPath) {
    throw new Error(`Expected second instance target path ${expectedPath}, received ${target.pathname}.`)
  }

  if (payload.phase !== "runtime") {
    throw new Error(`Expected runtime deep link phase, received ${payload.phase || "empty"}.`)
  }
}

function stopProcess(child) {
  if (!child?.pid) return

  try {
    if (process.platform === "win32") {
      execFileSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], {stdio: "ignore"})
    } else {
      child.kill("SIGTERM")
    }
  } catch (_error) {
    // The process may have exited on its own after handing off to the first instance.
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
    throw new Error("smoke:win:second-instance only runs on Windows.")
  }

  if (!fs.existsSync(exePath)) {
    throw new Error(`Missing ${exePath}. Run npm run pack:win or npm run verify:win first.`)
  }

  const smokeUrl = await startServer()
  const startTime = Date.now()
  const env = {
    ...process.env,
    MANA_CHESS_URL: smokeUrl,
    MANA_CHESS_DESKTOP_CHANNEL: channel,
    MANA_CHESS_OFFLINE_RETRY_SECONDS: "0"
  }

  firstChild = spawn(exePath, ["--windowed"], {
    cwd: desktopRoot,
    detached: false,
    stdio: "ignore",
    env
  })
  firstChild.unref()

  try {
    await waitForLog("desktop.session_started", startTime)
    await waitForLog("desktop.second_instance_ready", startTime)

    secondChild = spawn(exePath, [deepLink], {
      cwd: desktopRoot,
      detached: false,
      stdio: "ignore",
      env
    })
    secondChild.unref()

    const entry = await waitForLog(
      "desktop.deep_link_opened",
      startTime,
      logEntry => logEntry?.payload?.source === deepLink && logEntry?.payload?.phase === "runtime"
    )

    validateDeepLinkPayload(entry)
    console.log(`Second instance smoke handed off ${deepLink}`)
    console.log(`Target: ${entry.payload.target}`)
  } finally {
    stopProcess(secondChild)
    stopProcess(firstChild)
    await stopServer()
    secondChild = null
    firstChild = null
    await wait(750)
  }
}

main().catch(async error => {
  stopProcess(secondChild)
  stopProcess(firstChild)
  await stopServer()
  console.error(error.message || error)
  process.exit(1)
})
