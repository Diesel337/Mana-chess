const fs = require("node:fs")
const path = require("node:path")
const {spawnSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const steamRoot = path.join(desktopRoot, "steam")
const payloadRoot = path.join(desktopRoot, "dist", "win-unpacked")

function usage() {
  return [
    "Run a generated Mana Chess SteamPipe build:",
    "",
    "  node scripts/run-steam-build.cjs [--upload] [--app-build <path>]",
    "",
    "Preview is the safe default. Upload additionally requires:",
    "  MANA_CHESS_STEAM_UPLOAD_CONFIRM=UPLOAD_<AppID>",
    "",
    "Required environment:",
    "  MANA_CHESS_STEAM_USERNAME (or STEAM_USERNAME)",
    "",
    "SteamCMD discovery:",
    "  STEAMCMD_PATH, STEAMWORKS_SDK_PATH, ignored local tool folders, or PATH.",
    "",
    "This command deliberately never accepts or passes a Steam password."
  ].join("\n")
}

function parseArgs(argv) {
  const result = {
    upload: false,
    help: false,
    appBuildPath: path.join(steamRoot, "app_build_steam_app.vdf")
  }

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    if (argument === "--upload") {
      result.upload = true
      continue
    }
    if (argument === "--help") {
      result.help = true
      continue
    }

    const equalsIndex = argument.indexOf("=")
    const option = equalsIndex === -1 ? argument : argument.slice(0, equalsIndex)
    if (option !== "--app-build") {
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
      throw new Error("Missing value for --app-build.")
    }
    result.appBuildPath = path.resolve(desktopRoot, value)
  }

  return result
}

function readRequired(filePath, preparationCommand) {
  if (!fs.existsSync(filePath)) {
    throw new Error(
      "Missing " + path.relative(desktopRoot, filePath).replace(/\\/g, "/") +
        ". Run " + preparationCommand + " first."
    )
  }
  return fs.readFileSync(filePath, "utf8")
}

function extractRequired(content, pattern, label) {
  const match = content.match(pattern)
  if (!match) {
    throw new Error("Generated Steam app VDF is missing a valid " + label + ".")
  }
  return match[1]
}

function decodeVdfPath(value) {
  return value.replace(/\\\\/g, "\\")
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase()
}

function isInside(parentPath, childPath) {
  const relative = path.relative(parentPath, childPath)
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))
}

function validateGeneratedBuild(appBuildPath, upload) {
  const preparationCommand = upload
    ? "npm run steam:prepare:upload"
    : "npm run steam:prepare:preview"
  const appBuild = readRequired(appBuildPath, preparationCommand)
  if (/<[A-Z0-9_]+>/.test(appBuild)) {
    throw new Error("Generated Steam app VDF still contains placeholders.")
  }

  const appId = extractRequired(appBuild, /"AppID"\s+"([1-9]\d*)"/i, "AppID")
  const depotReferences = [
    ...appBuild.matchAll(/"([1-9]\d*)"\s+"depot_build_windows\.vdf"/gi)
  ]
  if (depotReferences.length !== 1) {
    throw new Error("Generated Steam app VDF must reference exactly one Windows depot.")
  }
  const depotReference = depotReferences[0][1]
  const appBuildDir = path.dirname(appBuildPath)
  const contentRoot = decodeVdfPath(
    extractRequired(appBuild, /"ContentRoot"\s+"([^"]+)"/i, "ContentRoot")
  )
  const buildOutput = decodeVdfPath(
    extractRequired(appBuild, /"BuildOutput"\s+"([^"]+)"/i, "BuildOutput")
  )
  if (!samePath(path.resolve(appBuildDir, contentRoot), payloadRoot)) {
    throw new Error("Generated Steam app VDF must use dist/win-unpacked as ContentRoot.")
  }
  if (!samePath(path.resolve(appBuildDir, buildOutput), path.join(appBuildDir, "build-output"))) {
    throw new Error("Generated Steam app VDF must keep BuildOutput beside the VDF.")
  }
  if (isInside(payloadRoot, appBuildDir)) {
    throw new Error("Generated Steam VDF files cannot live inside the depot payload.")
  }
  const setLiveMatch = appBuild.match(/"SetLive"\s+"([^"]*)"/i)
  const setLive = setLiveMatch ? setLiveMatch[1] : ""
  const isPreview = /"Preview"\s+"1"/i.test(appBuild)

  if (upload && isPreview) {
    throw new Error(
      "Upload mode refuses a preview VDF. Run npm run steam:prepare:upload first."
    )
  }
  if (!upload && !isPreview) {
    throw new Error(
      "Preview mode refuses an upload-capable VDF. Run npm run steam:prepare:preview first."
    )
  }
  if (!upload && setLive) {
    throw new Error("Preview mode refuses a VDF with SetLive configured.")
  }
  if (setLive.toLowerCase() === "default") {
    throw new Error("Steam's default branch must be assigned manually.")
  }
  if (setLive && !/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(setLive)) {
    throw new Error("Generated Steam app VDF contains an invalid SetLive branch.")
  }

  const depotPath = path.join(path.dirname(appBuildPath), "depot_build_windows.vdf")
  const depotBuild = readRequired(depotPath, preparationCommand)
  if (/<[A-Z0-9_]+>/.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF still contains placeholders.")
  }
  const depotId = extractRequired(depotBuild, /"DepotID"\s+"([1-9]\d*)"/i, "DepotID")
  if (depotId !== depotReference) {
    throw new Error(
      "Steam app/depot VDF mismatch: app references " + depotReference +
        ", depot declares " + depotId + "."
    )
  }
  if (depotId === appId) {
    throw new Error("Steam app ID and Windows depot ID must be different.")
  }
  if (!/"LocalPath"\s+"\*"/i.test(depotBuild) ||
      !/"DepotPath"\s+"\."/i.test(depotBuild) ||
      !/"recursive"\s+"1"/i.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF must map the complete payload recursively.")
  }
  if (!/"FileExclusion"\s+"\*\.pdb"/i.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF must exclude PDB files.")
  }
  if (!/"FileExclusion"\s+"\*\.log"/i.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF must exclude log files.")
  }
  if (!/"FileExclusion"\s+"resources\\{1,2}app-update\.yml"/i.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF must exclude resources/app-update.yml.")
  }
  if (!/"FileExclusion"\s+"resources\\{1,2}elevate\.exe"/i.test(depotBuild)) {
    throw new Error("Generated Steam depot VDF must exclude resources/elevate.exe.")
  }

  return {appId, depotId, isPreview, setLive}
}

