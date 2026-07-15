const crypto = require("node:crypto")
const fs = require("node:fs")
const path = require("node:path")
const {verifyWindowsExecutableResources} = require("./verify-win-executable-resources.cjs")
const {verifyWindowsSignatures} = require("./verify-win-signatures.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const packageJson = require(path.join(desktopRoot, "package.json"))
const payloadRoot = path.join(desktopRoot, "dist", "win-unpacked")
const defaultOutputDir = path.join(desktopRoot, "steam")
const defaultManifestPath = path.join(desktopRoot, "dist", "steam-depot-manifest.json")
const requiredPayloadFiles = [
  "Mana Chess.exe",
  "resources/app.asar",
  "resources/app.asar.unpacked/node_modules/steamworks.js/dist/win64/steam_api64.dll",
  "resources/app.asar.unpacked/node_modules/steamworks.js/dist/win64/steamworksjs.win32-x64-msvc.node"
]
const qaStateFiles = new Set([
  "desktop-log.jsonl",
  "desktop-state.json",
  "window-state.json"
])
const exclusions = [
  {
    vdf: "*.pdb",
    matches: relativePath => relativePath.toLowerCase().endsWith(".pdb")
  },
  {
    vdf: "*.log",
    matches: relativePath => relativePath.toLowerCase().endsWith(".log")
  },
  {
    vdf: "resources\\app-update.yml",
    matches: relativePath => relativePath.toLowerCase() === "resources/app-update.yml"
  },
  {
    vdf: "resources\\elevate.exe",
    matches: relativePath => relativePath.toLowerCase() === "resources/elevate.exe"
  }
]

function usage() {
  return [
    "Prepare the Mana Chess Windows SteamPipe build:",
    "",
    "  node scripts/prepare-steam-build.cjs [options]",
    "",
    "Options:",
    "  --verify                 Validate the payload without writing generated files.",
    "  --upload                 Generate an upload VDF. Preview is the safe default.",
    "  --app-id <id>            Steamworks app ID.",
    "  --depot-id <id>          Steamworks Windows depot ID.",
    "  --description <text>     Steam build description.",
    "  --set-live <branch>      Set an upload live on a non-default branch.",
    "  --output-dir <path>      Generated VDF directory (default: steam).",
    "  --manifest-path <path>   Depot manifest path (default: dist).",
    "  --help                   Show this help.",
    "",
    "Environment alternatives:",
    "  MANA_CHESS_STEAM_APP_ID / STEAM_APP_ID",
    "  MANA_CHESS_STEAM_DEPOT_ID / STEAM_WINDOWS_DEPOT_ID",
    "  MANA_CHESS_STEAM_BUILD_DESCRIPTION",
    "  MANA_CHESS_STEAM_SET_LIVE"
  ].join("\n")
}

function parseArgs(argv) {
  const result = {
    verify: false,
    upload: false,
    help: false,
    values: {}
  }
  const flags = new Map([
    ["--verify", "verify"],
    ["--upload", "upload"],
    ["--help", "help"]
  ])
  const valueOptions = new Map([
    ["--app-id", "appId"],
    ["--depot-id", "depotId"],
    ["--description", "description"],
    ["--set-live", "setLive"],
    ["--output-dir", "outputDir"],
    ["--manifest-path", "manifestPath"]
  ])

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]

    if (flags.has(argument)) {
      result[flags.get(argument)] = true
      continue
    }

    const equalsIndex = argument.indexOf("=")
    const option = equalsIndex === -1 ? argument : argument.slice(0, equalsIndex)
    if (!valueOptions.has(option)) {
      throw new Error("Unknown option " + JSON.stringify(argument) + ". Use --help for usage.")
    }

    let value
    if (equalsIndex !== -1) {
      value = argument.slice(equalsIndex + 1)
    } else {
      index += 1
      value = argv[index]
    }

    if (value === undefined || value.startsWith("--")) {
      throw new Error("Missing value for " + option + ".")
    }

    result.values[valueOptions.get(option)] = value
  }

  return result
}

function firstValue(...values) {
  return values.find(value => value !== undefined && String(value).trim() !== "")
}

function validateSteamId(value, label) {
  const normalized = String(value || "").trim()
  if (!/^[1-9]\d*$/.test(normalized)) {
    throw new Error(
      label + " must be a positive numeric Steamworks ID. " +
        "Provide it by CLI or environment; placeholders are not accepted."
    )
  }
  return normalized
}

