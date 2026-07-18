const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

const root = path.resolve(__dirname, "../..")
const listeners = new Map()
const timers = []
const window = {
  addEventListener: (name, callback) => listeners.set(name, callback),
  clearTimeout: () => {},
  setTimeout: callback => {
    timers.push(callback)
    return timers.length
  },
}
const context = vm.createContext({document: {}, window})
const source = fs.readFileSync(path.join(root, "assets/js/game_effects.js"), "utf8")
vm.runInContext(source, context, {filename: "game_effects.js"})

const controller = window.ManaChessGameEffects

const classList = () => {
  const values = new Set()
  return {
    add: (...names) => names.forEach(name => values.add(name)),
    contains: name => values.has(name),
    remove: (...names) => names.forEach(name => values.delete(name)),
  }
}

const element = (children = {}) => ({
  attributes: {},
  children,
  classList: classList(),
  offsetWidth: 80,
  style: {},
  getBoundingClientRect: () => ({height: 48, left: 120, top: 240, width: 48}),
  querySelector(selector) {
    return this.children[selector] || null
  },
  setAttribute(name, value) {
    this.attributes[name] = value
  },
})

const mountedHook = () => {
  const resultKicker = {textContent: ""}
  const resultTitle = {textContent: ""}
  const resultDetail = {textContent: ""}
  const unlockTitle = {textContent: ""}
  const captureImpact = element()
  const checkImpact = element()
  const result = element({
    "[data-game-effect-kicker]": resultKicker,
    "[data-game-effect-title]": resultTitle,
    "[data-game-effect-detail]": resultDetail,
  })
  const unlock = element({"[data-game-effect-unlock-title]": unlockTitle})
  const board = element()
  const square = element()
  square.closest = selector => selector === ".mc-board" ? board : null
  const game = {querySelector: () => square}
  const rootElement = element({
    "[data-game-effect-capture]": captureImpact,
    "[data-game-effect-check]": checkImpact,
    "[data-game-effect-result]": result,
    "[data-game-effect-unlock]": unlock,
  })
  rootElement.closest = selector => selector === ".mc-game" ? game : null

  let eventHandler = null
  const hook = {
    ...window.ManaChessGameEffectsHook,
    el: rootElement,
    handleEvent: (_name, callback) => { eventHandler = callback },
  }
  hook.mounted()

  return {
    board,
    captureImpact,
    checkImpact,
    event: payload => eventHandler(payload),
    hook,
    result,
    resultDetail,
    resultKicker,
    resultTitle,
    square,
    unlock,
    unlockTitle,
  }
}

test("normalizes presentation labels without trusting missing data", () => {
  assert.equal(controller.resultKicker("win"), "Victoria")
  assert.equal(controller.resultKicker("loss"), "Partida terminada")
  assert.deepEqual({...controller.normalizeUnlock({id: "arcane", label: "Conjunto Arcano"})}, {
    id: "arcane",
    label: "Conjunto Arcano",
  })
})

test("queues an unlock until its LiveView hook is mounted", () => {
  listeners.get("mana-chess:cosmetic-unlocked")({
    detail: {id: "celestial", label: "Conjunto Celestial"},
  })

  const view = mountedHook()

  assert.equal(view.unlockTitle.textContent, "Conjunto Celestial")
  assert.equal(view.unlock.attributes["aria-hidden"], "false")
  assert.equal(view.unlock.classList.contains("mc-effect-visible"), true)
  view.hook.destroyed()
})

test("plays capture, check and result payloads on stable targets", () => {
  const view = mountedHook()

  view.event({kind: "capture", row: 3, col: 4})
  assert.equal(view.square.classList.contains("mc-effect-capture"), true)
  assert.equal(view.captureImpact.classList.contains("mc-effect-active"), true)
  assert.equal(view.captureImpact.style.left, "120px")

  view.event({kind: "check", row: 0, col: 4})
  assert.equal(view.checkImpact.classList.contains("mc-effect-active"), true)
  assert.equal(view.board.classList.contains("mc-effect-check-board"), true)

  view.event({
    kind: "result",
    tone: "win",
    title: "Ganaste",
    detail: "Jaque mate a negras.",
  })
  assert.equal(view.resultKicker.textContent, "Victoria")
  assert.equal(view.resultTitle.textContent, "Ganaste")
  assert.equal(view.resultDetail.textContent, "Jaque mate a negras.")
  assert.equal(view.result.classList.contains("mc-effect-tone-win"), true)
  assert.equal(view.result.classList.contains("mc-effect-visible"), true)
  view.hook.destroyed()
})
