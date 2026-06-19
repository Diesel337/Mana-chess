const path = require("node:path")
const {app, BrowserWindow, Menu, screen, shell} = require("electron")

const DEFAULT_GAME_URL = process.env.MANA_CHESS_URL || "https://mana-chess-production.up.railway.app/"
const GAME_URL = desktopUrl(DEFAULT_GAME_URL)
const GAME_ORIGIN = new URL(GAME_URL).origin

let mainWindow = null

function createWindow() {
  const {width, height} = screen.getPrimaryDisplay().workAreaSize

  mainWindow = new BrowserWindow({
    width: Math.min(width, 1440),
    height: Math.min(height, 960),
    minWidth: 1024,
    minHeight: 720,
    title: "Mana Chess",
    icon: path.join(__dirname, "../build/icon.png"),
    backgroundColor: "#111713",
    autoHideMenuBar: true,
    fullscreenable: true,
    webPreferences: {
      preload: `${__dirname}/preload.cjs`,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  })

  mainWindow.loadURL(GAME_URL)
  mainWindow.maximize()

  mainWindow.webContents.setWindowOpenHandler(({url}) => {
    const parsed = safeUrl(url)
    if (!parsed) return {action: "deny"}

    if (parsed.origin === GAME_ORIGIN) {
      mainWindow.loadURL(desktopUrl(url))
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
    if (parsed.origin === GAME_ORIGIN) return

    event.preventDefault()
    shell.openExternal(url)
  })

  mainWindow.webContents.on("page-title-updated", event => {
    event.preventDefault()
    mainWindow.setTitle("Mana Chess")
  })

  mainWindow.webContents.on("did-fail-load", (_event, _errorCode, _errorDescription, validatedURL) => {
    if (validatedURL !== GAME_URL) return
    showOfflineScreen()
  })
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

function navigateHome() {
  if (!mainWindow) return
  mainWindow.loadURL(GAME_URL)
}

function toggleFullscreen() {
  if (!mainWindow) return
  mainWindow.setFullScreen(!mainWindow.isFullScreen())
}

function desktopUrl(url) {
  const parsed = new URL(url)
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

function showOfflineScreen() {
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
          <button onclick="location.href='${GAME_URL}'">Reintentar</button>
        </main>
      </body>
    </html>
  `)}`)
}

const gotLock = app.requestSingleInstanceLock()

if (!gotLock) {
  app.quit()
} else {
  app.on("second-instance", () => {
    if (!mainWindow) return
    if (mainWindow.isMinimized()) mainWindow.restore()
    mainWindow.focus()
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
