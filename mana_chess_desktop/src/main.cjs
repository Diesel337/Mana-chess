const fs = require("node:fs")
const path = require("node:path")
const {app, BrowserWindow, Menu, clipboard, ipcMain, screen, shell} = require("electron")

const DEFAULT_GAME_URL = process.env.MANA_CHESS_URL || "https://mana-chess-production.up.railway.app/"
const GAME_ORIGIN = new URL(DEFAULT_GAME_URL).origin
const PROTOCOL_SCHEME = "manachess"
const DESKTOP_BUILD_INFO_FILE = "build-info.generated.json"
const WINDOW_STATE_FILE = "window-state.json"
const DESKTOP_STATE_FILE = "desktop-state.json"
const DESKTOP_LOG_FILE = "desktop-log.jsonl"
const EVENT_LOG_LIMIT = 40
const DESKTOP_EVENT_PAYLOAD_MAX_BYTES = 4096
const DESKTOP_LOG_READ_LIMIT = 80
const DESKTOP_LOG_MAX_BYTES = 512 * 1024
const STEAM_ENV_NAMES = [
  "SteamAppId",
  "SteamGameId",
  "SteamOverlayGameId",
  "STEAM_APP_ID",
  "STEAM_APPID",
  "STEAM_GAME_ID",
  "STEAM_GAMEID",
  "STEAM_OVERLAY_GAME_ID",
  "SteamClientLaunch",
  "SteamEnv",
  "SteamPath",
  "SteamDeck",
  "SteamTenfoot"
]
const MIN_WINDOW_WIDTH = 1024
const MIN_WINDOW_HEIGHT = 720
const DEFAULT_WINDOW_WIDTH = 1440
const DEFAULT_WINDOW_HEIGHT = 960
const WINDOW_MODE_FULLSCREEN = "fullscreen"
const WINDOW_MODE_MAXIMIZED = "maximized"
const WINDOW_MODE_WINDOWED = "windowed"
const WINDOW_MODES = new Set([WINDOW_MODE_FULLSCREEN, WINDOW_MODE_MAXIMIZED, WINDOW_MODE_WINDOWED])
const DEFAULT_OFFLINE_RETRY_SECONDS = 20
const DESKTOP_BUILD_INFO = loadDesktopBuildInfo()
const DESKTOP_CHANNEL = process.env.MANA_CHESS_DESKTOP_CHANNEL || DESKTOP_BUILD_INFO.channel || "desktop"
const DESKTOP_QA_BYPASS_KEY = cleanQaBypassKey(process.env.MANA_CHESS_QA_BYPASS_KEY)
const DESKTOP_DISABLE_EXTERNAL_OPEN = process.env.MANA_CHESS_DISABLE_EXTERNAL_OPEN === "1"
const DESKTOP_STEAM_CONTEXT = steamLaunchContext()

let mainWindow = null
let pendingDeepLink = findDeepLink(process.argv)
let pendingGameUrl = gameUrlFromDeepLink(pendingDeepLink)
let saveWindowStateTimer = null
let lastNormalBounds = null
let desktopConnectionWasOffline = false

app.setAppUserModelId("com.diesel337.manachess")
registerProtocol()
bindProcessDiagnostics()

app.on("open-url", (event, url) => {
  event.preventDefault()
  openDeepLink(url)
})

