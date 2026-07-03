const fs = require("node:fs")
const path = require("node:path")
const crypto = require("node:crypto")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const packageJson = JSON.parse(fs.readFileSync(path.join(desktopRoot, "package.json"), "utf8"))
const electronBuilder = path.join(desktopRoot, "node_modules", "electron-builder", "cli.js")
const buildInfoPath = path.join(desktopRoot, "src", "build-info.generated.json")
const iconPngPath = path.join(desktopRoot, "build", "icon.png")
const iconIcoPath = path.join(desktopRoot, "build", "icon.ico")
const exePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const installerPath = path.join(desktopRoot, "dist", `Mana Chess Setup ${packageJson.version}.exe`)
const latestYmlPath = path.join(desktopRoot, "dist", "latest.yml")
const blockMapPath = `${installerPath}.blockmap`
const manifestPath = path.join(desktopRoot, "dist", "release-manifest.json")
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

function relativePath(pathToFormat) {
  return path.relative(desktopRoot, pathToFormat).replace(/\\/g, "/")
}

function sha256File(pathToHash) {
  const hash = crypto.createHash("sha256")
  const buffer = Buffer.alloc(1024 * 1024)
  const file = fs.openSync(pathToHash, "r")

  try {
    let bytesRead = 0
    do {
      bytesRead = fs.readSync(file, buffer, 0, buffer.length, null)
      if (bytesRead > 0) hash.update(buffer.subarray(0, bytesRead))
    } while (bytesRead > 0)
  } finally {
    fs.closeSync(file)
  }

  return hash.digest("hex")
}

function artifactInfo(label, pathToArtifact) {
  const stat = assertFile(pathToArtifact, label)
  return {
    label,
    path: relativePath(pathToArtifact),
    bytes: stat.size,
    sha256: sha256File(pathToArtifact)
  }
}

function readBuildInfo() {
  try {
    return JSON.parse(fs.readFileSync(buildInfoPath, "utf8"))
  } catch (_error) {
    return {}
  }
}

function writeReleaseManifest(artifacts) {
  const build = readBuildInfo()
  const manifest = {
    schemaVersion: 1,
    productName: packageJson.productName || "Mana Chess",
    version: packageJson.version,
    appId: packageJson.build?.appId || "",
    generatedAt: new Date().toISOString(),
    build,
    artifacts
  }

  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`)
  return manifest
}

function validateIconAssets() {
  if (packageJson.build?.win?.icon !== "build/icon.ico") {
    throw new Error("package.json build.win.icon must point to build/icon.ico")
  }

  if (!Array.isArray(packageJson.build?.files) || !packageJson.build.files.includes("build/icon.png")) {
    throw new Error("package.json build.files must include build/icon.png")
  }

  const png = fs.readFileSync(iconPngPath)
  const pngSignature = png.subarray(0, 8).toString("hex")
  if (pngSignature !== "89504e470d0a1a0a") {
    throw new Error("build/icon.png is not a PNG file.")
  }

  const pngWidth = png.readUInt32BE(16)
  const pngHeight = png.readUInt32BE(20)
  if (pngWidth !== 256 || pngHeight !== 256) {
    throw new Error(`build/icon.png must be 256x256, found ${pngWidth}x${pngHeight}.`)
  }

  const ico = fs.readFileSync(iconIcoPath)
  if (ico.length < 22 || ico.readUInt16LE(0) !== 0 || ico.readUInt16LE(2) !== 1) {
    throw new Error("build/icon.ico is not a valid ICO file.")
  }

  const icoCount = ico.readUInt16LE(4)
  const icoEntries = []
  for (let index = 0; index < icoCount; index += 1) {
    const offset = 6 + index * 16
    if (offset + 15 >= ico.length) {
      throw new Error("build/icon.ico has a truncated icon directory.")
    }

    icoEntries.push({
      width: ico[offset] || 256,
      height: ico[offset + 1] || 256,
      bytes: ico.readUInt32LE(offset + 8)
    })
  }

  const hasLargeIcon = icoEntries.some(entry => entry.width >= 256 && entry.height >= 256 && entry.bytes > 0)
  if (!hasLargeIcon) {
    throw new Error("build/icon.ico must include a 256x256 icon entry.")
  }
}

validateIconAssets()
run(node, ["scripts/check-syntax.cjs"])
run(node, ["scripts/write-build-info.cjs"])

if (!fs.existsSync(electronBuilder)) {
  throw new Error("electron-builder is not installed. Run npm ci first.")
}

run(node, [electronBuilder, "--win", "nsis", "--x64"])

const artifacts = [
  artifactInfo("desktop-icon-png", iconPngPath),
  artifactInfo("desktop-icon-ico", iconIcoPath),
  artifactInfo("unpacked-windows-executable", exePath),
  artifactInfo("windows-installer", installerPath),
  artifactInfo("installer-update-metadata", latestYmlPath),
  artifactInfo("installer-block-map", blockMapPath)
]

const installer = artifacts.find(artifact => artifact.label === "windows-installer")

if (installer.bytes < minInstallerBytes) {
  throw new Error(`Installer looks too small: ${installer.bytes} bytes`)
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

const manifest = writeReleaseManifest(artifacts)

for (const artifact of manifest.artifacts) {
  const megabytes = Math.round(artifact.bytes / 1024 / 1024)
  const size = megabytes > 0 ? `${megabytes} MB` : `${artifact.bytes} bytes`
  console.log(`Verified ${artifact.path} (${size}) sha256=${artifact.sha256}`)
}

console.log(`Wrote ${relativePath(manifestPath)}`)
