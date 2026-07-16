const fs = require("node:fs")
const path = require("node:path")
const {spawnSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const repoRoot = path.resolve(desktopRoot, "..")
const defaultOrigin = "https://mana-chess-production.up.railway.app"
const placeholderIds = new Set(["480", "111111", "111112"])
const nativeRuntimeFiles = [
  path.join("dist", "win-unpacked", "resources", "app.asar.unpacked", "node_modules", "steamworks.js", "dist", "win64", "steam_api64.dll"),
  path.join("dist", "win-unpacked", "resources", "app.asar.unpacked", "node_modules", "steamworks.js", "dist", "win64", "steamworksjs.win32-x64-msvc.node")
]

function parseArgs(argv) {
  const args = {target: "internal", strict: false, json: false, network: true, origin: defaultOrigin}

  for (const argument of argv) {
    if (argument === "--strict") args.strict = true
    else if (argument === "--json") args.json = true
    else if (argument === "--no-network") args.network = false
    else if (argument === "--target=internal") args.target = "internal"
    else if (argument === "--target=release") args.target = "release"
    else if (argument.startsWith("--origin=")) args.origin = argument.slice("--origin=".length)
    else throw new Error(`Unknown option ${JSON.stringify(argument)}.`)
  }

  args.origin = secureOrigin(args.origin)
  if (!args.origin) throw new Error("Steam doctor origin must use HTTPS or loopback HTTP.")
  return args
}

function secureOrigin(value) {
  try {
    const url = new URL(String(value || ""))
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
    if (url.protocol !== "https:" && !(loopback && url.protocol === "http:")) return ""
    return url.origin
  } catch (_error) {
    return ""
  }
}

function gitOutput(args) {
  const result = spawnSync("git", args, {
    cwd: repoRoot,
    encoding: "utf8",
    windowsHide: true
  })
  return result.status === 0 ? String(result.stdout || "").trim() : ""
}

function readJson(relativePath) {
  const fullPath = path.join(desktopRoot, relativePath)
  if (!fs.existsSync(fullPath)) return null

  try {
    return JSON.parse(fs.readFileSync(fullPath, "utf8"))
  } catch (_error) {
    return null
  }
}

function steamId(value) {
  const text = String(value || "").trim()
  if (!/^[1-9][0-9]{0,9}$/.test(text) || placeholderIds.has(text)) return ""

  const parsed = Number(text)
  return Number.isSafeInteger(parsed) && parsed <= 4_294_967_295 ? String(parsed) : ""
}

function addCheck(checks, id, status, summary) {
  checks.push({id, status, summary: String(summary || "")})
}

function checkRepository(checks) {
  const commit = gitOutput(["rev-parse", "HEAD"])
  const branch = gitOutput(["branch", "--show-current"]) || "detached"
  const dirty = gitOutput(["status", "--porcelain", "--untracked-files=all"])

  if (!commit) addCheck(checks, "repository", "block", "Git repository state is unavailable.")
  else if (dirty) addCheck(checks, "repository", "block", `${branch} ${commit.slice(0, 12)} has uncommitted changes.`)
  else addCheck(checks, "repository", "pass", `${branch} ${commit.slice(0, 12)} is clean.`)

  return commit
}

function checkCandidate(checks, commit, target) {
  const manifest = readJson(path.join("dist", "release-manifest.json"))
  if (!manifest) {
    addCheck(checks, "candidate", "block", "Missing dist/release-manifest.json; run release:win:candidate.")
    addCheck(checks, "signing", target === "release" ? "block" : "warn", "No candidate signatures are available.")
    return
  }

  const buildCommit = String(manifest?.build?.commit || "")
  const dirty = String(manifest?.build?.dirty || "")
  const artifacts = Array.isArray(manifest.artifacts) ? manifest.artifacts : []
  const missingArtifacts = artifacts.filter(item => !fs.existsSync(path.join(desktopRoot, item.path || "")))

  if (!commit || buildCommit.length < 7 || !commit.startsWith(buildCommit) || dirty !== "false") {
    addCheck(
      checks,
      "candidate",
      "block",
      `Manifest build ${buildCommit || "missing"} dirty=${dirty || "missing"} is not the clean current commit.`
    )
  } else if (missingArtifacts.length > 0) {
    addCheck(checks, "candidate", "block", `${missingArtifacts.length} manifest artifacts are missing.`)
  } else {
    addCheck(checks, "candidate", "pass", `Windows ${manifest.version} matches ${buildCommit} with ${artifacts.length} artifacts.`)
  }

  const signatures = Array.isArray(manifest.windowsSignatures) ? manifest.windowsSignatures : []
  const validSignatures = signatures.length > 0 && signatures.every(item => item.status === "Valid")
  const signatureStatus = validSignatures ? "pass" : target === "release" ? "block" : "warn"
  addCheck(
    checks,
    "signing",
    signatureStatus,
    validSignatures ? `${signatures.length} Authenticode signatures are valid.` : "Candidate is not fully Authenticode signed."
  )
}

function checkNativeRuntime(checks) {
  const missing = nativeRuntimeFiles.filter(relativePath => !fs.existsSync(path.join(desktopRoot, relativePath)))
  if (missing.length === 0) addCheck(checks, "native_runtime", "pass", "Steam DLL and N-API binding are packaged.")
  else addCheck(checks, "native_runtime", "block", `Missing ${missing.map(item => path.basename(item)).join(", ")}.`)
}

function checkSteamIdentifiers(checks) {
  const appId = steamId(process.env.MANA_CHESS_STEAM_APP_ID || process.env.STEAM_APP_ID)
  const depotId = steamId(process.env.MANA_CHESS_STEAM_DEPOT_ID || process.env.STEAM_WINDOWS_DEPOT_ID)

  addCheck(
    checks,
    "app_id",
    appId ? "pass" : "block",
    appId ? `Release AppID ${appId} is configured.` : "Set a real MANA_CHESS_STEAM_APP_ID."
  )
  addCheck(
    checks,
    "depot_id",
    depotId && depotId !== appId ? "pass" : "block",
    depotId && depotId !== appId ? `Windows depot ${depotId} is configured.` : "Set a distinct real MANA_CHESS_STEAM_DEPOT_ID."
  )

  return {appId, depotId}
}

function steamCmdCandidate(candidate) {
  if (!candidate) return ""
  const normalized = path.resolve(String(candidate).trim().replace(/^"(.*)"$/, "$1"))
  if (!fs.existsSync(normalized)) return ""
  if (fs.statSync(normalized).isDirectory()) {
    const nested = path.join(normalized, "steamcmd.exe")
    return fs.existsSync(nested) ? nested : ""
  }
  return path.basename(normalized).toLowerCase() === "steamcmd.exe" ? normalized : ""
}

function steamCmdFromPath() {
  const result = spawnSync("where.exe", ["steamcmd.exe"], {
    cwd: desktopRoot,
    encoding: "utf8",
    windowsHide: true
  })
  if (result.status !== 0) return ""

  for (const candidate of String(result.stdout || "").split(/\r?\n/)) {
    const executable = steamCmdCandidate(candidate)
    if (executable) return executable
  }

  return ""
}

function checkSteamTools(checks) {
  const sdkRoot = String(process.env.STEAMWORKS_SDK_PATH || "").trim()
  const sdkSteamCmd = steamCmdCandidate(
    sdkRoot && path.join(sdkRoot, "tools", "ContentBuilder", "builder", "steamcmd.exe")
  )
  const fallbackSteamCmd = steamCmdCandidate(process.env.STEAMCMD_PATH) ||
    steamCmdCandidate(path.join(desktopRoot, "steam", "steamworks-sdk", "tools", "ContentBuilder", "builder")) ||
    steamCmdCandidate(path.join(desktopRoot, "steam", "steamcmd")) ||
    steamCmdFromPath()

  if (sdkSteamCmd) addCheck(checks, "steamworks_sdk", "pass", "SteamCMD is available from the configured Steamworks SDK.")
  else if (fallbackSteamCmd) addCheck(checks, "steamworks_sdk", "warn", "SteamCMD exists, but STEAMWORKS_SDK_PATH is not ready.")
  else addCheck(checks, "steamworks_sdk", "block", "Install the latest Steamworks SDK and set STEAMWORKS_SDK_PATH.")

  const username = String(process.env.MANA_CHESS_STEAM_USERNAME || process.env.STEAM_USERNAME || "").trim()
  const usernameReady = /^[A-Za-z0-9_.-]+$/.test(username)
  addCheck(
    checks,
    "build_account",
    usernameReady ? "pass" : "block",
    usernameReady ? "Steam build account name is present (value hidden)." : "Set MANA_CHESS_STEAM_USERNAME."
  )
}

async function fetchBackendConfiguration(origin) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), 10_000)

  try {
    const response = await fetch(new URL("/auth/steam/config", origin), {
      headers: {accept: "application/json", "x-mana-chess-desktop": "1"},
      cache: "no-store",
      redirect: "error",
      signal: controller.signal
    })
    const body = await response.json().catch(() => ({}))
    return {ok: response.ok, status: response.status, body}
  } finally {
    clearTimeout(timeout)
  }
}