function createWindow() {
  const windowState = readWindowState()
  lastNormalBounds = {...windowState.bounds}

  mainWindow = new BrowserWindow({
    ...windowState.bounds,
    minWidth: MIN_WINDOW_WIDTH,
    minHeight: MIN_WINDOW_HEIGHT,
    title: "Mana Chess",
    icon: path.join(__dirname, "../build/icon.png"),
    backgroundColor: "#111713",
    autoHideMenuBar: true,
    fullscreenable: true,
    show: false,
    webPreferences: {
      preload: `${__dirname}/preload.cjs`,
      additionalArguments: [
        `--mana-chess-version=${app.getVersion()}`,
        `--mana-chess-channel=${DESKTOP_CHANNEL}`,
        `--mana-chess-origin=${GAME_ORIGIN}`,
        `--mana-chess-build-commit=${DESKTOP_BUILD_INFO.commit}`,
        `--mana-chess-build-dirty=${DESKTOP_BUILD_INFO.dirty}`,
        `--mana-chess-build-time=${DESKTOP_BUILD_INFO.builtAt}`,
        `--mana-chess-build-source=${DESKTOP_BUILD_INFO.source}`,
        `--mana-chess-steam-detected=${DESKTOP_STEAM_CONTEXT.detected ? "1" : "0"}`,
        `--mana-chess-steam-app-id=${DESKTOP_STEAM_CONTEXT.appId}`,
        `--mana-chess-steam-game-id=${DESKTOP_STEAM_CONTEXT.gameId}`,
        `--mana-chess-steam-overlay-game-id=${DESKTOP_STEAM_CONTEXT.overlayGameId}`,
        `--mana-chess-steam-client-launch=${DESKTOP_STEAM_CONTEXT.clientLaunch ? "1" : "0"}`,
        `--mana-chess-steam-env=${DESKTOP_STEAM_CONTEXT.steamEnv ? "1" : "0"}`,
        `--mana-chess-steam-path=${DESKTOP_STEAM_CONTEXT.steamPath ? "1" : "0"}`,
        `--mana-chess-steam-deck=${DESKTOP_STEAM_CONTEXT.steamDeck ? "1" : "0"}`,
        `--mana-chess-steam-tenfoot=${DESKTOP_STEAM_CONTEXT.steamTenfoot ? "1" : "0"}`,
        `--mana-chess-steam-present-keys=${DESKTOP_STEAM_CONTEXT.presentKeys.join(",")}`
      ],
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  bindWindowState(windowState)
  bindNavigationGuards()
  bindShortcuts()
  applyDesktopPresence(readDesktopState().presence)

  mainWindow.once("ready-to-show", () => {
    if (windowState.isMaximized) mainWindow.maximize()
    if (windowState.isFullScreen) mainWindow.setFullScreen(true)
    mainWindow.show()
  })

  const initialDeepLink = pendingDeepLink
  const initialUrl = pendingGameUrl || DEFAULT_GAME_URL
  pendingDeepLink = null
  pendingGameUrl = null
  loadGameUrl(initialUrl)
  logDeepLinkOpened(initialDeepLink, initialUrl, "startup")
}

function bindDesktopBridge() {
  ipcMain.handle("mana-chess:copy-share-link", (_event, url) => {
    const shareUrl = cleanShareUrl(url) || cleanShareUrl(mainWindow?.webContents.getURL()) || DEFAULT_GAME_URL
    clipboard.writeText(shareUrl)
    return {ok: true, url: shareUrl}
  })

  ipcMain.handle("mana-chess:open-share-link", async (_event, url) => {
    const shareUrl = cleanShareUrl(url) || cleanShareUrl(mainWindow?.webContents.getURL()) || DEFAULT_GAME_URL
    return openExternalUrl(shareUrl, "bridge.openShareLink")
  })

  ipcMain.handle("mana-chess:copy-deep-link", (_event, url) => copyDeepLinkForUrl(url || mainWindow?.webContents.getURL()))

  ipcMain.handle("mana-chess:get-desktop-state", () => readDesktopState())

  ipcMain.handle("mana-chess:get-desktop-diagnostics", () => desktopDiagnostics())

  ipcMain.handle("mana-chess:copy-desktop-state", () => copyDesktopState())

  ipcMain.handle("mana-chess:copy-desktop-diagnostics", () => copyDesktopDiagnostics())

  ipcMain.handle("mana-chess:open-desktop-state-folder", () => openDesktopStateFolder())

  ipcMain.handle("mana-chess:open-desktop-log-folder", () => openDesktopLogFolder())

  ipcMain.handle("mana-chess:reset-desktop-state", () => resetDesktopState())

  ipcMain.on("mana-chess:desktop-event", (_event, event) => recordDesktopEvent(event))
}

function buildMenu() {
  return Menu.buildFromTemplate([
    {
      label: "Mana Chess",
      submenu: [
        {
          label: "Volver al lobby",
          accelerator: "CommandOrControl+L",
          click: () => navigateHome()
        },
        {
          label: "Copiar link actual",
          accelerator: "CommandOrControl+Shift+C",
          click: () => copyCurrentLink()
        },
        {
          label: "Copiar deep link desktop",
          click: () => copyCurrentDeepLink()
        },
        {
          label: "Desktop",
          submenu: [
            {
              label: "Copiar estado local",
              click: () => copyDesktopState()
            },
            {
              label: "Copiar diagnostico QA",
              click: () => copyDesktopDiagnostics()
            },
            {
              label: "Abrir datos desktop",
              click: () => openDesktopStateFolder()
            },
            {
              label: "Abrir logs desktop",
              click: () => openDesktopLogFolder()
            },
            {
              label: "Reiniciar estado local",
              click: () => resetDesktopState()
            }
          ]
        },
        {
          label: "Recargar",
          accelerator: "CommandOrControl+R",
          click: () => mainWindow?.reload()
        },
        {
          label: "Pantalla completa",
          accelerator: "F11",
          click: () => toggleFullscreen()
        },
        {type: "separator"},
        {
          label: "Abrir link actual en web",
          click: () => openCurrentWebLink()
        },
        {type: "separator"},
        {
          label: "Salir",
          role: "quit"
        }
      ]
    },
    {
      label: "Vista",
      submenu: [
        {label: "Acercar", role: "zoomIn"},
        {label: "Alejar", role: "zoomOut"},
        {label: "Zoom normal", role: "resetZoom"}
      ]
    }
  ])
}

function bindNavigationGuards() {
  mainWindow.webContents.setWindowOpenHandler(({url}) => {
    const parsed = safeUrl(url)
    if (!parsed) return {action: "deny"}

    if (parsed.origin === GAME_ORIGIN) {
      loadGameUrl(url)
      return {action: "deny"}
    }

    void openExternalUrl(url, "navigation.window_open")
    return {action: "deny"}
  })

  mainWindow.webContents.on("will-navigate", (event, url) => {
    const parsed = safeUrl(url)
    if (!parsed) {
      event.preventDefault()
      return
    }

    if (parsed.origin === GAME_ORIGIN) {
      if (parsed.searchParams.get("desktop") !== "1") {
        event.preventDefault()
        loadGameUrl(url)
      }
      return
    }

    event.preventDefault()
    void openExternalUrl(url, "navigation.will_navigate")
  })

  mainWindow.webContents.on("page-title-updated", event => {
    event.preventDefault()
    applyDesktopPresence(readDesktopState().presence)
  })

  mainWindow.webContents.on("did-fail-load", (_event, errorCode, errorDescription, validatedURL, isMainFrame) => {
    if (!isMainFrame) return

    const parsed = safeUrl(validatedURL)
    if (parsed?.origin !== GAME_ORIGIN) return

    appendDesktopLog("warn", "desktop.did_fail_load", {errorCode, errorDescription, url: cleanShareUrl(validatedURL)})
    showOfflineScreen(validatedURL, {errorCode, errorDescription})
  })

  mainWindow.webContents.on("did-finish-load", () => {
    if (!desktopConnectionWasOffline) return

    const parsed = safeUrl(mainWindow.webContents.getURL())
    if (parsed?.origin !== GAME_ORIGIN) return

    desktopConnectionWasOffline = false
    recordDesktopEvent({
      name: "desktop.reconnected",
      payload: {url: cleanShareUrl(parsed.toString()) || DEFAULT_GAME_URL}
    })
  })

  mainWindow.webContents.on("render-process-gone", (_event, details) => {
    appendDesktopLog("error", "desktop.render_process_gone", details)
  })

  mainWindow.webContents.on("console-message", (_event, level, message, line, sourceId) => {
    const renderedMessage = String(message || "")
    const numericLevel = Number(level)
    const shouldLog = Number.isFinite(numericLevel)
      ? numericLevel >= 2
      : /error|failed|exception|unhandled/i.test(renderedMessage)

    if (!shouldLog) return

    appendDesktopLog("renderer", "desktop.console_message", {
      level,
      message: renderedMessage.slice(0, 1000),
      line,
      sourceId: cleanShareUrl(sourceId) || String(sourceId || "").slice(0, 240)
    })
  })

  mainWindow.on("unresponsive", () => {
    appendDesktopLog("warn", "desktop.window_unresponsive", {url: currentShareUrl()})
  })

  mainWindow.on("responsive", () => {
    appendDesktopLog("info", "desktop.window_responsive", {url: currentShareUrl()})
  })
}

function bindShortcuts() {
  mainWindow.webContents.on("before-input-event", (event, input) => {
    if (input.type !== "keyDown") return
    if (input.key !== "Escape") return
    if (!mainWindow.isFullScreen()) return

    event.preventDefault()
    mainWindow.setFullScreen(false)
  })
}

function bindWindowState(windowState) {
  for (const eventName of ["resize", "move", "maximize", "unmaximize", "enter-full-screen", "leave-full-screen"]) {
    mainWindow.on(eventName, queueSaveWindowState)
  }

  mainWindow.on("close", saveWindowStateNow)

  if (windowState.isMaximized || windowState.isFullScreen) {
    queueSaveWindowState()
  }
}

function navigateHome() {
  loadGameUrl(DEFAULT_GAME_URL)
}

function loadGameUrl(url) {
  const targetUrl = desktopUrl(url)

  if (!mainWindow) {
    pendingGameUrl = url
    return
  }

  mainWindow.loadURL(targetUrl)
}

function openDeepLink(url) {
  const targetUrl = gameUrlFromDeepLink(url)
  if (!targetUrl) return false

  if (!mainWindow) {
    pendingDeepLink = url
    pendingGameUrl = targetUrl
    return true
  }

  loadGameUrl(targetUrl)
  logDeepLinkOpened(url, targetUrl, "runtime")
  focusMainWindow()
  return true
}

function logDeepLinkOpened(url, targetUrl, phase) {
  if (!url) return

  appendDesktopLog("info", "desktop.deep_link_opened", {
    source: String(url || "").slice(0, 300),
    target: cleanShareUrl(targetUrl) || String(targetUrl || "").slice(0, 300),
    phase
  })
}

function focusMainWindow() {
  if (!mainWindow) return
  if (mainWindow.isMinimized()) mainWindow.restore()
  mainWindow.show()
  mainWindow.focus()
}

function toggleFullscreen() {
  if (!mainWindow) return
  mainWindow.setFullScreen(!mainWindow.isFullScreen())
}

function currentShareUrl() {
  if (!mainWindow) return DEFAULT_GAME_URL
  return cleanShareUrl(mainWindow.webContents.getURL()) || DEFAULT_GAME_URL
}

function copyCurrentLink() {
  clipboard.writeText(currentShareUrl())
}

function copyCurrentDeepLink() {
  copyDeepLinkForUrl(mainWindow?.webContents.getURL())
}

function openCurrentWebLink() {
  void openExternalUrl(currentShareUrl(), "menu.openCurrentWebLink")
}

async function openExternalUrl(url, source = "desktop") {
  const parsed = safeUrl(String(url || ""))
  const safeLogUrl = externalLogUrl(url)

  if (!parsed) {
    const error = "invalid_url"
    appendDesktopLog("warn", "desktop.external_link_failed", {source, url: "", error})
    return {ok: false, url: "", error}
  }

  if (!externalProtocolAllowed(parsed)) {
    const error = "blocked_protocol"
    appendDesktopLog("warn", "desktop.external_link_blocked", {
      source,
      url: safeLogUrl,
      protocol: String(parsed.protocol || "").slice(0, 24),
      error
    })
    return {ok: false, url: parsed.toString(), error}
  }

  try {
    if (DESKTOP_DISABLE_EXTERNAL_OPEN) {
      appendDesktopLog("info", "desktop.external_link_opened", {source, url: safeLogUrl, skipped: true})
      return {ok: true, url: parsed.toString(), skipped: true}
    }

    await shell.openExternal(parsed.toString())
    appendDesktopLog("info", "desktop.external_link_opened", {source, url: safeLogUrl})
    return {ok: true, url: parsed.toString()}
  } catch (error) {
    const message = String(error?.message || error || "").slice(0, 1000)
    appendDesktopLog("warn", "desktop.external_link_failed", {source, url: safeLogUrl, error: message})
    return {ok: false, url: parsed.toString(), error: message}
  }
}

function externalLogUrl(url) {
  const shareUrl = cleanShareUrl(url)
  if (shareUrl) return shareUrl.slice(0, 300)

  const parsed = safeUrl(String(url || ""))
  if (!parsed) return ""

  return `${parsed.origin}${parsed.pathname}`.slice(0, 300)
}

function externalProtocolAllowed(parsed) {
  return parsed?.protocol === "http:" || parsed?.protocol === "https:"
}

function desktopStatePath() {
  const dataPath = desktopUserDataPath()
  return dataPath ? path.join(dataPath, DESKTOP_STATE_FILE) : DESKTOP_STATE_FILE
}

function readDesktopState() {
  try {
    return normalizeDesktopState(JSON.parse(fs.readFileSync(desktopStatePath(), "utf8")))
  } catch (_error) {
    return normalizeDesktopState({})
  }
}

function writeDesktopState(state) {
  try {
    const dataPath = desktopUserDataPath()
    if (!dataPath) return

    fs.mkdirSync(dataPath, {recursive: true})
    fs.writeFileSync(desktopStatePath(), JSON.stringify(normalizeDesktopState(state), null, 2))
  } catch (_error) {
    // Desktop state should never block gameplay or app launch.
  }
}

function normalizeDesktopState(state) {
  return {
    version: 1,
    updatedAt: typeof state.updatedAt === "string" ? state.updatedAt : "",
    presence: typeof state.presence === "object" && state.presence ? state.presence : desktopPresence("lobby"),
    counters: typeof state.counters === "object" && state.counters ? state.counters : {},
    achievements: typeof state.achievements === "object" && state.achievements ? state.achievements : {},
    seen: typeof state.seen === "object" && state.seen ? state.seen : {},
    lastEvents: Array.isArray(state.lastEvents) ? state.lastEvents.slice(0, EVENT_LOG_LIMIT) : []
  }
}

function copyDesktopState() {
  const state = readDesktopState()
  clipboard.writeText(JSON.stringify(state, null, 2))
  return {ok: true, state}
}

function desktopDiagnostics() {
  return {
    ok: true,
    app: {
      name: app.getName(),
      version: app.getVersion(),
      channel: DESKTOP_CHANNEL,
      platform: process.platform,
      origin: GAME_ORIGIN,
      build: desktopBuildInfo(),
      steam: DESKTOP_STEAM_CONTEXT
    },
    window: currentWindowDiagnostics(),
    paths: {
      userData: desktopUserDataPath(),
      state: desktopStatePath(),
      log: desktopLogPath()
    },
    state: readDesktopState(),
    recentLog: readDesktopLogLines()
  }
}

function currentWindowDiagnostics() {
  if (!mainWindow || mainWindow.isDestroyed()) {
    return {exists: false}
  }

  return {
    exists: true,
    url: cleanShareUrl(mainWindow.webContents.getURL()) || "",
    title: mainWindow.getTitle(),
    bounds: mainWindow.getBounds(),
    isMaximized: mainWindow.isMaximized(),
    isFullScreen: mainWindow.isFullScreen(),
    isMinimized: mainWindow.isMinimized()
  }
}

function copyDesktopDiagnostics() {
  const diagnostics = desktopDiagnostics()
  clipboard.writeText(JSON.stringify(diagnostics, null, 2))
  appendDesktopLog("info", "desktop.diagnostics_copied", {url: diagnostics.window.url})
  return {ok: true, diagnostics}
}

async function openDesktopStateFolder() {
  try {
    const dataPath = desktopUserDataPath()
    fs.mkdirSync(dataPath, {recursive: true})
    const error = await shell.openPath(dataPath)
    return {ok: !error, path: dataPath, error}
  } catch (error) {
    return {ok: false, error: String(error?.message || error)}
  }
}

async function openDesktopLogFolder() {
  try {
    const dataPath = desktopUserDataPath()
    fs.mkdirSync(dataPath, {recursive: true})
    ensureDesktopLogFile()
    const error = await shell.openPath(dataPath)
    appendDesktopLog(error ? "warn" : "info", "desktop.log_folder_opened", {path: dataPath, error})
    return {ok: !error, path: dataPath, log: desktopLogPath(), error}
  } catch (error) {
    return {ok: false, error: String(error?.message || error)}
  }
}

function resetDesktopState() {
  writeDesktopState(normalizeDesktopState({}))
  return recordDesktopEvent({
    name: "desktop.session_started",
    payload: desktopSessionPayload({reset: true})
  }) || readDesktopState()
}

function applyDesktopPresence(presence = {}) {
  const label = typeof presence.label === "string" ? presence.label.trim() : ""
  const title = label ? `Mana Chess - ${label}` : "Mana Chess"

  if (!mainWindow || mainWindow.isDestroyed()) return title

  mainWindow.setTitle(title)
  return title
}

function recordDesktopEvent(event) {
  const normalizedEvent = normalizeDesktopEvent(event)
  if (!normalizedEvent) return null

  appendDesktopLog("event", normalizedEvent.name, normalizedEvent.payload)
  const state = updateDesktopState(readDesktopState(), normalizedEvent)
  writeDesktopState(state)
  applyDesktopPresence(state.presence)
  return state
}

function desktopSessionPayload(extra = {}) {
  return {
    version: app.getVersion(),
    channel: DESKTOP_CHANNEL,
    launchMode: launchWindowMode() || "saved",
    steam: DESKTOP_STEAM_CONTEXT,
    ...extra
  }
}

function normalizeDesktopEvent(event) {
  if (!event || typeof event.name !== "string") return null

  const name = event.name.trim().slice(0, 80)
  if (!name) return null

  return {
    name,
    payload: normalizeDesktopEventPayload(event.payload),
    at: new Date().toISOString()
  }
}

function normalizeDesktopEventPayload(payload) {
  const cloned = cloneJson(payload)
  const serialized = JSON.stringify(cloned)
  const bytes = Buffer.byteLength(serialized || "{}", "utf8")

  if (bytes <= DESKTOP_EVENT_PAYLOAD_MAX_BYTES) return cloned

  return {
    truncated: true,
    originalBytes: bytes,
    maxBytes: DESKTOP_EVENT_PAYLOAD_MAX_BYTES
  }
}

function cloneJson(value) {
  try {
    return JSON.parse(JSON.stringify(value || {}))
  } catch (_error) {
    return {}
  }
}

function updateDesktopState(state, event) {
  const next = normalizeDesktopState(state)
  const {name, payload, at} = event

  next.updatedAt = at
  next.lastEvents = [event, ...next.lastEvents].slice(0, EVENT_LOG_LIMIT)
  incrementCounter(next, `event:${name}`)

  if (name === "desktop.session_started") {
    incrementCounter(next, "sessions")
    unlockAchievement(next, "desktop_session", "Abrir Mana Chess Desktop", at)
    next.presence = desktopPresence("lobby", payload, at)
  }

  if (name === "desktop.offline") {
    incrementCounter(next, "offlineScreens")
    next.presence = desktopPresence("offline", payload, at)
  }

  if (name === "desktop.reconnected") {
    incrementCounter(next, "reconnections")
    next.presence = desktopPresence("lobby", payload, at)
  }

  if (name === "screen.viewed") {
    next.presence = desktopPresence(payload.screen || "lobby", payload, at)
  }

  if (name === "match.opened") {
    next.presence = desktopPresence("game", payload, at)
    if (markSeen(next, "openedMatches", payload.gameId)) incrementCounter(next, "matchesOpened")
    if (String(payload.gameId || "").startsWith("private_")) unlockAchievement(next, "private_match", "Abrir partida privada", at)
  }

  if (name === "match.status_changed") {
    next.presence = desktopPresence("game", payload, at)
  }

  if (name === "match.started") {
    next.presence = desktopPresence("playing", payload, at)
    if (markSeen(next, "startedMatches", payload.gameId)) incrementCounter(next, "matchesStarted")
    unlockAchievement(next, "first_match", "Iniciar primera partida", at)
  }

  if (name === "match.finished") {
    next.presence = desktopPresence("result", payload, at)
    const newResult = markSeen(next, "finishedResults", payload.resultKey || payload.gameId)

    if (newResult) {
      incrementCounter(next, "matchesFinished")
      if (payload.result === "win") {
        incrementCounter(next, "wins")
        unlockAchievement(next, "first_win", "Primera victoria", at)
      }
      if (payload.result === "loss") incrementCounter(next, "losses")
      if (payload.result === "draw") {
        incrementCounter(next, "draws")
        unlockAchievement(next, "first_draw", "Primer empate", at)
      }
    }

    unlockAchievement(next, "first_result", "Terminar primera partida", at)
  }

  return next
}

function desktopPresence(kind, payload = {}, at = new Date().toISOString()) {
  const labels = {
    lobby: "En lobby",
    offline: "Sin conexion",
    game: "En partida",
    playing: "Jugando partida",
    result: resultPresenceLabel(payload.result)
  }

  return {
    kind,
    label: labels[kind] || labels.lobby,
    gameId: payload.gameId || "",
    status: payload.status || "",
    screen: payload.screen || (payload.gameId ? "game" : "lobby"),
    updatedAt: at
  }
}

function resultPresenceLabel(result) {
  if (result === "win") return "Victoria registrada"
  if (result === "loss") return "Derrota registrada"
  if (result === "draw") return "Empate registrado"
  return "Partida terminada"
}

function incrementCounter(state, key) {
  state.counters[key] = Number.isFinite(state.counters[key]) ? state.counters[key] + 1 : 1
}

function markSeen(state, bucket, value) {
  if (!value) return true
  const seen = Array.isArray(state.seen[bucket]) ? state.seen[bucket] : []
  if (seen.includes(value)) return false

  state.seen[bucket] = [value, ...seen].slice(0, 80)
  return true
}

function unlockAchievement(state, id, title, at) {
  if (state.achievements[id]) return
  state.achievements[id] = {id, title, unlockedAt: at}
}

function loadDesktopBuildInfo() {
  const fallback = {
    version: "",
    channel: "desktop",
    commit: process.env.MANA_CHESS_BUILD_COMMIT || "dev",
    dirty: process.env.MANA_CHESS_BUILD_DIRTY || "unknown",
    builtAt: process.env.MANA_CHESS_BUILD_TIME || "",
    source: "runtime"
  }

  try {
    const buildInfoPath = path.join(__dirname, DESKTOP_BUILD_INFO_FILE)
    return normalizeDesktopBuildInfo(JSON.parse(fs.readFileSync(buildInfoPath, "utf8")), fallback)
  } catch (_error) {
    return normalizeDesktopBuildInfo({}, fallback)
  }
}

function normalizeDesktopBuildInfo(info, fallback = {}) {
  return {
    version: String(info.version || fallback.version || ""),
    channel: String(info.channel || fallback.channel || "desktop"),
    commit: String(info.commit || fallback.commit || "dev").slice(0, 80),
    dirty: String(info.dirty || fallback.dirty || "unknown").slice(0, 16),
    builtAt: String(info.builtAt || fallback.builtAt || "").slice(0, 80),
    source: String(info.source || fallback.source || "runtime").slice(0, 40)
  }
}

function desktopBuildInfo() {
  return {
    ...DESKTOP_BUILD_INFO,
    version: DESKTOP_BUILD_INFO.version || app.getVersion(),
    channel: DESKTOP_CHANNEL
  }
}

function steamLaunchContext(env = process.env) {
  const appId = cleanSteamId(readEnv(env, ["SteamAppId", "STEAM_APP_ID", "STEAM_APPID"]))
  const gameId = cleanSteamId(readEnv(env, ["SteamGameId", "STEAM_GAME_ID", "STEAM_GAMEID"]))
  const overlayGameId = cleanSteamId(readEnv(env, ["SteamOverlayGameId", "STEAM_OVERLAY_GAME_ID"]))
  const presentKeys = presentSteamEnvKeys(env)

  return {
    detected: Boolean(appId || gameId || overlayGameId || presentKeys.length > 0),
    appId,
    gameId,
    overlayGameId,
    clientLaunch: Boolean(readEnv(env, ["SteamClientLaunch"])),
    steamEnv: Boolean(readEnv(env, ["SteamEnv"])),
    steamPath: Boolean(readEnv(env, ["SteamPath"])),
    steamDeck: Boolean(readEnv(env, ["SteamDeck"])),
    steamTenfoot: Boolean(readEnv(env, ["SteamTenfoot"])),
    presentKeys
  }
}

function presentSteamEnvKeys(env = process.env) {
  return STEAM_ENV_NAMES.filter(name => readEnv(env, [name]))
}

function readEnv(env = process.env, names = []) {
  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(env, name)) return String(env[name] || "").trim()

    const normalizedName = String(name || "").toLowerCase()
    const actualName = Object.keys(env).find(key => key.toLowerCase() === normalizedName)
    if (actualName) return String(env[actualName] || "").trim()
  }

  return ""
}

function cleanSteamId(value) {
  const text = String(value || "").trim()
  return /^[0-9]{1,32}$/.test(text) ? text : ""
}

function bindProcessDiagnostics() {
  process.on("uncaughtException", error => {
    appendDesktopLog("fatal", "main.uncaught_exception", errorPayload(error))
  })

  process.on("unhandledRejection", reason => {
    appendDesktopLog("fatal", "main.unhandled_rejection", errorPayload(reason))
  })

  app.on("child-process-gone", (_event, details) => {
    appendDesktopLog("error", "desktop.child_process_gone", details)
  })
}

function errorPayload(error) {
  return {
    message: String(error?.message || error || "").slice(0, 1000),
    stack: String(error?.stack || "").slice(0, 4000)
  }
}

function desktopUserDataPath() {
  try {
    return app.getPath("userData")
  } catch (_error) {
    return ""
  }
}

function desktopLogPath() {
  const dataPath = desktopUserDataPath()
  return dataPath ? path.join(dataPath, DESKTOP_LOG_FILE) : ""
}

function ensureDesktopLogFile() {
  const logPath = desktopLogPath()
  if (!logPath) return ""

  fs.mkdirSync(path.dirname(logPath), {recursive: true})
  if (!fs.existsSync(logPath)) fs.writeFileSync(logPath, "")
  return logPath
}

function appendDesktopLog(level, name, payload = {}) {
  const logPath = desktopLogPath()
  if (!logPath) return

  try {
    fs.mkdirSync(path.dirname(logPath), {recursive: true})
    trimDesktopLogFile(logPath)
    fs.appendFileSync(logPath, `${JSON.stringify({
      at: new Date().toISOString(),
      level: String(level || "info").slice(0, 24),
      name: String(name || "desktop.event").slice(0, 100),
      version: app.getVersion(),
      channel: DESKTOP_CHANNEL,
      commit: DESKTOP_BUILD_INFO.commit,
      payload: cloneJson(payload)
    })}\n`)
  } catch (_error) {
    // Diagnostics should never block gameplay or app launch.
  }
}

function trimDesktopLogFile(logPath = desktopLogPath()) {
  if (!logPath) return

  try {
    const stat = fs.statSync(logPath)
    if (stat.size <= DESKTOP_LOG_MAX_BYTES) return

    const keepBytes = Math.floor(DESKTOP_LOG_MAX_BYTES * 0.75)
    const buffer = fs.readFileSync(logPath)
    const tail = buffer.subarray(Math.max(0, buffer.length - keepBytes))
    const firstNewline = tail.indexOf(10)
    const trimmedTail = firstNewline >= 0 ? tail.subarray(firstNewline + 1) : tail
    fs.writeFileSync(logPath, trimmedTail)
  } catch (_error) {
    // Missing logs are fine; they will be recreated on the next write.
  }
}

function readDesktopLogLines(limit = DESKTOP_LOG_READ_LIMIT) {
  const logPath = desktopLogPath()
  if (!logPath) return []

  try {
    const text = fs.readFileSync(logPath, "utf8").trim()
    if (!text) return []

    return text.split(/\r?\n/).slice(-limit)
  } catch (_error) {
    return []
  }
}

function cleanShareUrl(url) {
  const parsed = safeUrl(String(url || ""))
  if (!parsed || parsed.origin !== GAME_ORIGIN) return null
  parsed.searchParams.delete("desktop")
  parsed.searchParams.delete("qa_key")
  return parsed.toString()
}

function copyDeepLinkForUrl(url) {
  const deepLink = deepLinkForGameUrl(url)
  clipboard.writeText(deepLink)
  return {ok: true, url: deepLink}
}

function deepLinkForGameUrl(url) {
  const parsed = safeUrl(cleanShareUrl(url) || DEFAULT_GAME_URL)
  if (!parsed || parsed.origin !== GAME_ORIGIN) return `${PROTOCOL_SCHEME}://lobby`

  const parts = parsed.pathname.split("/").filter(Boolean)
  if (parts[0] === "game" && parts[1]) return `${PROTOCOL_SCHEME}://game/${encodeURIComponent(parts[1])}`

  return `${PROTOCOL_SCHEME}://lobby`
}

function desktopUrl(url) {
  const parsed = new URL(url, DEFAULT_GAME_URL)
  parsed.searchParams.set("desktop", "1")
  if (DESKTOP_QA_BYPASS_KEY) parsed.searchParams.set("qa_key", DESKTOP_QA_BYPASS_KEY)
  return parsed.toString()
}

function cleanQaBypassKey(value) {
  return String(value || "").trim().slice(0, 256)
}

function safeUrl(url) {
  try {
    return new URL(url)
  } catch (_error) {
    return null
  }
}

function findDeepLink(argv) {
  return argv.find(arg => typeof arg === "string" && arg.startsWith(`${PROTOCOL_SCHEME}:`)) || null
}

function gameUrlFromDeepLink(url) {
  const route = routeFromDeepLink(url)
  if (!route) return null
  return new URL(route, DEFAULT_GAME_URL).toString()
}

function routeFromDeepLink(url) {
  const parsed = safeUrl(url)
  if (!parsed || parsed.protocol !== `${PROTOCOL_SCHEME}:`) return null

  const parts = [
    parsed.hostname,
    ...parsed.pathname.split("/").filter(Boolean)
  ].filter(Boolean)

  if (parts.length === 0 || parts[0] === "lobby") return "/"
  if (parts[0] === "game" && parts[1]) return gameRoute(parts[1])
  if (parts[0].startsWith("game_") || parts[0].startsWith("private_")) return gameRoute(parts[0])

  return "/"
}

function gameRoute(gameId) {
  return `/game/${encodeURIComponent(gameId)}`
}

function registerProtocol() {
  if (process.defaultApp && process.argv.length >= 2) {
    app.setAsDefaultProtocolClient(PROTOCOL_SCHEME, process.execPath, [path.resolve(process.argv[1])])
    return
  }

  app.setAsDefaultProtocolClient(PROTOCOL_SCHEME)
}

function windowStatePath() {
  return path.join(app.getPath("userData"), WINDOW_STATE_FILE)
}

function readWindowState() {
  const defaultState = defaultWindowState()

  try {
    const savedState = JSON.parse(fs.readFileSync(windowStatePath(), "utf8"))
    const normalizedState = normalizeWindowState(savedState, defaultState)
    const visibleState = boundsAreVisible(normalizedState.bounds) ? normalizedState : defaultState
    return applyLaunchWindowMode(visibleState)
  } catch (_error) {
    return applyLaunchWindowMode(defaultState)
  }
}

function applyLaunchWindowMode(windowState, mode = launchWindowMode()) {
  if (mode === WINDOW_MODE_FULLSCREEN) {
    return {...windowState, isMaximized: false, isFullScreen: true}
  }

  if (mode === WINDOW_MODE_MAXIMIZED) {
    return {...windowState, isMaximized: true, isFullScreen: false}
  }

  if (mode === WINDOW_MODE_WINDOWED) {
    return {...windowState, isMaximized: false, isFullScreen: false}
  }

  return windowState
}

function launchWindowMode(argv = process.argv, env = process.env) {
  const argMode = launchWindowModeFromArgv(argv)
  if (argMode) return argMode

  return normalizeWindowMode(env.MANA_CHESS_WINDOW_MODE)
}

function launchWindowModeFromArgv(argv = []) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (typeof arg !== "string") continue

    if (arg === "--fullscreen") return WINDOW_MODE_FULLSCREEN
    if (arg === "--maximized") return WINDOW_MODE_MAXIMIZED
    if (arg === "--windowed") return WINDOW_MODE_WINDOWED
    if (arg === "--window-mode") return normalizeWindowMode(argv[index + 1])
    if (arg.startsWith("--window-mode=")) return normalizeWindowMode(arg.slice("--window-mode=".length))
  }

  return ""
}