function validateDescription(value) {
  const normalized = String(value || "").trim()
  if (!normalized || normalized.length > 120 || /[\x00-\x1f"\\]/.test(normalized)) {
    throw new Error(
      "Steam build description must be 1-120 characters without quotes, backslashes, or controls."
    )
  }
  return normalized
}

function validateSetLive(value, mode) {
  const normalized = String(value || "").trim()
  if (!normalized) {
    return ""
  }
  if (mode === "preview") {
    throw new Error("--set-live is not allowed in preview mode.")
  }
  if (normalized.toLowerCase() === "default") {
    throw new Error("Steam's default branch must be assigned manually; --set-live=default is rejected.")
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(normalized)) {
    throw new Error("Steam branch must use 1-64 letters, numbers, dots, underscores, or hyphens.")
  }
  return normalized
}

function isInside(parentPath, childPath) {
  const relative = path.relative(parentPath, childPath)
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))
}

function assertGeneratedPathsAreOutsidePayload(outputDir, manifestPath) {
  if (isInside(payloadRoot, outputDir)) {
    throw new Error("Steam VDF output directory cannot be inside the depot payload.")
  }
  if (isInside(payloadRoot, manifestPath)) {
    throw new Error("Steam depot manifest cannot be written inside the depot payload.")
  }
  const generatedVdfs = [
    path.join(outputDir, "app_build_steam_app.vdf"),
    path.join(outputDir, "depot_build_windows.vdf")
  ]
  if (generatedVdfs.some(vdfPath => path.resolve(vdfPath) === path.resolve(manifestPath))) {
    throw new Error("Steam depot manifest path cannot replace a generated VDF.")
  }
}

function vdfPath(fromDir, targetPath) {
  let relative = path.relative(fromDir, targetPath)
  if (!relative) {
    relative = "."
  } else if (!relative.startsWith(".")) {
    relative = "." + path.sep + relative
  }
  return relative.replace(/\\/g, "\\\\").replace(/\//g, "\\\\")
}

function renderAppBuild(config) {
  const previewLine = config.mode === "preview" ? '  "Preview" "1"\n' : ""
  return [
    '"AppBuild"',
    "{",
    '  "AppID" "' + config.appId + '"',
    '  "Desc" "' + config.description + '"',
    '  "BuildOutput" "' + vdfPath(config.outputDir, path.join(config.outputDir, "build-output")) + '"',
    '  "ContentRoot" "' + vdfPath(config.outputDir, payloadRoot) + '"',
    previewLine.trimEnd(),
    '  "SetLive" "' + config.setLive + '"',
    "",
    '  "Depots"',
    "  {",
    '    "' + config.depotId + '" "depot_build_windows.vdf"',
    "  }",
    "}",
    ""
  ].filter((line, index, lines) => line !== "" || lines[index - 1] !== "").join("\n")
}

function renderDepotBuild(config) {
  const exclusionLines = exclusions.map(
    exclusion => '  "FileExclusion" "' + exclusion.vdf.replace(/\\/g, "\\\\") + '"'
  )
  return [
    '"DepotBuild"',
    "{",
    '  "DepotID" "' + config.depotId + '"',
    "",
    '  "FileMapping"',
    "  {",
    '    "LocalPath" "*"',
    '    "DepotPath" "."',
    '    "recursive" "1"',
    "  }",
    "",
    ...exclusionLines,
    "}",
    ""
  ].join("\n")
}

function normalizedRelativePath(fullPath) {
  return path.relative(payloadRoot, fullPath).replace(/\\/g, "/")
}

function collectPayloadCandidates(directory = payloadRoot, candidates = []) {
  for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
    const fullPath = path.join(directory, entry.name)
    const stat = fs.lstatSync(fullPath)
    const relativePath = normalizedRelativePath(fullPath)

    if (stat.isSymbolicLink()) {
      throw new Error("Steam depot payload cannot contain symbolic links: " + relativePath)
    }

    if (stat.isDirectory()) {
      collectPayloadCandidates(fullPath, candidates)
      continue
    }

    if (!stat.isFile()) {
      throw new Error("Unsupported Steam depot payload entry: " + relativePath)
    }

    if (qaStateFiles.has(entry.name.toLowerCase())) {
      throw new Error("QA state must not ship in the Steam depot: " + relativePath)
    }

    if (!exclusions.some(exclusion => exclusion.matches(relativePath))) {
      candidates.push({
        fullPath,
        path: relativePath,
        size: stat.size
      })
    }
  }

  return candidates
}

function hashFile(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash("sha256")
    const stream = fs.createReadStream(filePath)
    stream.on("error", reject)
    stream.on("data", chunk => hash.update(chunk))
    stream.on("end", () => resolve(hash.digest("hex")))
  })
}

