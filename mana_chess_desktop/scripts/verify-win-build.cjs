const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const electronBuilder = path.join(desktopRoot, "node_modules", "electron-builder", "cli.js")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].join(" ")}`)
  execFileSync(command, args, {
    cwd: desktopRoot,
    stdio: "inherit",
    ...options
  })
}

run(node, ["--check", "src/main.cjs"])
run(node, ["--check", "src/preload.cjs"])
run(node, ["scripts/write-build-info.cjs"])

if (!fs.existsSync(electronBuilder)) {
  throw new Error("electron-builder is not installed. Run npm ci first.")
}

run(node, [electronBuilder, "--dir", "--win", "--x64"])

if (!fs.existsSync(exePath)) {
  throw new Error(`Expected Windows executable at ${exePath}`)
}

console.log(`Verified ${path.relative(desktopRoot, exePath)}`)
