const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const repoRoot = path.resolve(desktopRoot, "..")
const packagePath = path.join(desktopRoot, "package.json")
const outputPath = path.join(desktopRoot, "src", "build-info.generated.json")
const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"))

function git(args, fallback = "") {
  try {
    return execFileSync("git", args, {
      cwd: repoRoot,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim()
  } catch (_error) {
    return fallback
  }
}

function buildTime() {
  if (process.env.MANA_CHESS_BUILD_TIME) return process.env.MANA_CHESS_BUILD_TIME

  const epoch = Number(process.env.SOURCE_DATE_EPOCH || "")
  if (Number.isFinite(epoch) && epoch > 0) return new Date(epoch * 1000).toISOString()

  return ""
}

const status = git(["status", "--short"], "")
const info = {
  version: pkg.version,
  channel: process.env.MANA_CHESS_DESKTOP_CHANNEL || "desktop",
  commit: process.env.MANA_CHESS_BUILD_COMMIT || git(["rev-parse", "--short=12", "HEAD"], "unknown"),
  dirty: process.env.MANA_CHESS_BUILD_DIRTY || (status ? "true" : "false"),
  builtAt: buildTime(),
  source: "generated"
}

fs.writeFileSync(outputPath, `${JSON.stringify(info, null, 2)}\n`)
console.log(`Wrote ${path.relative(desktopRoot, outputPath)} ${info.version} ${info.commit}`)