async function checkBackend(checks, args, appId) {
  if (!args.network) {
    addCheck(checks, "backend", "block", "Backend verification was skipped with --no-network.")
    return
  }

  try {
    const response = await fetchBackendConfiguration(args.origin)
    const steam = response.body?.steam
    if (!response.ok || response.body?.ok !== true || !steam) {
      addCheck(checks, "backend", "block", `${args.origin} returned HTTP ${response.status} without Steam bootstrap.`)
      return
    }

    const backendAppId = steamId(steam.app_id)
    const protocolReady = steam.protocol_version === 1
    const identityReady = typeof steam.ticket_identity === "string" && steam.ticket_identity.trim().length > 0
    const appMatches = Boolean(appId && backendAppId === appId)

    if (!steam.configured) addCheck(checks, "backend", "block", "Railway Steam auth is not configured.")
    else if (!protocolReady || !identityReady) addCheck(checks, "backend", "block", "Railway Steam bootstrap contract is invalid.")
    else if (!appMatches) addCheck(checks, "backend", "block", `Railway AppID ${backendAppId || "missing"} does not match local release AppID.`)
    else addCheck(checks, "backend", "pass", `Railway protocol 1 is configured for AppID ${backendAppId}.`)

    const launchRequired = response.body.launch_required === true
    const launchStatus = launchRequired ? "pass" : args.target === "release" ? "block" : "warn"
    addCheck(
      checks,
      "launch_gate",
      launchStatus,
      launchRequired ? "Railway requires verified Steam sessions." : "Railway launch access remains open."
    )
  } catch (error) {
    const reason = error?.name === "AbortError" ? "timed out" : "is unreachable"
    addCheck(checks, "backend", "block", `${args.origin} ${reason}.`)
  }
}

function printReport(args, checks) {
  const counts = {pass: 0, warn: 0, block: 0}
  for (const check of checks) counts[check.status] += 1
  const ready = counts.block === 0

  if (args.json) {
    console.log(JSON.stringify({target: args.target, origin: args.origin, ready, counts, checks}, null, 2))
  } else {
    console.log(`Mana Chess Steam doctor (${args.target})`)
    console.log(`Backend: ${args.origin}`)
    for (const check of checks) {
      console.log(`[${check.status.toUpperCase()}] ${check.id}: ${check.summary}`)
    }
    console.log(`Result: ${ready ? "READY" : "WAITING"} (${counts.pass} pass, ${counts.warn} warn, ${counts.block} block)`)
  }

  if (args.strict && !ready) process.exitCode = 1
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  const checks = []
  const commit = checkRepository(checks)
  checkCandidate(checks, commit, args.target)
  checkNativeRuntime(checks)
  const {appId} = checkSteamIdentifiers(checks)
  checkSteamTools(checks)
  await checkBackend(checks, args, appId)
  printReport(args, checks)
}

main().catch(error => {
  console.error(`Steam doctor failed: ${error.message}`)
  process.exitCode = 1
})
