const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const steamRoot = path.join(desktopRoot, "steam")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")

function run(label, command, args, options = {}) {
  console.log(`\n== ${label} ==`)
  console.log(`> ${[command, ...args].join(" ")}`)
  execFileSync(command, args, {
    cwd: desktopRoot,
    stdio: "inherit",
    ...options
  })
}

function readRequired(relativePath) {
  const fullPath = path.join(desktopRoot, relativePath)
  if (!fs.existsSync(fullPath)) {
    throw new Error(`Missing ${relativePath}`)
  }

  return fs.readFileSync(fullPath, "utf8")
}

function assertIncludes(content, relativePath, expected) {
  if (!content.includes(expected)) {
    throw new Error(`${relativePath} must include ${expected}`)
  }
}

function validateSteamPipeTemplates() {
  console.log("\n== SteamPipe templates ==")

  const appBuildPath = path.join("steam", "app_build_steam_app.vdf.example")
  const depotPath = path.join("steam", "depot_build_windows.vdf.example")
  const gitignorePath = path.join("steam", ".gitignore")
  const readmePath = path.join("steam", "README.md")

  const appBuild = readRequired(appBuildPath)
  const depot = readRequired(depotPath)
  const gitignore = readRequired(gitignorePath)
  const readme = readRequired(readmePath)

  assertIncludes(appBuild, appBuildPath, "<STEAM_APP_ID>")
  assertIncludes(appBuild, appBuildPath, "<WINDOWS_DEPOT_ID>")
  assertIncludes(appBuild, appBuildPath, "..\\\\dist\\\\win-unpacked")
  assertIncludes(appBuild, appBuildPath, "depot_build_windows.vdf")
  assertIncludes(depot, depotPath, "<WINDOWS_DEPOT_ID>")
  assertIncludes(depot, depotPath, "\"LocalPath\" \"*\"")
  assertIncludes(depot, depotPath, "\"recursive\" \"1\"")
  assertIncludes(gitignore, gitignorePath, "*.vdf")
  assertIncludes(gitignore, gitignorePath, "!*.vdf.example")
  assertIncludes(gitignore, gitignorePath, "build-output/")
  assertIncludes(readme, readmePath, "Mana Chess.exe")
  assertIncludes(readme, readmePath, "steamcmd")

  const localVdfs = fs.readdirSync(steamRoot)
    .filter(name => name.endsWith(".vdf") && !name.endsWith(".vdf.example"))

  if (localVdfs.length > 0) {
    console.log(`Local ignored Steam VDF files present: ${localVdfs.join(", ")}`)
  }

  console.log("SteamPipe templates are present and keep real IDs outside git.")
}

function main() {
  if (process.platform !== "win32") {
    throw new Error("release:win:preflight only runs on Windows.")
  }

  validateSteamPipeTemplates()
  run("Windows installer and build verification", node, ["scripts/verify-win-installer.cjs"])

  if (!fs.existsSync(exePath)) {
    throw new Error(`Expected Windows executable at ${exePath}`)
  }

  run("Window mode smoke tests", node, ["scripts/smoke-win-app.cjs", "--all-modes"])
  run("Steam env smoke test", node, ["scripts/smoke-win-app.cjs", "--mode=windowed", "--steam-env"])
  run("Deep link smoke test", node, ["scripts/smoke-win-deep-link.cjs"])
  run("Desktop bridge smoke test", node, ["scripts/smoke-win-bridge.cjs"])
  run("Offline smoke test", node, ["scripts/smoke-win-offline.cjs"])
  console.log("\nWindows release preflight passed.")
}

main()
