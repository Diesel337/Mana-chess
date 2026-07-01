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

        try {
          const state = await bridge?.getState?.();
          stateOk = Boolean(state && typeof state === "object");
        } catch (_error) {}

        try {
          const diagnostics = await bridge?.getDiagnostics?.();
          diagnosticsOk = Boolean(diagnostics?.window);
        } catch (_error) {}

        bridge?.sendEvent?.("desktop.bridge_smoke", {
          bridge: Boolean(bridge),
          isDesktop: info.isDesktop === true,
          channel: info.channel || "",
          version: info.version || "",
          stateOk,
          diagnosticsOk,
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
  if (payload.stateOk !== true) throw new Error("Expected bridge getState() to return desktop state.")
  if (payload.diagnosticsOk !== true) throw new Error("Expected bridge getDiagnostics() to return window diagnostics.")
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
      MANA_CHESS_DESKTOP_CHANNEL: channel,
      MANA_CHESS_OFFLINE_RETRY_SECONDS: "0"
    }
  })

  child.unref()

  try {
    const entry = await waitForBridgeLog(startTime)
    validateBridgePayload(entry)
    console.log(`Bridge smoke loaded ${smokeUrl}`)
    console.log(`Bridge: isDesktop=${entry.payload.isDesktop} channel=${entry.payload.channel} stateOk=${entry.payload.stateOk}`)
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
