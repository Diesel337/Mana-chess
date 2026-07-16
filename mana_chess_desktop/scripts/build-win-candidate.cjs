const fs = require("node:fs")
const path = require("node:path")
const {spawnSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const repoRoot = path.resolve(desktopRoot, "..")
const manifestPath = path.join(desktopRoot, "dist", "release-manifest.json")

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].join(" ")}`)
  const result = spawnSync(command, args, {
    cwd: options.cwd || desktopRoot,
    encoding: options.encoding,
    stdio: options.stdio || "inherit",
    windowsHide: true
  })

  if (result.error) throw result.error
  if (result.status !== 0) throw new Error(`${path.basename(command)} exited with status ${result.status}.`)
  return String(result.stdout || "").trim()
}

function gitOutput(args) {
  return run("git", args, {cwd: repoRoot, encoding: "utf8", stdio: "pipe"})
}

function requireCleanRepository(phase) {
  const status = gitOutput(["status", "--porcelain", "--untracked-files=all"])
  if (status) {
    throw new Error(`Refusing ${phase} with repository changes. Commit or remove them first.`)
  }
}

function verifyManifest(expectedCommit) {
  if (!fs.existsSync(manifestPath)) {
    throw new Error("Windows candidate did not produce dist/release-manifest.json.")
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"))
  const buildCommit = String(manifest?.build?.commit || "").trim()
  const dirty = String(manifest?.build?.dirty || "").trim()

  if (buildCommit.length < 7 || !expectedCommit.startsWith(buildCommit)) {
    throw new Error(`Candidate commit ${buildCommit || "missing"} does not match ${expectedCommit.slice(0, 12)}.`)
  }
  if (dirty !== "false") {
    throw new Error(`Candidate build must record dirty=false, received ${dirty || "missing"}.`)
  }

  return manifest
}

function main() {
  if (process.platform !== "win32") throw new Error("Windows candidate builds only run on Windows.")

  requireCleanRepository("a release candidate build")
  const commit = gitOutput(["rev-parse", "HEAD"])
  const branch = gitOutput(["branch", "--show-current"]) || "detached"

  console.log(`Building clean Mana Chess candidate from ${branch} ${commit.slice(0, 12)}.`)
  run(process.execPath, ["scripts/release-preflight-win.cjs"])
  const manifest = verifyManifest(commit)
  requireCleanRepository("candidate completion")

  console.log(
    `Windows candidate ready: Mana Chess ${manifest.version}, commit ${manifest.build.commit}, dirty=${manifest.build.dirty}.`
  )
}

try {
  main()
} catch (error) {
  console.error(`Windows candidate failed: ${error.message}`)
  process.exitCode = 1
}
