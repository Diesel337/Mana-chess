const {app, BrowserWindow, Menu, screen, shell} = require("electron")

const GAME_URL = desktopUrl(process.env.MANA_CHESS_URL || "https://control-piezas-production-59aa.up.railway.app/")

let mainWindow = null

function createWindow() {
  const {width, height} = screen.getPrimaryDisplay().workAreaSize

  mainWindow = new BrowserWindow({
    width: Math.min(width, 1440),
    height: Math.min(height, 960),
    minWidth: 1024,
    minHeight: 720,
    title: "Mana Chess",
    backgroundColor: "#111713",
    autoHideMenuBar: true,
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
    if (url.startsWith(GAME_URL)) {
      return {action: "allow"}
    }

    shell.openExternal(url)
    return {action: "deny"}
  })

  mainWindow.webContents.on("did-fail-load", (_event, _errorCode, _errorDescription, validatedURL) => {
    if (validatedURL !== GAME_URL) return
    showOfflineScreen()
  })
}

function desktopUrl(url) {
  const parsed = new URL(url)
  parsed.searchParams.set("desktop", "1")
  return parsed.toString()
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
    Menu.setApplicationMenu(null)
    createWindow()

    app.on("activate", () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
}

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit()
})
