const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const {execFileSync} = require("node:child_process")
const {verifyWindowsExecutableResources} = require("./verify-win-executable-resources.cjs")
const {verifyWindowsSignatures} = require("./verify-win-signatures.cjs")

const desktopRoot = path.resolve(__dirname, "..")
const node = process.execPath
const packageJson = require(path.join(desktopRoot, "package.json"))
const productName = packageJson.productName || "Mana Chess"
const installerPath = path.join(desktopRoot, "dist", `Mana Chess Setup ${packageJson.version}.exe`)
const smokePrefix = "mana-chess-installer-smoke-"
const powershell = path.join(
  process.env.SystemRoot || "C:\\Windows",
  "System32",
  "WindowsPowerShell",
  "v1.0",
  "powershell.exe"
)

const stateInspectionScript = String.raw`
$ErrorActionPreference = "Stop"
$productName = $env:MANA_CHESS_INSTALL_PRODUCT
$uninstallRoots = @(
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$registryEntries = @(
  Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { [string]$_.DisplayName -eq $productName } |
    ForEach-Object {
      [pscustomobject]@{
        DisplayName = [string]$_.DisplayName
        DisplayVersion = [string]$_.DisplayVersion
        Publisher = [string]$_.Publisher
        UninstallString = [string]$_.UninstallString
        QuietUninstallString = [string]$_.QuietUninstallString
        RegistryPath = [string]$_.PSPath
      }
    }
)

function Read-Shortcut([string]$shortcutPath) {
  if (-not (Test-Path -LiteralPath $shortcutPath)) {
    return [pscustomobject]@{ Path = $shortcutPath; Exists = $false; TargetPath = ""; Arguments = "" }
  }

  $shell = $null
  $shortcut = $null
  try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    return [pscustomobject]@{
      Path = $shortcutPath
      Exists = $true
      TargetPath = [string]$shortcut.TargetPath
      Arguments = [string]$shortcut.Arguments
    }
  }
  finally {
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
  }
}

$protocolCommandPath = "Registry::HKEY_CURRENT_USER\Software\Classes\manachess\shell\open\command"
$protocolCommand = ""
if (Test-Path -LiteralPath $protocolCommandPath) {
  $protocolCommand = [string](Get-Item -LiteralPath $protocolCommandPath).GetValue("")
}

$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Mana Chess.lnk"
$startMenuShortcut = Join-Path ([Environment]::GetFolderPath("Programs")) "Mana Chess.lnk"

[pscustomobject]@{
  RegistryEntries = $registryEntries
  DesktopShortcut = Read-Shortcut $desktopShortcut
  StartMenuShortcut = Read-Shortcut $startMenuShortcut
  Protocol = [pscustomobject]@{
    Exists = (Test-Path -LiteralPath $protocolCommandPath)
    Command = $protocolCommand
  }
} | ConvertTo-Json -Depth 6 -Compress
`

const cleanupRegistryScript = String.raw`
$ErrorActionPreference = "Stop"
$installDir = $env:MANA_CHESS_INSTALL_DIR
$installedExe = $env:MANA_CHESS_INSTALLED_EXE
$productName = $env:MANA_CHESS_INSTALL_PRODUCT
$protocolRoot = "HKCU:\Software\Classes\manachess"
$protocolCommandPath = Join-Path $protocolRoot "shell\open\command"

if (Test-Path -LiteralPath $protocolCommandPath) {
  $command = [string](Get-Item -LiteralPath $protocolCommandPath).GetValue("")
  if ($command.IndexOf($installedExe, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    Remove-Item -LiteralPath $protocolRoot -Recurse -Force
  }
}

$uninstallRoots = @(
  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object {
    [string]$_.DisplayName -eq $productName -and
    ([string]$_.UninstallString).IndexOf($installDir, [StringComparison]::OrdinalIgnoreCase) -ge 0
  } |
  ForEach-Object { Remove-Item -LiteralPath $_.PSPath -Recurse -Force }
`

