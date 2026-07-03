const os = require("node:os")
const path = require("node:path")

function smokeUserDataDir(name) {
  const configuredPath = String(process.env.MANA_CHESS_SMOKE_USER_DATA_DIR || "").trim()
  if (configuredPath) return path.resolve(configuredPath)

  const safeName = String(name || "smoke").replace(/[^a-z0-9_-]/gi, "-").toLowerCase()
  return path.join(os.tmpdir(), "mana-chess-desktop-smoke", `${safeName}-${process.pid}`)
}

function desktopLogPath(userDataDir) {
  return path.join(userDataDir, "desktop-log.jsonl")
}

module.exports = {
  desktopLogPath,
  smokeUserDataDir
}
