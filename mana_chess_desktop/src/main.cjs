const fs = require("node:fs")
const path = require("node:path")
const {app, BrowserWindow, Menu, clipboard, screen, shell} = require("electron")

const DEFAULT_GAME_URL = process.env.MANA_CHESS_URL || "https://mana-chess-production.up.railway.app/"
const GAME_ORIGIN = new URL(DEFAULT_GAME_URL).origin
const PROTOCOL_SCHEME = "manachess"
const WINDOW_STATE_FILE = "window-state.json"
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
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  bindWindowState(windowState)
  bindNavigationGuards()
  bindShortcuts()

  mainWindow.once("ready-to-show", () => {
    if (windowState.isMaximized) mainWindow.maximize()
    if (windowState.isFullScreen) mainWindow.setFullScreen(true)
    mainWindow.show()
  })

  const initialUrl = pendingGameUrl || DEFAULT_GAME_URL
  pendingGameUrl = null
  loadGameUrl(initialUrl)
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
          label: "Abrir version web",
          click: () => shell.openExternal(DEFAULT_GAME_URL)
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
    mainWindow.setTitle("Mana Chess")
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

function copyCurrentLink() {
  if (!mainWindow) return

  const currentUrl = safeUrl(mainWindow.webContents.getURL())
  if (!currentUrl || currentUrl.origin !== GAME_ORIGIN) {
    clipboard.writeText(DEFAULT_GAME_URL)
    return
  }

  currentUrl.searchParams.delete("desktop")
  clipboard.writeText(currentUrl.toString())
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

  mainWindow.loadURL(`data:text/html;charset=utf-8,${encodeURIComponent(`
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Mana Chess</title>
        <style>
          body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            background: #111713;
            color: #f7f2e8;
            font-family: Arial, sans-serif;
          }

          main {
            width: min(520px, calc(100vw - 32px));
            display: grid;
            gap: 16px;
            padding: 24px;
            background: #172019;
            border: 1px solid #344032;
            border-radius: 8px;
          }

          h1 {
            margin: 0;
            color: #e6bd68;
          }

          p {
            margin: 0;
            color: #b7c3b3;
            line-height: 1.45;
          }

          button {
            min-height: 42px;
            border: 0;
            border-radius: 8px;
            background: #e6bd68;
            color: #171207;
            cursor: pointer;
            font-weight: 900;
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Mana Chess</h1>
          <p>No se pudo cargar el juego online. Revisa tu conexion a internet o intenta de nuevo.</p>
          <button onclick='location.href=${retryTarget}'>Reintentar</button>
        </main>
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
    createWindow()

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit()
})
