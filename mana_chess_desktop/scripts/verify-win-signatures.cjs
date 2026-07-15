const fs = require("node:fs")
const path = require("node:path")
const {execFileSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const packageJson = require(path.join(desktopRoot, "package.json"))
const defaultFiles = [
  {
    label: "windows-executable",
    path: path.join(desktopRoot, "dist", "win-unpacked", "Mana Chess.exe")
  },
  {
    label: "windows-installer",
    path: path.join(desktopRoot, "dist", `Mana Chess Setup ${packageJson.version}.exe`)
  }
]

const inspectionScript = String.raw`
$ErrorActionPreference = "Stop"
$signature = Get-AuthenticodeSignature -FilePath $env:MANA_CHESS_SIGNATURE_FILE

[pscustomobject]@{
  Status = [string]$signature.Status
  SignerSubject = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { "" }
  SignerThumbprint = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Thumbprint } else { "" }
  TimeStamperSubject = if ($null -ne $signature.TimeStamperCertificate) { [string]$signature.TimeStamperCertificate.Subject } else { "" }
} | ConvertTo-Json -Compress
`

function envEnabled(value) {
  return ["1", "true", "yes", "on"].includes(String(value || "").trim().toLowerCase())
}

function relativePath(filePath) {
  return path.relative(desktopRoot, filePath).replace(/\\/g, "/")
}

function inspectSignature(file) {
  if (!fs.existsSync(file.path)) {
    throw new Error(`Missing ${file.label} at ${file.path}`)
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
      env: {...process.env, MANA_CHESS_SIGNATURE_FILE: file.path}
    }
  ).trim()

  const inspected = JSON.parse(output)
  return {
    label: file.label,
    path: relativePath(file.path),
    status: inspected.Status,
    signerSubject: inspected.SignerSubject,
    signerThumbprint: inspected.SignerThumbprint,
    timeStamperSubject: inspected.TimeStamperSubject
  }
}

function verifyWindowsSignatures(options = {}) {
  if (process.platform !== "win32") {
    throw new Error("Windows Authenticode verification only runs on Windows.")
  }

  const files = options.files || defaultFiles
  const requireSigned = options.requireSigned ?? envEnabled(process.env.MANA_CHESS_REQUIRE_SIGNED)
  const signatures = files.map(inspectSignature)
  const invalid = signatures.filter(signature => signature.status !== "Valid")

  if (requireSigned && invalid.length > 0) {
    const summary = invalid.map(signature => `${signature.path}=${signature.status}`).join(", ")
    throw new Error(`Signed Windows release required, but Authenticode validation failed: ${summary}`)
  }

  return signatures
}

module.exports = {verifyWindowsSignatures}

if (require.main === module) {
  const signatures = verifyWindowsSignatures()
  for (const signature of signatures) {
    console.log(`Authenticode ${signature.path}: ${signature.status}`)
  }
}
