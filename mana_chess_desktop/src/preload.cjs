const {contextBridge, ipcRenderer} = require("electron")

const readArg = (name) => {
  const prefix = `--${name}=`
  const value = process.argv.find(arg => typeof arg === "string" && arg.startsWith(prefix))
  return value ? value.slice(prefix.length) : ""
}

const desktopInfo = Object.freeze({
  isDesktop: true,
  appName: "Mana Chess",
  version: readArg("mana-chess-version") || "0.2.0",
  channel: readArg("mana-chess-channel") || "desktop",
  origin: readArg("mana-chess-origin") || "",
  platform: process.platform
})

function clonePayload(payload) {
  try {
    return JSON.parse(JSON.stringify(payload || {}))
  } catch (_error) {
    return {}
  }
}

contextBridge.exposeInMainWorld("ManaChessDesktop", {
  getInfo: () => ({...desktopInfo}),
  getState: () => ipcRenderer.invoke("mana-chess:get-desktop-state"),
  copyState: () => ipcRenderer.invoke("mana-chess:copy-desktop-state"),
  openStateFolder: () => ipcRenderer.invoke("mana-chess:open-desktop-state-folder"),
  resetState: () => ipcRenderer.invoke("mana-chess:reset-desktop-state"),
  copyShareLink: (url = "") => ipcRenderer.invoke("mana-chess:copy-share-link", String(url || "")),
  openShareLink: (url = "") => ipcRenderer.invoke("mana-chess:open-share-link", String(url || "")),
  copyDeepLink: (url = "") => ipcRenderer.invoke("mana-chess:copy-deep-link", String(url || "")),
  sendEvent: (name, payload = {}) => {
    if (typeof name !== "string" || name.trim().length === 0) return
    ipcRenderer.send("mana-chess:desktop-event", {
      name: name.trim().slice(0, 80),
      payload: clonePayload(payload)
    })
  }
})

window.addEventListener("DOMContentLoaded", () => {
  const {dataset} = document.documentElement
  dataset.desktop = "true"
  dataset.desktopChannel = desktopInfo.channel
  dataset.desktopVersion = desktopInfo.version
})
