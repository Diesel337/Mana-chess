const fs = require("node:fs")
const path = require("node:path")
const {app, BrowserWindow, Menu, clipboard, ipcMain, screen, shell} = require("electron")

const DEFAULT_GAME_URL = process.env.MANA_CHESS_URL || "https://mana-chess-production.up.railway.app/"
const GAME_ORIGIN = new URL(DEFAULT_GAME_URL).origin
const PROTOCOL_SCHEME = "manachess"
const DESKTOP_CHANNEL = process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop"
const WINDOW_STATE_FILE = "window-state.json"
const DESKTOP_STATE_FILE = "desktop-state.json"
const EVENT_LOG_LIMIT = 40
const MIN_WINDOW_WIDTH = 1024
const MIN_WINDOW_HEIGHT = 720
const DEFAULT_WINDOW_WIDTH = 1440
const DEFAULT_WINDOW_HEIGHT = 960

let mainWindow = null
let pendingGameUrl = gameUrlFromDeepLink(findDeepLink(process.argv))
let saveWindowStateTimer = null
let lastNormalBounds = null

app.setAppUserModelId("com.diesel337.manachess")
registerProtocol()

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
        `--mana-chess-origin=${GAME_ORIGIN}`
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

  const initialUrl = pendingGameUrl || DEFAULT_GAME_URL
  pendingGameUrl = null
  loadGameUrl(initialUrl)
}

function bindDesktopBridge() {
  ipcMain.handle("mana-chess:copy-share-link", (_event, url) => {
    const shareUrl = cleanShareUrl(url) || cleanShareUrl(mainWindow?.webContents.getURL()) || DEFAULT_GAME_URL
    clipboard.writeText(shareUrl)
    return {ok: true, url: shareUrl}
  })

  ipcMain.handle("mana-chess:open-share-link", (_event, url) => {
    const shareUrl = cleanShareUrl(url) || cleanShareUrl(mainWindow?.webContents.getURL()) || DEFAULT_GAME_URL
    shell.openExternal(shareUrl)
    return {ok: true, url: shareUrl}
  })

  ipcMain.handle("mana-chess:copy-deep-link", (_event, url) => copyDeepLinkForUrl(url || mainWindow?.webContents.getURL()))

  ipcMain.handle("mana-chess:get-desktop-state", () => readDesktopState())

  ipcMain.handle("mana-chess:copy-desktop-state", () => copyDesktopState())

  ipcMain.handle("mana-chess:open-desktop-state-folder", () => openDesktopStateFolder())

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
              label: "Abrir datos desktop",
              click: () => openDesktopStateFolder()
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

    shell.openExternal(url)
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
    shell.openExternal(url)
  })

  mainWindow.webContents.on("page-title-updated", event => {
    event.preventDefault()
    applyDesktopPresence(readDesktopState().presence)
  })

  mainWindow.webContents.on("did-fail-load", (_event, _errorCode, _errorDescription, validatedURL, isMainFrame) => {
    if (!isMainFrame) return

    const parsed = safeUrl(validatedURL)
    if (parsed?.origin !== GAME_ORIGIN) return

    showOfflineScreen(validatedURL)
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

  loadGameUrl(targetUrl)
  focusMainWindow()
  return true
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
  shell.openExternal(currentShareUrl())
}

function desktopStatePath() {
  return path.join(app.getPath("userData"), DESKTOP_STATE_FILE)
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
    fs.mkdirSync(app.getPath("userData"), {recursive: true})
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

async function openDesktopStateFolder() {
  try {
    const dataPath = app.getPath("userData")
    fs.mkdirSync(dataPath, {recursive: true})
    const error = await shell.openPath(dataPath)
    return {ok: !error, path: dataPath, error}
  } catch (error) {
    return {ok: false, error: String(error?.message || error)}
  }
}

function resetDesktopState() {
  writeDesktopState(normalizeDesktopState({}))
  return recordDesktopEvent({
    name: "desktop.session_started",
    payload: {version: app.getVersion(), channel: DESKTOP_CHANNEL, reset: true}
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

  const state = updateDesktopState(readDesktopState(), normalizedEvent)
  writeDesktopState(state)
  applyDesktopPresence(state.presence)
  return state
}

function normalizeDesktopEvent(event) {
  if (!event || typeof event.name !== "string") return null

  const name = event.name.trim().slice(0, 80)
  if (!name) return null

  return {
    name,
    payload: cloneJson(event.payload),
    at: new Date().toISOString()
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

function cleanShareUrl(url) {
  const parsed = safeUrl(String(url || ""))
  if (!parsed || parsed.origin !== GAME_ORIGIN) return null
  parsed.searchParams.delete("desktop")
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
  return parsed.toString()
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
    return boundsAreVisible(normalizedState.bounds) ? normalizedState : defaultState
  } catch (_error) {
    return defaultState
  }
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

function showOfflineScreen(retryUrl = DEFAULT_GAME_URL) {
  const retryTarget = JSON.stringify(desktopUrl(retryUrl))
  const lobbyTarget = JSON.stringify(desktopUrl(DEFAULT_GAME_URL))
  const browserTarget = JSON.stringify(cleanShareUrl(retryUrl) || DEFAULT_GAME_URL)

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
            width: min(620px, 100%);
            display: grid;
            gap: 18px;
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

          .actions {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 10px;
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

          .status {
            min-height: 20px;
            color: var(--gold);
            font-size: 13px;
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
          <h1>Mana Chess</h1>
          <p>No se pudo cargar el juego online. Revisa tu conexion a internet o intenta de nuevo.</p>
          <div class="actions">
            <button onclick="retryOnline()">Reintentar</button>
            <button class="secondary" onclick="openInBrowser()">Abrir en navegador</button>
            <button class="secondary" onclick="goLobby()">Volver al lobby</button>
            <button class="secondary" onclick="copyLink()">Copiar link</button>
          </div>
          <p class="status" id="status" aria-live="polite"></p>
        </main>
        <script>
          const retryTarget = ${retryTarget};
          const lobbyTarget = ${lobbyTarget};
          const browserTarget = ${browserTarget};
          const status = document.getElementById("status");

          function retryOnline() {
            location.href = retryTarget;
          }

          function goLobby() {
            location.href = lobbyTarget;
          }

          async function openInBrowser() {
            await window.ManaChessDesktop?.openShareLink(browserTarget);
          }

          async function copyLink() {
            const result = await window.ManaChessDesktop?.copyShareLink(browserTarget);
            status.textContent = result?.ok ? "Link copiado." : "No se pudo copiar el link.";
          }
        </script>
      </body>
    </html>
  `)}`)
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
    recordDesktopEvent({name: "desktop.session_started", payload: {version: app.getVersion(), channel: DESKTOP_CHANNEL}})
    createWindow()

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit()
})
