const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const packageJson = require(path.join(desktopRoot, "package.json"))
const defaultExePath = path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
const iconPngPath = path.join(desktopRoot, "build", "icon.png")
const maxIconDifference = 100_000

const inspectionScript = String.raw`
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$exePath = $env:MANA_CHESS_VERIFY_EXE
$iconPath = $env:MANA_CHESS_VERIFY_ICON
$item = Get-Item -LiteralPath $exePath
$sourceOriginal = $null
$source = $null
$graphics = $null
$exeIcon = $null
$exeBitmap = $null

try {
  $sourceOriginal = [System.Drawing.Bitmap]::FromFile($iconPath)
  $source = [System.Drawing.Bitmap]::new(32, 32)
  $graphics = [System.Drawing.Graphics]::FromImage($source)
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  [void]$graphics.DrawImage($sourceOriginal, 0, 0, 32, 32)
  $graphics.Dispose()
  $graphics = $null

  $exeIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($item.FullName)
  if ($null -eq $exeIcon) {
    throw "Executable does not expose an associated icon."
  }

  $exeBitmap = $exeIcon.ToBitmap()
  if ($exeBitmap.Width -ne 32 -or $exeBitmap.Height -ne 32) {
    throw "Expected a 32x32 associated icon, found $($exeBitmap.Width)x$($exeBitmap.Height)."
  }

  $difference = 0L
  for ($x = 0; $x -lt 32; $x++) {
    for ($y = 0; $y -lt 32; $y++) {
      $expected = $source.GetPixel($x, $y)
      $actual = $exeBitmap.GetPixel($x, $y)
      $difference += [Math]::Abs([int]$expected.R - [int]$actual.R)
      $difference += [Math]::Abs([int]$expected.G - [int]$actual.G)
      $difference += [Math]::Abs([int]$expected.B - [int]$actual.B)
      $difference += [Math]::Abs([int]$expected.A - [int]$actual.A)
    }
  }

  [pscustomobject]@{
    FileDescription = $item.VersionInfo.FileDescription
    ProductName = $item.VersionInfo.ProductName
    CompanyName = $item.VersionInfo.CompanyName
    FileVersion = $item.VersionInfo.FileVersion
    ProductVersion = $item.VersionInfo.ProductVersion
    InternalName = $item.VersionInfo.InternalName
    LegalCopyright = $item.VersionInfo.LegalCopyright
    IconWidth = $exeBitmap.Width
    IconHeight = $exeBitmap.Height
    IconDifference = $difference
  } | ConvertTo-Json -Compress
}
finally {
  if ($null -ne $graphics) { $graphics.Dispose() }
  if ($null -ne $source) { $source.Dispose() }
  if ($null -ne $sourceOriginal) { $sourceOriginal.Dispose() }
  if ($null -ne $exeBitmap) { $exeBitmap.Dispose() }
  if ($null -ne $exeIcon) { $exeIcon.Dispose() }
}
`

function assertEqual(actual, expected, label) {
  if (actual !== expected) {
    throw new Error(`Expected ${label} ${JSON.stringify(expected)}, found ${JSON.stringify(actual)}.`)
  }
}

function verifyWindowsExecutableResources(exePath = defaultExePath) {
  if (process.platform !== "win32") {
    throw new Error("Windows executable resource verification only runs on Windows.")
  }

  const powershell = path.join(
    process.env.SystemRoot || "C:\\Windows",
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe"
  )

  const output = execFileSync(
    powershell,
    ["-NoProfile", "-NonInteractive", "-Command", inspectionScript],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        MANA_CHESS_VERIFY_EXE: exePath,
        MANA_CHESS_VERIFY_ICON: iconPngPath
      }
    }
  ).trim()
  const identity = JSON.parse(output)

  assertEqual(identity.ProductName, packageJson.productName, "ProductName")
  assertEqual(identity.FileDescription, packageJson.description, "FileDescription")
  assertEqual(identity.CompanyName, packageJson.author?.name || "", "CompanyName")
  assertEqual(identity.FileVersion, packageJson.version, "FileVersion")
  assertEqual(identity.InternalName, packageJson.productName, "InternalName")
  assertEqual(identity.LegalCopyright, packageJson.build?.copyright || "", "LegalCopyright")

  if (!String(identity.ProductVersion || "").startsWith(`${packageJson.version}.`)) {
    throw new Error(`Unexpected ProductVersion ${JSON.stringify(identity.ProductVersion)}.`)
  }

  if (!Number.isFinite(identity.IconDifference) || identity.IconDifference > maxIconDifference) {
    throw new Error(
      `Embedded icon differs from build/icon.png: ${identity.IconDifference} > ${maxIconDifference}.`
    )
  }

  return identity
}

module.exports = {verifyWindowsExecutableResources}

if (require.main === module) {
  const identity = verifyWindowsExecutableResources(process.argv[2] || defaultExePath)
  console.log(
    `Verified Windows identity ${identity.ProductName} ${identity.FileVersion} ` +
      `(icon difference ${identity.IconDifference}).`
  )
}
