const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const root = path.resolve(__dirname, "../..")
const context = vm.createContext({window: {}})

for (const file of ["cosmetic_catalog.js", "cosmetic_progression.js"]) {
  const source = fs.readFileSync(path.join(root, "assets/js", file), "utf8")
  vm.runInContext(source, context, {filename: file})
}

const progression = context.window.ManaChessCosmeticProgression

const loadCosmetics = () => {
  const values = new Map()
  const events = []
  const localStorage = {
    getItem: key => values.has(key) ? values.get(key) : null,
    removeItem: key => values.delete(key),
    setItem: (key, value) => values.set(key, String(value)),
  }
  const document = {
    addEventListener: () => {},
    documentElement: {dataset: {}, style: {setProperty: () => {}}},
    querySelectorAll: () => [],
  }
  class MutationObserver {
    observe() {}
  }
  class CustomEvent {
    constructor(type, init = {}) {
      this.type = type
      this.detail = init.detail
    }
  }
  const window = {
    CustomEvent,
    dispatchEvent: event => events.push(event),
  }
  const browser = vm.createContext({
    MutationObserver,
    document,
    localStorage,
    requestAnimationFrame: callback => callback(),
    window,
  })

  for (const file of ["cosmetic_catalog.js", "cosmetic_progression.js", "cosmetics.js"]) {
    const source = fs.readFileSync(path.join(root, "assets/js", file), "utf8")
    vm.runInContext(source, browser, {filename: file})
  }

  return {controller: browser.window.ManaChessCosmetics, events, localStorage}
}

test("defines the five release mastery milestones", () => {
  assert.deepEqual(
    Array.from(progression.milestones, milestone => [milestone.id, milestone.metric, milestone.target]),
    [
      ["arcane", "played", 1],
      ["crystal", "wins", 3],
      ["elemental", "played", 10],
      ["custom", "wins", 5],
      ["celestial", "wins", 10],
    ]
  )
})

test("unlocks complete rewards only after their local milestone", () => {
  const firstMatch = progression.syncUnlocks({played: 1, wins: 0}, [])
  assert.deepEqual(Array.from(firstMatch.unlocks).sort(), ["board:arcane", "piece:arcane"])

  const threeWins = progression.syncUnlocks({played: 4, wins: 3}, [])
  assert.deepEqual(Array.from(threeWins.unlocks).sort(), [
    "board:arcane",
    "board:crystal",
    "piece:arcane",
    "piece:crystal",
  ])

  const fullRoute = progression.syncUnlocks({played: 10, wins: 10}, [])
  assert.equal(fullRoute.unlocks.length, 11)
  assert.deepEqual(
    Array.from(fullRoute.unlockedMilestones),
    ["arcane", "crystal", "elemental", "custom", "celestial"]
  )
})

test("preserves old unlocks and repairs legacy custom palette groups", () => {
  const partial = progression.syncUnlocks({played: 0, wins: 0}, ["board:crystal"])
  assert.deepEqual(Array.from(partial.unlocks), ["board:crystal"])

  const custom = progression.syncUnlocks({played: 0, wins: 0}, ["palette:custom"])
  assert.deepEqual(Array.from(custom.unlocks).sort(), ["board:custom", "palette:custom", "piece:custom"])
})

test("reports compact progress and mastery summary labels", () => {
  assert.equal(progression.progressLabel("pack:arcane", {played: 0}), "0/1 partida")
  assert.equal(progression.progressLabel("piece:crystal", {wins: 2}), "2/3 victorias")
  assert.equal(progression.progressLabel("board:elemental", {played: 20}), "10/10 partidas")
  assert.equal(progression.requirementLabel("palette:custom"), "Gana 5 partidas")

  const synced = progression.syncUnlocks({played: 4, wins: 3}, [])
  assert.deepEqual(
    {...progression.summary({played: 4, wins: 3}, synced.unlocks)},
    {completed: 2, total: 5, percent: 40, label: "Maestria 2/5"}
  )
})

test("locked cosmetic actions cannot grant or equip their own reward", () => {
  const {controller, localStorage} = loadCosmetics()

  assert.equal(controller.chooseBoard("arcane"), false)
  assert.equal(controller.choosePack("crystal"), false)
  assert.equal(controller.choosePack("celestial"), false)
  assert.equal(controller.choosePalette("midnight"), false)
  assert.equal(localStorage.getItem("mana-chess-cosmetic-unlocks"), null)
  assert.equal(localStorage.getItem("mana-chess-board-skin"), null)

  localStorage.setItem("mana-chess-local-stats", JSON.stringify({played: 1, wins: 0}))
  controller.render()

  assert.equal(controller.chooseBoard("arcane"), true)
  assert.equal(localStorage.getItem("mana-chess-board-skin"), "arcane")
  assert.deepEqual(
    JSON.parse(localStorage.getItem("mana-chess-cosmetic-unlocks")).sort(),
    ["board:arcane", "piece:arcane"]
  )
})

test("equips the complete Celestial set only after ten wins", () => {
  const {controller, localStorage} = loadCosmetics()
  localStorage.setItem("mana-chess-local-stats", JSON.stringify({played: 10, wins: 10}))

  controller.render()

  assert.equal(controller.choosePack("celestial"), true)
  assert.equal(localStorage.getItem("mana-chess-board-skin"), "celestial")
  assert.equal(localStorage.getItem("mana-chess-piece-skin"), "celestial")

  const unlocks = JSON.parse(localStorage.getItem("mana-chess-cosmetic-unlocks"))
  assert.ok(unlocks.includes("board:celestial"))
  assert.ok(unlocks.includes("piece:celestial"))
})

test("announces each newly earned mastery reward only once", () => {
  const {controller, events, localStorage} = loadCosmetics()
  localStorage.setItem("mana-chess-local-stats", JSON.stringify({played: 1, wins: 0}))

  controller.render()
  controller.render()

  assert.equal(events.length, 1)
  assert.equal(events[0].type, "mana-chess:cosmetic-unlocked")
  assert.deepEqual({...events[0].detail}, {id: "arcane", label: "Conjunto Arcano"})
})