function executableCandidate(candidate) {
  if (!candidate) {
    return null
  }

  const normalized = path.resolve(String(candidate).trim().replace(/^"(.*)"$/, "$1"))
  if (!fs.existsSync(normalized)) {
    return null
  }
  if (fs.statSync(normalized).isDirectory()) {
    const nested = path.join(normalized, "steamcmd.exe")
    return fs.existsSync(nested) ? nested : null
  }
  return path.basename(normalized).toLowerCase() === "steamcmd.exe" ? normalized : null
}

function findSteamCmd() {
  const sdkRoot = process.env.STEAMWORKS_SDK_PATH
  const candidates = [
    process.env.STEAMCMD_PATH,
    sdkRoot && path.join(sdkRoot, "tools", "ContentBuilder", "builder", "steamcmd.exe"),
    path.join(steamRoot, "steamworks-sdk", "tools", "ContentBuilder", "builder", "steamcmd.exe"),
    path.join(steamRoot, "steamcmd", "steamcmd.exe")
  ]

  for (const candidate of candidates) {
    const executable = executableCandidate(candidate)
    if (executable) {
      return executable
    }
  }

  const where = spawnSync("where.exe", ["steamcmd.exe"], {
    cwd: desktopRoot,
    encoding: "utf8",
    windowsHide: true
  })
  if (where.status === 0) {
    for (const candidate of String(where.stdout || "").split(/\r?\n/)) {
      const executable = executableCandidate(candidate)
      if (executable) {
        return executable
      }
    }
  }

  throw new Error(
    "SteamCMD was not found. Install the latest Steamworks SDK and set " +
      "STEAMWORKS_SDK_PATH, or set STEAMCMD_PATH to steamcmd.exe."
  )
}

function validateUsername(value) {
  const username = String(value || "").trim()
  if (!/^[A-Za-z0-9_.-]+$/.test(username)) {
    throw new Error(
      "Set MANA_CHESS_STEAM_USERNAME (or STEAM_USERNAME) to the Steam build account name."
    )
  }
  return username
}

function main() {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    console.log(usage())
    return
  }
  if (process.platform !== "win32") {
    throw new Error("Mana Chess SteamPipe execution only runs on Windows.")
  }

  const build = validateGeneratedBuild(args.appBuildPath, args.upload)
  if (args.upload) {
    const expectedConfirmation = "UPLOAD_" + build.appId
    if (process.env.MANA_CHESS_STEAM_UPLOAD_CONFIRM !== expectedConfirmation) {
      throw new Error(
        "Steam upload requires MANA_CHESS_STEAM_UPLOAD_CONFIRM=" + expectedConfirmation + "."
      )
    }
  }

  const username = validateUsername(
    process.env.MANA_CHESS_STEAM_USERNAME || process.env.STEAM_USERNAME
  )
  const steamcmd = findSteamCmd()
  const mode = args.upload ? "UPLOAD" : "PREVIEW"
  console.log(
    "SteamPipe " + mode + ": app " + build.appId + ", depot " + build.depotId +
      (build.setLive ? ", SetLive " + build.setLive : "") + "."
  )
  console.log("> steamcmd +login <steam_username> +run_app_build <generated-vdf> +quit")

  const result = spawnSync(
    steamcmd,
    ["+login", username, "+run_app_build", args.appBuildPath, "+quit"],
    {
      cwd: path.dirname(args.appBuildPath),
      stdio: "inherit",
      windowsHide: false
    }
  )
  if (result.error) {
    throw result.error
  }
  if (result.status !== 0) {
    throw new Error("SteamCMD exited with status " + result.status + ".")
  }

  console.log("SteamPipe " + mode + " completed.")
}

try {
  main()
} catch (error) {
  console.error("Steam build command failed: " + error.message)
  process.exitCode = 1
}
