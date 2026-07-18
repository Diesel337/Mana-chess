// Transient game presentation effects. Keep the priv/static copy in sync until
// Mana Chess has a real JS bundling step.
(() => {
  const captureDuration = 950
  const checkDuration = 900
  const resultDuration = 2400
  const unlockDuration = 3000
  const resultTones = new Set(["win", "loss", "draw"])
  const state = {hook: null, pendingUnlocks: []}

  const resultKicker = tone => {
    if (tone === "win") return "Victoria"
    if (tone === "loss") return "Partida terminada"
    if (tone === "draw") return "Resultado"
    return "Partida terminada"
  }

  const normalizeUnlock = (detail = {}) => ({
    id: String(detail.id || "reward"),
    label: String(detail.label || "Nueva recompensa"),
  })

  const schedule = (hook, callback, delay) => {
    const timer = window.setTimeout(() => {
      hook.effectTimers.delete(timer)
      callback()
    }, delay)

    hook.effectTimers.add(timer)
    return timer
  }

  const restartClass = (hook, element, className, duration) => {
    if (!element) return
    element.classList.remove(className)
    void element.offsetWidth
    element.classList.add(className)
    schedule(hook, () => element.classList.remove(className), duration)
  }

  const gameRoot = hook => hook.el.closest(".mc-game") || document

  const targetSquare = (hook, effect) => {
    const row = Number(effect.row)
    const col = Number(effect.col)
    if (!Number.isInteger(row) || !Number.isInteger(col)) return null
    return gameRoot(hook).querySelector(`[data-r="${row}"][data-c="${col}"]`)
  }

  const anchorImpact = (impact, square) => {
    if (!impact || !square) return false
    const rect = square.getBoundingClientRect()
    impact.style.left = `${rect.left}px`
    impact.style.top = `${rect.top}px`
    impact.style.width = `${rect.width}px`
    impact.style.height = `${rect.height}px`
    return true
  }

  const playCapture = (hook, effect) => {
    const square = targetSquare(hook, effect)
    const impact = hook.el.querySelector("[data-game-effect-capture]")
    if (anchorImpact(impact, square)) restartClass(hook, impact, "mc-effect-active", captureDuration)
    restartClass(hook, square, "mc-effect-capture", captureDuration)
  }

  const playCheck = (hook, effect) => {
    const square = targetSquare(hook, effect)
    const impact = hook.el.querySelector("[data-game-effect-check]")
    if (anchorImpact(impact, square)) restartClass(hook, impact, "mc-effect-active", checkDuration)
    restartClass(hook, square?.closest(".mc-board"), "mc-effect-check-board", checkDuration)
  }

  const playResult = (hook, effect) => {
    const panel = hook.el.querySelector("[data-game-effect-result]")
    if (!panel) return

    const tone = resultTones.has(effect.tone) ? effect.tone : "draw"
    panel.querySelector("[data-game-effect-kicker]").textContent = resultKicker(tone)
    panel.querySelector("[data-game-effect-title]").textContent = String(effect.title || "Partida terminada")
    panel.querySelector("[data-game-effect-detail]").textContent = String(effect.detail || "")
    panel.classList.remove("mc-effect-tone-win", "mc-effect-tone-loss", "mc-effect-tone-draw")
    panel.classList.add(`mc-effect-tone-${tone}`, "mc-effect-visible")
    panel.setAttribute("aria-hidden", "false")

    if (hook.resultTimer) window.clearTimeout(hook.resultTimer)
    hook.resultTimer = schedule(hook, () => {
      panel.classList.remove("mc-effect-visible")
      panel.setAttribute("aria-hidden", "true")
      hook.resultTimer = null
    }, resultDuration)
  }

  const drainUnlocks = () => {
    const hook = state.hook
    if (!hook || hook.unlockActive || state.pendingUnlocks.length === 0) return

    const panel = hook.el.querySelector("[data-game-effect-unlock]")
    if (!panel) return

    const unlock = state.pendingUnlocks.shift()
    hook.unlockActive = true
    hook.activeUnlockId = unlock.id
    panel.querySelector("[data-game-effect-unlock-title]").textContent = unlock.label
    panel.classList.add("mc-effect-visible")
    panel.setAttribute("aria-hidden", "false")

    schedule(hook, () => {
      panel.classList.remove("mc-effect-visible")
      panel.setAttribute("aria-hidden", "true")
      hook.unlockActive = false
      hook.activeUnlockId = null
      drainUnlocks()
    }, unlockDuration)
  }

  const enqueueUnlock = detail => {
    const unlock = normalizeUnlock(detail)
    const duplicate = state.pendingUnlocks.some(item => item.id === unlock.id)
    if (duplicate || state.hook?.activeUnlockId === unlock.id) return

    state.pendingUnlocks.push(unlock)
    drainUnlocks()
  }

  const play = (hook, effect = {}) => {
    if (effect.kind === "capture") playCapture(hook, effect)
    if (effect.kind === "check") playCheck(hook, effect)
    if (effect.kind === "result") playResult(hook, effect)
  }

  if (typeof window.addEventListener === "function") {
    window.addEventListener("mana-chess:cosmetic-unlocked", event => enqueueUnlock(event.detail))
  }

  window.ManaChessGameEffects = Object.freeze({enqueueUnlock, normalizeUnlock, resultKicker})
  window.ManaChessGameEffectsHook = {
    mounted() {
      this.effectTimers = new Set()
      this.resultTimer = null
      this.unlockActive = false
      this.activeUnlockId = null
      state.hook = this
      this.handleEvent("game_effect", effect => play(this, effect))
      drainUnlocks()
    },

    destroyed() {
      this.effectTimers.forEach(timer => window.clearTimeout(timer))
      this.effectTimers.clear()
      if (state.hook === this) state.hook = null
    },
  }
})()
