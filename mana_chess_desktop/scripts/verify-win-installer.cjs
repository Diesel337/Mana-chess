const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const packageJson = JSON.parse(fs.readFileSync(path.join(desktopRoot, "package.json"), "utf8"))
const electronBuilder = path.join(desktopRoot, "node_modules", "electron-builder", "cli.js")
const installerPath = path.join(desktopRoot, "dist", `Mana Chess Setup ${packageJson.version}.exe`)
const latestYmlPath = path.join(desktopRoot, "dist", "latest.yml")
const blockMapPath = `${installerPath}.blockmap`
const minInstallerBytes = 50 * 1024 * 1024

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].join(" ")}`)
  execFileSync(command, args, {
    cwd: desktopRoot,
    stdio: "inherit",
    ...options
  })
}

function assertFile(pathToCheck, label) {
  if (!fs.existsSync(pathToCheck)) {
    throw new Error(`Expected ${label} at ${pathToCheck}`)
  }

  return fs.statSync(pathToCheck)
}

run(node, ["--check", "src/main.cjs"])
run(node, ["--check", "src/preload.cjs"])
run(node, ["scripts/write-build-info.cjs"])

if (!fs.existsSync(electronBuilder)) {
  throw new Error("electron-builder is not installed. Run npm ci first.")
}

run(node, [electronBuilder, "--win", "nsis", "--x64"])

const installerStat = assertFile(installerPath, "Windows installer")
assertFile(latestYmlPath, "installer update metadata")
assertFile(blockMapPath, "installer block map")

if (installerStat.size < minInstallerBytes) {
  throw new Error(`Installer looks too small: ${installerStat.size} bytes`)
}

const header = Buffer.alloc(2)
const installerFd = fs.openSync(installerPath, "r")
try {
  fs.readSync(installerFd, header, 0, header.length, 0)
} finally {
  fs.closeSync(installerFd)
}

if (header.toString("ascii") !== "MZ") {
  throw new Error("Installer does not have a Windows executable MZ header.")
}

console.log(`Verified ${path.relative(desktopRoot, installerPath)} (${Math.round(installerStat.size / 1024 / 1024)} MB)`)
