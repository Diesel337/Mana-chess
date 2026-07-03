const fs = require("node:fs")
const path = require("node:path")
const {spawnSync} = require("node:child_process")

const desktopRoot = path.resolve(__dirname, "..")
const checkRoots = ["src", "scripts"]
const extensions = new Set([".cjs", ".js"])

function collectJavaScriptFiles(relativeDir) {
  const dir = path.join(desktopRoot, relativeDir)
  const entries = fs.readdirSync(dir, {withFileTypes: true})

  return entries.flatMap(entry => {
    const relativePath = path.join(relativeDir, entry.name)
    const fullPath = path.join(desktopRoot, relativePath)

    if (entry.isDirectory()) {
      return collectJavaScriptFiles(relativePath)
    }

    if (entry.isFile() && extensions.has(path.extname(entry.name))) {
      return [fullPath]
    }

    return []
  })
}

const files = checkRoots
  .flatMap(collectJavaScriptFiles)
  .sort((left, right) => left.localeCompare(right))

for (const file of files) {
  const relativePath = path.relative(desktopRoot, file)
  console.log(`Checking ${relativePath}`)

  const result = spawnSync(process.execPath, ["--check", file], {
    cwd: desktopRoot,
    stdio: "inherit"
  })

  if (result.status !== 0) {
    process.exit(result.status || 1)
  }
}

console.log(`Checked ${files.length} desktop JavaScript files.`)