function wait(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

function run(command, args, options = {}) {
  console.log(`> ${[command, ...args].join(" ")}`)
  execFileSync(command, args, {
    cwd: desktopRoot,
    stdio: "inherit",
    timeout: 180_000,
    ...options
  })
}

function installationState() {
  const output = execFileSync(
    powershell,
    ["-NoProfile", "-NonInteractive", "-Command", stateInspectionScript],
    {
      encoding: "utf8",
      env: {...process.env, MANA_CHESS_INSTALL_PRODUCT: productName}
    }
  ).trim()
  const state = JSON.parse(output)
  state.RegistryEntries = Array.isArray(state.RegistryEntries)
    ? state.RegistryEntries
    : state.RegistryEntries
      ? [state.RegistryEntries]
      : []
  return state
}

function samePath(left, right) {
  return path.resolve(String(left || "")).toLowerCase() === path.resolve(String(right || "")).toLowerCase()
}

function includesPath(value, expectedPath) {
  return String(value || "").toLowerCase().includes(path.resolve(expectedPath).toLowerCase())
}

function assertCleanMachineState(state) {
  const conflicts = []
  if (state.RegistryEntries.length > 0) conflicts.push("uninstall registry entry")
  if (state.DesktopShortcut?.Exists) conflicts.push(state.DesktopShortcut.Path)
  if (state.StartMenuShortcut?.Exists) conflicts.push(state.StartMenuShortcut.Path)
  if (state.Protocol?.Exists) conflicts.push("manachess:// registration")

  if (conflicts.length > 0) {
    throw new Error(`Installer smoke requires no existing Mana Chess installation: ${conflicts.join(", ")}`)
  }
}

function assertInstalledState(state, installedExe, uninstallerPath, requireProtocol) {
  if (state.RegistryEntries.length !== 1) {
    throw new Error(`Expected one Mana Chess uninstall entry, found ${state.RegistryEntries.length}.`)
  }

  const entry = state.RegistryEntries[0]
  if (entry.DisplayVersion !== packageJson.version) {
    throw new Error(`Expected installed version ${packageJson.version}, found ${entry.DisplayVersion || "empty"}.`)
  }
  const expectedPublisher = packageJson.author?.name || ""
  if (entry.Publisher !== expectedPublisher) {
    throw new Error(`Expected installed publisher ${expectedPublisher}, found ${entry.Publisher || "empty"}.`)
  }
  if (!includesPath(entry.UninstallString, uninstallerPath)) {
    throw new Error("Uninstall registry command does not target the temporary installation.")
  }
  if (!String(entry.QuietUninstallString || "").includes("/S")) {
    throw new Error("Quiet uninstall registry command is missing /S.")
  }

  for (const shortcut of [state.DesktopShortcut, state.StartMenuShortcut]) {
    if (!shortcut?.Exists) throw new Error(`Expected installer shortcut at ${shortcut?.Path || "unknown path"}.`)
    if (!samePath(shortcut.TargetPath, installedExe)) {
      throw new Error(`Shortcut ${shortcut.Path} targets ${shortcut.TargetPath || "nothing"}.`)
    }
  }

  if (requireProtocol) {
    if (!state.Protocol?.Exists || !includesPath(state.Protocol.Command, installedExe)) {
      throw new Error("manachess:// is not registered to the installed executable.")
    }
  }
}

function assertUninstalledState(state) {
  if (state.RegistryEntries.length > 0) throw new Error("Uninstaller left a Mana Chess registry entry.")
  if (state.DesktopShortcut?.Exists) throw new Error("Uninstaller left the desktop shortcut.")
  if (state.StartMenuShortcut?.Exists) throw new Error("Uninstaller left the Start Menu shortcut.")
  if (state.Protocol?.Exists) throw new Error("Uninstaller left the manachess:// registration.")
}

async function waitForInstalledFilesToDisappear(installedExe, uninstallerPath) {
  const deadline = Date.now() + 15_000
  while (Date.now() < deadline) {
    if (!fs.existsSync(installedExe) && !fs.existsSync(uninstallerPath)) return
    await wait(250)
  }
  throw new Error("Timed out waiting for installed files to be removed.")
}

function safeRemoveSmokeRoot(smokeRoot) {
  const resolvedRoot = path.resolve(smokeRoot)
  const expectedParent = path.resolve(os.tmpdir())
  if (path.dirname(resolvedRoot) !== expectedParent || !path.basename(resolvedRoot).startsWith(smokePrefix)) {
    throw new Error(`Refusing to remove unsafe installer smoke path ${resolvedRoot}`)
  }
  fs.rmSync(resolvedRoot, {recursive: true, force: true})
}

function removeOwnedShortcuts(state, installedExe) {
  for (const shortcut of [state.DesktopShortcut, state.StartMenuShortcut]) {
    if (shortcut?.Exists && samePath(shortcut.TargetPath, installedExe)) {
      fs.rmSync(shortcut.Path, {force: true})
    }
  }
}

function removeOwnedRegistryResidue(installDir, installedExe) {
  execFileSync(
    powershell,
    ["-NoProfile", "-NonInteractive", "-Command", cleanupRegistryScript],
    {
      stdio: "ignore",
      env: {
        ...process.env,
        MANA_CHESS_INSTALL_DIR: installDir,
        MANA_CHESS_INSTALLED_EXE: installedExe,
        MANA_CHESS_INSTALL_PRODUCT: productName
      }
    }
  )
}

async function cleanup(smokeRoot, installDir, installedExe, uninstallerPath) {
  if (fs.existsSync(uninstallerPath)) {
    try {
      execFileSync(uninstallerPath, ["/currentuser", "/S"], {
        cwd: desktopRoot,
        stdio: "ignore",
        timeout: 120_000
      })
      await waitForInstalledFilesToDisappear(installedExe, uninstallerPath)
    } catch (_error) {
      // Guarded residue cleanup below handles incomplete QA uninstalls.
    }
  }

  try {
    const state = installationState()
    removeOwnedShortcuts(state, installedExe)
    removeOwnedRegistryResidue(installDir, installedExe)
  } finally {
    safeRemoveSmokeRoot(smokeRoot)
  }
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("smoke:win:installer only runs on Windows.")
  }
  if (!fs.existsSync(installerPath)) {
    throw new Error(`Missing ${installerPath}. Run npm run verify:win:installer first.`)
  }

  assertCleanMachineState(installationState())

  const smokeRoot = fs.mkdtempSync(path.join(os.tmpdir(), smokePrefix))
  const installDir = path.join(smokeRoot, "install")
  const installedExe = path.join(installDir, "Mana Chess.exe")
  const uninstallerPath = path.join(installDir, "Uninstall Mana Chess.exe")
  const elevatePath = path.join(installDir, "resources", "elevate.exe")
  const userDataDir = path.join(smokeRoot, "user-data")

  try {
    run(installerPath, ["/S", `/D=${installDir}`])

    if (!fs.existsSync(installedExe) || !fs.existsSync(uninstallerPath)) {
      throw new Error("Installer did not create the expected executable and uninstaller.")
    }

    const identity = verifyWindowsExecutableResources(installedExe)
    const installedSignatures = verifyWindowsSignatures({
      files: [
        {label: "installed-windows-executable", path: installedExe},
        {label: "windows-uninstaller", path: uninstallerPath},
        {label: "windows-elevate-helper", path: elevatePath}
      ]
    })
    assertInstalledState(installationState(), installedExe, uninstallerPath, false)

    for (const signature of installedSignatures) {
      console.log(`Authenticode ${signature.label}: ${signature.status}`)
    }

    run(
      node,
      ["scripts/smoke-win-app.cjs", `--exe=${installedExe}`, "--mode=windowed", "--register-protocol"],
      {
        env: {
          ...process.env,
          MANA_CHESS_SMOKE_USER_DATA_DIR: userDataDir,
          MANA_CHESS_DESKTOP_CHANNEL: "desktop-installer-smoke"
        }
      }
    )
    assertInstalledState(installationState(), installedExe, uninstallerPath, true)

    run(uninstallerPath, ["/currentuser", "/S"])
    await waitForInstalledFilesToDisappear(installedExe, uninstallerPath)

    const uninstalledState = installationState()
    assertUninstalledState(uninstalledState)

    const installResidue = fs.existsSync(installDir) ? fs.readdirSync(installDir, {withFileTypes: true}) : []
    if (installResidue.length > 0) {
      throw new Error(`Uninstaller left files in ${installDir}: ${installResidue.map(entry => entry.name).join(", ")}`)
    }

    console.log(`Installed and launched ${identity.ProductName} ${identity.FileVersion}.`)
    console.log("Verified uninstall registry, shortcuts, manachess://, and application files were removed.")
  } finally {
    await cleanup(smokeRoot, installDir, installedExe, uninstallerPath)
  }
}

main().catch(error => {
  console.error(error.message || error)
  process.exit(1)
})