function normalizeWindowMode(value) {
  const mode = String(value || "").trim().toLowerCase()
  return WINDOW_MODES.has(mode) ? mode : ""
}

function offlineRetrySeconds(argv = process.argv, env = process.env) {
  const argValue = readLaunchArg(argv, "--offline-retry-seconds")
  const rawValue = argValue || env.MANA_CHESS_OFFLINE_RETRY_SECONDS
  if (typeof rawValue === "undefined" || rawValue === "") return DEFAULT_OFFLINE_RETRY_SECONDS

  const seconds = Number(rawValue)
  if (!Number.isFinite(seconds) || seconds < 0) return DEFAULT_OFFLINE_RETRY_SECONDS

  return Math.round(seconds)
}

function readLaunchArg(argv = [], name) {
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === name) return argv[index + 1]
    if (typeof arg === "string" && arg.startsWith(`${name}=`)) return arg.slice(name.length + 1)
  }

  return ""
}

function defaultWindowState() {
  const {width, height} = screen.getPrimaryDisplay().workAreaSize

  return {
    bounds: {
      width: Math.min(width, DEFAULT_WINDOW_WIDTH),
      height: Math.min(height, DEFAULT_WINDOW_HEIGHT)
    },
    isMaximized: true,
    isFullScreen: false
  }
}

