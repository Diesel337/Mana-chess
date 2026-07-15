const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")
const {verifyWindowsExecutableResources} = require("./verify-win-executable-resources.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].join(" ")}`)
  execFileSync(command, args, {
    cwd: desktopRoot,
    stdio: "inherit",
    ...options
  })
}

run(node, ["scripts/check-syntax.cjs"])
run(node, ["scripts/write-build-info.cjs"])

run(node, ["scripts/run-electron-builder.cjs", "--dir", "--win", "--x64"])

if (!fs.existsSync(exePath)) {
  throw new Error(`Expected Windows executable at ${exePath}`)
}

verifyWindowsExecutableResources(exePath)
console.log(`Verified ${path.relative(desktopRoot, exePath)}`)