async function inventoryPayload() {
  if (!fs.existsSync(payloadRoot)) {
    throw new Error("Missing dist/win-unpacked. Run npm run verify:win:installer first.")
  }

  const candidates = collectPayloadCandidates()
    .sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0)
  const files = []

  for (const candidate of candidates) {
    files.push({
      path: candidate.path,
      size: candidate.size,
      sha256: await hashFile(candidate.fullPath)
    })
  }

  const included = new Set(files.map(file => file.path.toLowerCase()))
  for (const requiredPath of requiredPayloadFiles) {
    if (!included.has(requiredPath.toLowerCase())) {
      throw new Error("Steam depot payload is missing required file " + requiredPath + ".")
    }
  }

  const aggregate = crypto.createHash("sha256")
  let totalBytes = 0
  for (const file of files) {
    aggregate.update(file.path + "\0" + file.size + "\0" + file.sha256 + "\n")
    totalBytes += file.size
  }

  return {
    files,
    fileCount: files.length,
    totalBytes,
    sha256: aggregate.digest("hex")
  }
}

function writeGeneratedFile(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), {recursive: true})
  fs.writeFileSync(filePath, content, {encoding: "utf8"})
}

function displayPath(filePath) {
  const relative = path.relative(desktopRoot, filePath)
  return relative.startsWith("..") ? filePath : relative.replace(/\\/g, "/")
}

function formatBytes(bytes) {
  return (bytes / (1024 * 1024)).toFixed(1) + " MiB"
}

async function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    console.log(usage())
    return
  }
  if (process.platform !== "win32") {
    throw new Error("Mana Chess Windows Steam depot preparation only runs on Windows.")
  }

  const mode = args.upload ? "upload" : "preview"
  const appId = validateSteamId(
    firstValue(args.values.appId, process.env.MANA_CHESS_STEAM_APP_ID, process.env.STEAM_APP_ID),
    "App ID"
  )
  const depotId = validateSteamId(
    firstValue(
      args.values.depotId,
      process.env.MANA_CHESS_STEAM_DEPOT_ID,
      process.env.STEAM_WINDOWS_DEPOT_ID
    ),
    "Windows depot ID"
  )
  if (appId === depotId) {
    throw new Error("Steam app ID and Windows depot ID must be different.")
  }

  const description = validateDescription(firstValue(
    args.values.description,
    process.env.MANA_CHESS_STEAM_BUILD_DESCRIPTION,
    "Mana Chess Windows " + packageJson.version
  ))
  const setLive = validateSetLive(
    firstValue(args.values.setLive, process.env.MANA_CHESS_STEAM_SET_LIVE, ""),
    mode
  )
  const outputDir = path.resolve(desktopRoot, args.values.outputDir || defaultOutputDir)
  const manifestPath = path.resolve(
    desktopRoot,
    args.values.manifestPath || defaultManifestPath
  )
  assertGeneratedPathsAreOutsidePayload(outputDir, manifestPath)

  const config = {appId, depotId, description, mode, outputDir, setLive}
  const appBuild = renderAppBuild(config)
  const depotBuild = renderDepotBuild(config)
  const inventory = await inventoryPayload()
  const exePath = path.join(payloadRoot, "Mana Chess.exe")
  const identity = verifyWindowsExecutableResources(exePath)
  const [authenticode] = verifyWindowsSignatures({
    files: [{label: "steam-windows-executable", path: exePath}]
  })
  const manifest = {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    product: packageJson.productName,
    version: packageJson.version,
    mode,
    appId,
    depotId,
    description,
    setLive,
    payloadRoot: "dist/win-unpacked",
    requiredFiles: requiredPayloadFiles,
    excludedPatterns: exclusions.map(exclusion => exclusion.vdf.replace(/\\/g, "/")),
    fileCount: inventory.fileCount,
    totalBytes: inventory.totalBytes,
    sha256: inventory.sha256,
    executable: {
      path: "Mana Chess.exe",
      identity,
      authenticode
    },
    files: inventory.files
  }

  if (!args.verify) {
    writeGeneratedFile(path.join(outputDir, "app_build_steam_app.vdf"), appBuild)
    writeGeneratedFile(path.join(outputDir, "depot_build_windows.vdf"), depotBuild)
    writeGeneratedFile(manifestPath, JSON.stringify(manifest, null, 2) + "\n")
  }

  console.log("Steam depot " + (args.verify ? "verified" : "prepared") + " in " + mode + " mode.")
  console.log("App " + appId + ", depot " + depotId + ", version " + packageJson.version + ".")
  console.log(
    inventory.fileCount + " files, " + formatBytes(inventory.totalBytes) +
      ", aggregate SHA256 " + inventory.sha256 + "."
  )
  console.log("Authenticode Mana Chess.exe: " + authenticode.status + ".")
  if (args.verify) {
    console.log("No generated files were written (--verify).")
  } else {
    console.log("App VDF: " + displayPath(path.join(outputDir, "app_build_steam_app.vdf")))
    console.log("Depot VDF: " + displayPath(path.join(outputDir, "depot_build_windows.vdf")))
    console.log("Manifest: " + displayPath(manifestPath))
  }
}

main().catch(error => {
  console.error("Steam build preparation failed: " + error.message)
  process.exitCode = 1
})
