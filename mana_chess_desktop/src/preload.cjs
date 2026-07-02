const {contextBridge, ipcRenderer} = require("electron")

const DESKTOP_EVENT_PAYLOAD_MAX_BYTES = 4096

const readArg = (name) => {
  const prefix = `--${name}=`
  const value = process.argv.find(arg => typeof arg === "string" && arg.startsWith(prefix))
  return value ? value.slice(prefix.length) : ""
}

const readBoolArg = (name) => readArg(name) === "1"

const readListArg = (name) => readArg(name).split(",").filter(Boolean)

const desktopInfo = Object.freeze({
  isDesktop: true,
  appName: "Mana Chess",
  version: readArg("mana-chess-version") || "0.2.0",
  channel: readArg("mana-chess-channel") || "desktop",
  origin: readArg("mana-chess-origin") || "",
  platform: process.platform,
  build: {
    commit: readArg("mana-chess-build-commit") || "dev",
    dirty: readArg("mana-chess-build-dirty") || "unknown",
    builtAt: readArg("mana-chess-build-time") || "",
    source: readArg("mana-chess-build-source") || "runtime"
  },
  steam: {
    detected: readBoolArg("mana-chess-steam-detected"),
    appId: readArg("mana-chess-steam-app-id") || "",
    gameId: readArg("mana-chess-steam-game-id") || "",
    overlayGameId: readArg("mana-chess-steam-overlay-game-id") || "",
    clientLaunch: readBoolArg("mana-chess-steam-client-launch"),
    steamEnv: readBoolArg("mana-chess-steam-env"),
    steamPath: readBoolArg("mana-chess-steam-path"),
    steamDeck: readBoolArg("mana-chess-steam-deck"),
    steamTenfoot: readBoolArg("mana-chess-steam-tenfoot"),
    presentKeys: readListArg("mana-chess-steam-present-keys")
  }
})

function cloneSerializable(value) {
  try {
    return JSON.parse(JSON.stringify(value || {}))
  } catch (_error) {
    return {}
  }
}

function normalizeEventPayload(payload) {
  const cloned = cloneSerializable(payload)
  const serialized = JSON.stringify(cloned)
  const bytes = Buffer.byteLength(serialized || "{}", "utf8")

  if (bytes <= DESKTOP_EVENT_PAYLOAD_MAX_BYTES) return cloned

  return {
    truncated: true,
    originalBytes: bytes,
    maxBytes: DESKTOP_EVENT_PAYLOAD_MAX_BYTES
  }
}

contextBridge.exposeInMainWorld("ManaChessDesktop", {
  getInfo: () => cloneSerializable(desktopInfo),
  getState: () => ipcRenderer.invoke("mana-chess:get-desktop-state"),
  getDiagnostics: () => ipcRenderer.invoke("mana-chess:get-desktop-diagnostics"),
  copyState: () => ipcRenderer.invoke("mana-chess:copy-desktop-state"),
  copyDiagnostics: () => ipcRenderer.invoke("mana-chess:copy-desktop-diagnostics"),
  openStateFolder: () => ipcRenderer.invoke("mana-chess:open-desktop-state-folder"),
  openLogFolder: () => ipcRenderer.invoke("mana-chess:open-desktop-log-folder"),
  resetState: () => ipcRenderer.invoke("mana-chess:reset-desktop-state"),
  copyShareLink: (url = "") => ipcRenderer.invoke("mana-chess:copy-share-link", String(url || "")),
  openShareLink: (url = "") => ipcRenderer.invoke("mana-chess:open-share-link", String(url || "")),
  copyDeepLink: (url = "") => ipcRenderer.invoke("mana-chess:copy-deep-link", String(url || "")),
  sendEvent: (name, payload = {}) => {
    if (typeof name !== "string" || name.trim().length === 0) return
    ipcRenderer.send("mana-chess:desktop-event", {
      name: name.trim().slice(0, 80),
      payload: normalizeEventPayload(payload)
    })
  }
})

window.addEventListener("DOMContentLoaded", () => {
  const {dataset} = document.documentElement
  dataset.desktop = "true"
  dataset.desktopChannel = desktopInfo.channel
  dataset.desktopVersion = desktopInfo.version
})