function normalizeWindowState(savedState, defaultState) {
  const workArea = screen.getPrimaryDisplay().workAreaSize
  const savedBounds = savedState?.bounds || {}
  const bounds = {...defaultState.bounds}

  if (Number.isFinite(savedBounds.width)) {
    bounds.width = clamp(Math.round(savedBounds.width), MIN_WINDOW_WIDTH, Math.max(MIN_WINDOW_WIDTH, workArea.width))
  }

  if (Number.isFinite(savedBounds.height)) {
    bounds.height = clamp(Math.round(savedBounds.height), MIN_WINDOW_HEIGHT, Math.max(MIN_WINDOW_HEIGHT, workArea.height))
  }

  if (Number.isFinite(savedBounds.x)) bounds.x = Math.round(savedBounds.x)
  if (Number.isFinite(savedBounds.y)) bounds.y = Math.round(savedBounds.y)

  return {
    bounds,
    isMaximized: typeof savedState?.isMaximized === "boolean" ? savedState.isMaximized : defaultState.isMaximized,
    isFullScreen: typeof savedState?.isFullScreen === "boolean" ? savedState.isFullScreen : defaultState.isFullScreen
  }
}

function boundsAreVisible(bounds) {
  if (!Number.isFinite(bounds.x) || !Number.isFinite(bounds.y)) return true

  return screen.getAllDisplays().some(display => {
    const {workArea} = display
    const overlapX = Math.max(0, Math.min(bounds.x + bounds.width, workArea.x + workArea.width) - Math.max(bounds.x, workArea.x))
    const overlapY = Math.max(0, Math.min(bounds.y + bounds.height, workArea.y + workArea.height) - Math.max(bounds.y, workArea.y))
    return overlapX > 80 && overlapY > 80
  })
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function queueSaveWindowState() {
  clearTimeout(saveWindowStateTimer)
  saveWindowStateTimer = setTimeout(saveWindowStateNow, 250)
}

function saveWindowStateNow() {
  if (!mainWindow || mainWindow.isDestroyed()) return

  if (!mainWindow.isMaximized() && !mainWindow.isFullScreen()) {
    lastNormalBounds = mainWindow.getBounds()
  }

  const state = {
    bounds: lastNormalBounds || mainWindow.getBounds(),
    isMaximized: mainWindow.isMaximized(),
    isFullScreen: mainWindow.isFullScreen()
  }

  try {
    fs.mkdirSync(app.getPath("userData"), {recursive: true})
    fs.writeFileSync(windowStatePath(), JSON.stringify(state, null, 2))
  } catch (_error) {
    // Window state is a convenience; launch should never fail because of it.
  }
}

function showOfflineScreen(retryUrl = DEFAULT_GAME_URL, failure = {}) {
  const retryTarget = JSON.stringify(desktopUrl(retryUrl))
  const lobbyTarget = JSON.stringify(desktopUrl(DEFAULT_GAME_URL))
  const browserTarget = JSON.stringify(cleanShareUrl(retryUrl) || DEFAULT_GAME_URL)
  const retrySeconds = offlineRetrySeconds()
  const retryDelayMs = retrySeconds * 1000
  const retryDelayTarget = JSON.stringify(retryDelayMs)
  const failureSummary = JSON.stringify(offlineFailureSummary(failure))

  desktopConnectionWasOffline = true
  recordDesktopEvent({
    name: "desktop.offline",
    payload: {
      url: cleanShareUrl(retryUrl) || DEFAULT_GAME_URL,
      errorCode: failure.errorCode || "",
      errorDescription: failure.errorDescription || "",
      retrySeconds
    }
  })

  mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Mana Chess</title>
        <style>
          :root {
            color-scheme: dark;
            --bg: #111713;
            --panel: #172019;
            --panel-2: #1d281f;
            --line: #344032;
            --text: #f7f2e8;
            --muted: #b7c3b3;
            --gold: #e6bd68;
            --gold-text: #171207;
            --danger: #ef8a6b;
          }

          * {
            box-sizing: border-box;
          }

          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 24px;
            background: var(--bg);
            color: var(--text);
            font-family: Arial, Helvetica, sans-serif;
          }

          main {
            width: min(680px, 100%);
            display: grid;
            gap: 16px;
            padding: clamp(20px, 4vw, 32px);
            background: var(--panel);
            border: 1px solid var(--line);
            border-radius: 8px;
          }

          h1 {
            margin: 0;
            color: var(--gold);
            font-size: clamp(28px, 5vw, 40px);
            line-height: 1.05;
          }

          p {
            margin: 0;
            color: var(--muted);
            line-height: 1.45;
          }

          .eyebrow {
            margin: 0;
            color: var(--danger);
            font-size: 12px;
            font-weight: 900;
            letter-spacing: .08em;
            text-transform: uppercase;
          }

          .actions {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 10px;
          }

          .actions button:last-child:nth-child(odd) {
            grid-column: 1 / -1;
          }

          button {
            min-height: 42px;
            width: 100%;
            border: 1px solid transparent;
            border-radius: 8px;
            padding: 0 14px;
            background: var(--gold);
            color: var(--gold-text);
            cursor: pointer;
            font-weight: 900;
            font-size: 14px;
          }

          button.secondary {
            background: var(--panel-2);
            border-color: var(--line);
            color: var(--text);
          }

          button:disabled {
            cursor: default;
            opacity: .62;
          }

          .status {
            min-height: 20px;
            color: var(--gold);
            font-size: 13px;
          }

          .details {
            min-height: 18px;
            color: var(--muted);
            font-size: 12px;
            overflow-wrap: anywhere;
          }

          @media (max-width: 520px) {
            body {
              padding: 16px;
            }

            .actions {
              grid-template-columns: 1fr;
            }
          }
        </style>
      </head>
      <body>
        <main>
          <p class="eyebrow">Modo online no disponible</p>
          <h1>Mana Chess</h1>
          <p>No se pudo cargar el juego online. El launcher seguira intentando reconectar automaticamente.</p>
          <div class="actions">
            <button onclick="retryOnline()">Reintentar ahora</button>
            <button class="secondary" id="pauseButton" onclick="toggleAutoRetry()">Pausar reintentos</button>
            <button class="secondary" onclick="openInBrowser()">Abrir en navegador</button>
            <button class="secondary" onclick="goLobby()">Volver al lobby</button>
            <button class="secondary" onclick="copyLink()">Copiar link</button>
          </div>
          <p class="status" id="status" aria-live="polite"></p>
          <p class="details" id="details"></p>
        </main>
        <script>
          const retryTarget = ${retryTarget};
          const lobbyTarget = ${lobbyTarget};
          const browserTarget = ${browserTarget};
          const retryDelayMs = ${retryDelayTarget};
          const failureSummary = ${failureSummary};
          const status = document.getElementById("status");
          const details = document.getElementById("details");
          const pauseButton = document.getElementById("pauseButton");
          let retryTimer = null;
          let retryStartedAt = 0;
          let retryPaused = retryDelayMs <= 0;

          function retryOnline() {
            clearRetryTimer();
            status.textContent = "Reintentando conexion...";
            location.href = retryTarget;
          }

          function goLobby() {
            clearRetryTimer();
            location.href = lobbyTarget;
          }

          async function openInBrowser() {
            await window.ManaChessDesktop?.openShareLink(browserTarget);
          }

          async function copyLink() {
            const result = await window.ManaChessDesktop?.copyShareLink(browserTarget);
            status.textContent = result?.ok ? "Link copiado." : "No se pudo copiar el link.";
          }

          function toggleAutoRetry() {
            retryPaused = !retryPaused;
            pauseButton.textContent = retryPaused ? "Continuar reintentos" : "Pausar reintentos";

            if (retryPaused) {
              clearRetryTimer();
              status.textContent = "Reintentos automaticos pausados.";
              return;
            }

            startRetryTimer();
          }

          function startRetryTimer() {
            clearRetryTimer();

            if (retryDelayMs <= 0) {
              status.textContent = "Reintento automatico desactivado.";
              pauseButton.textContent = "Reintento desactivado";
              pauseButton.disabled = true;
              return;
            }

            retryStartedAt = Date.now();
            retryTimer = window.setInterval(updateRetryStatus, 250);
            updateRetryStatus();
          }

          function updateRetryStatus() {
            const remainingMs = Math.max(0, retryDelayMs - (Date.now() - retryStartedAt));
            const remainingSeconds = Math.ceil(remainingMs / 1000);
            status.textContent = remainingSeconds > 0
              ? "Reintentando en " + remainingSeconds + " s..."
              : "Reintentando conexion...";

            if (remainingMs <= 0) retryOnline();
          }

          function clearRetryTimer() {
            if (!retryTimer) return;
            window.clearInterval(retryTimer);
            retryTimer = null;
          }

          window.addEventListener("online", () => {
            status.textContent = "Conexion detectada. Reintentando...";
            retryOnline();
          });

          window.addEventListener("offline", () => {
            status.textContent = "Sin conexion local detectada.";
          });

          details.textContent = failureSummary;
          window.ManaChessDesktop?.sendEvent("desktop.offline_screen_viewed", {
            retryDelayMs,
            failureSummary,
            online: navigator.onLine
          });
          startRetryTimer();
        </script>
      </body>
    </html>
  `)}`)
}

function offlineFailureSummary(failure = {}) {
  const description = typeof failure.errorDescription === "string" ? failure.errorDescription.trim() : ""
  const code = Number.isFinite(failure.errorCode) ? failure.errorCode : ""

  if (description && code !== "") return `Fallo: ${description} (${code})`
  if (description) return `Fallo: ${description}`
  if (code !== "") return `Fallo de carga (${code})`
  return "Esperando conexion con el servidor de Mana Chess."
}

const gotLock = app.requestSingleInstanceLock()

if (!gotLock) {
  app.quit()
} else {
  app.on("second-instance", (_event, commandLine) => {
    const deepLink = findDeepLink(commandLine)
    if (deepLink) openDeepLink(deepLink)
    focusMainWindow()
  })

  app.whenReady().then(() => {
    Menu.setApplicationMenu(buildMenu())
    bindDesktopBridge()
    recordDesktopEvent({
      name: "desktop.session_started",
      payload: desktopSessionPayload()
    })
    createWindow()

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit()
})
