const crypto = require("node:crypto")
const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")
const {appBuilderPath} = require("app-builder-bin")
const {path7za} = require("7zip-bin")

const builderVersion = require("electron-builder/package.json").version
const artifacts = {
  "25.1.8": {
    version: "2.6.0",
    sha256: "cdaec7154dda7cc31f88d886e2489379a0625a737d610b5ae7f62a12f16743a4"
  }
}

function sha256File(filePath) {
  const hash = crypto.createHash("sha256")
  hash.update(fs.readFileSync(filePath))
  return hash.digest("hex")
}

function validPayload(targetPath) {
  return [
    path.join(targetPath, "rcedit-x64.exe"),
    path.join(targetPath, "windows-10", "x64", "signtool.exe")
  ].every(filePath => fs.existsSync(filePath) && fs.statSync(filePath).size > 0)
}

function electronBuilderCacheRoot() {
  if (process.env.ELECTRON_BUILDER_CACHE) {
    return path.resolve(process.env.ELECTRON_BUILDER_CACHE)
  }

  if (!process.env.LOCALAPPDATA) {
    throw new Error("LOCALAPPDATA is required to prepare the Windows electron-builder cache.")
  }

  return path.join(process.env.LOCALAPPDATA, "electron-builder", "Cache")
}

function prepareWinCodeSign() {
  if (process.platform !== "win32") return null

  const artifact = artifacts[builderVersion]
  if (!artifact) {
    throw new Error(
      `Unsupported electron-builder ${builderVersion}. Review the winCodeSign artifact mapping.`
    )
  }

  const name = `winCodeSign-${artifact.version}`
  const cacheParent = path.join(electronBuilderCacheRoot(), "winCodeSign")
  const targetPath = path.join(cacheParent, name)
  if (validPayload(targetPath)) return targetPath

  fs.mkdirSync(cacheParent, {recursive: true})
  const archivePath = path.join(cacheParent, `${name}.7z`)
  const url =
    `https://github.com/electron-userland/electron-builder-binaries/releases/download/${name}/${name}.7z`

  if (!fs.existsSync(archivePath) || sha256File(archivePath) !== artifact.sha256) {
    fs.rmSync(archivePath, {force: true})
    console.log(`Downloading ${name} from the electron-builder release...`)
    execFileSync(appBuilderPath, ["download", "--url", url, "--output", archivePath], {
      stdio: "inherit"
    })
  }

  const actualSha256 = sha256File(archivePath)
  if (actualSha256 !== artifact.sha256) {
    throw new Error(`Unexpected ${name} SHA256: ${actualSha256}`)
  }

  const temporaryPath = `${targetPath}.tmp-${process.pid}`
  fs.rmSync(temporaryPath, {recursive: true, force: true})

  try {
    execFileSync(
      path7za,
      [
        "x",
        archivePath,
        `-o${temporaryPath}`,
        "-y",
        "-bd",
        "-xr!darwin\\*",
        "-xr!linux\\*"
      ],
      {stdio: "inherit"}
    )

    if (!validPayload(temporaryPath)) {
      throw new Error(`${name} did not contain the expected Windows tools.`)
    }

    fs.rmSync(targetPath, {recursive: true, force: true})
    fs.renameSync(temporaryPath, targetPath)
  } finally {
    fs.rmSync(temporaryPath, {recursive: true, force: true})
  }

  console.log(`Prepared ${targetPath}`)
  return targetPath
}

module.exports = {prepareWinCodeSign}

if (require.main === module) {
  prepareWinCodeSign()
}
