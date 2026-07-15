const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")
const {prepareWinCodeSign} = require("./prepare-win-code-sign.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const electronBuilder = path.join(desktopRoot, "node_modules", "electron-builder", "cli.js")
const builderArgs = process.argv.slice(2)

if (!fs.existsSync(electronBuilder)) {
  throw new Error("electron-builder is not installed. Run npm ci first.")
}

if (builderArgs.length === 0) {
  throw new Error("Pass electron-builder arguments, for example --dir --win --x64.")
}

prepareWinCodeSign()

const env = {...process.env}
if (!env.CSC_IDENTITY_AUTO_DISCOVERY) {
  env.CSC_IDENTITY_AUTO_DISCOVERY = "false"
}

console.log(`> ${[process.execPath, electronBuilder, ...builderArgs].join(" ")}`)
console.log(`CSC identity auto-discovery: ${env.CSC_IDENTITY_AUTO_DISCOVERY}`)

execFileSync(process.execPath, [electronBuilder, ...builderArgs], {
  cwd: desktopRoot,
  env,
  stdio: "inherit"
})
