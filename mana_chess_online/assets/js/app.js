// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/mana_chess_online"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {
  LocalStats: {
    mounted() {
      this.lastResultKey = null
      this.storageKey = "mana-chess-local-stats"
      this.soundKey = "mana-chess-sound-enabled"
      this.soundVolumeKey = "mana-chess-sound-volume"
      this.skinKey = "mana-chess-board-skin"
      this.pieceSkinKey = "mana-chess-piece-skin"
      this.cosmeticUnlockKey = "mana-chess-cosmetic-unlocks"
      this.paletteKey = "mana-chess-custom-palette"
      this.lastSoundState = this.soundState()
      this.lastChatScrollState = null
      this.lastDesktopEventKeys = new Set()
      this.lastDesktopViewKey = null
      this.lastViewKey = this.viewKey()
      this.keepInitialViewInFrame()
      this.handleReset = event => {
        if (!event.target.closest("[data-stats-reset]")) return
        localStorage.removeItem(this.storageKey)
        this.lastResultKey = null
        this.renderStats()
      }
      this.handleInviteCopy = event => {
        const button = event.target.closest("[data-copy-invite]")
        if (!button) return
        event.preventDefault()
        this.copyInvite(button)
      }
      this.handleSoundToggle = event => {
        const button = event.target.closest("[data-sound-toggle]")
        if (!button) return
        event.preventDefault()
        const enabled = !this.soundEnabled()
        this.setSoundEnabled(enabled)
        this.renderSoundToggle()
        if (enabled) this.playSound("ready")
      }
      this.handleSoundVolume = event => {
        const input = event.target.closest("[data-sound-volume]")
        if (!input) return
        this.setSoundVolume(input.value)
        this.renderSoundToggle()
      }
      this.handleCosmeticUnlock = event => {
        const control = event.target.closest("[data-cosmetic-premium], [data-palette-unlock]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return

        const premiumId = control.dataset.cosmeticPremium || "palette:custom"
        if (this.cosmeticUnlocked(premiumId) && !control.matches("[data-palette-unlock]")) return

        event.preventDefault()
        event.stopImmediatePropagation()
        this.unlockCosmetic(premiumId)
        this.activateCosmeticControl(control)
        this.renderCosmetics()
        if (this.soundEnabled()) this.playSound("skin")
      }
      this.handleSoundAction = event => {
        const control = event.target.closest("[data-sound-action]")
        if (!control || control.disabled) return
        if (control.matches("[data-piece-skin-choice]")) {
          if (this.cosmeticsController()) {
            if (this.soundEnabled()) this.playSound(control.dataset.soundAction || "skin")
            return
          }

          event.preventDefault()
          event.stopImmediatePropagation()
          this.setPieceSkin(control.dataset.pieceSkinChoice)
          this.renderPieceSkin()
          if (this.soundEnabled()) this.playSound("skin")
          return
        }
        if (!this.soundEnabled()) return
        this.playSound(control.dataset.soundAction || "tap")
      }
      this.handleSkinChoice = event => {
        const control = event.target.closest("[data-board-skin-choice]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return

        event.preventDefault()
        this.setBoardSkin(control.dataset.boardSkinChoice)
        this.renderBoardSkin()
        this.playSound("skin")
      }
      this.handlePieceSkinChoice = event => {
        const control = event.target.closest("[data-piece-skin-choice]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return

        event.preventDefault()
        this.setPieceSkin(control.dataset.pieceSkinChoice)
        this.renderPieceSkin()
        this.playSound("skin")
      }
      this.handlePalettePreset = event => {
        const control = event.target.closest("[data-palette-preset]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return
        if (!this.cosmeticUnlocked("palette:custom")) return

        event.preventDefault()
        this.setPalette(this.palettePreset(control.dataset.palettePreset))
        this.setBoardSkin("custom")
        this.setPieceSkin("custom")
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
        this.renderCosmetics()
        this.playSound("skin")
      }
      this.handlePaletteReset = event => {
        const control = event.target.closest("[data-palette-reset]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return
        if (!this.cosmeticUnlocked("palette:custom")) return

        event.preventDefault()
        this.setPalette(this.defaultPalette())
        this.setBoardSkin("custom")
        this.setPieceSkin("custom")
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
        this.renderCosmetics()
        this.playSound("skin")
      }
      this.handlePaletteColor = event => {
        const input = event.target.closest("[data-palette-color]")
        if (!input || input.disabled) return
        if (this.cosmeticsController()) return
        if (!this.cosmeticUnlocked("palette:custom")) return

        this.setPalette({...this.readPalette(), [input.dataset.paletteColor]: input.value})
        this.setBoardSkin("custom")
        this.setPieceSkin("custom")
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
        this.renderCosmetics()
      }
      this.handleCosmeticPack = event => {
        const control = event.target.closest("[data-cosmetic-pack]")
        if (!control || control.disabled) return
        if (this.cosmeticsController()) return

        event.preventDefault()
        this.applyCosmeticPack(control.dataset.cosmeticPack)
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderCosmetics()
      }
      this.handleViewJump = event => {
        if (!event.target.closest('[phx-click="start_practice"], [phx-click="start_tutorial"], [phx-click="sit_anywhere"], [phx-click="create_private"], [phx-click="leave"], [phx-click="sit"]')) return
        this.scrollViewToTop()
      }
      this.el.addEventListener("click", this.handleReset)
      this.el.addEventListener("click", this.handleInviteCopy)
      this.el.addEventListener("click", this.handleSoundToggle)
      this.el.addEventListener("input", this.handleSoundVolume)
      this.el.addEventListener("change", this.handleSoundVolume)
      this.el.addEventListener("click", this.handleCosmeticUnlock)
      this.el.addEventListener("click", this.handleSoundAction)
      this.el.addEventListener("click", this.handleSkinChoice)
      this.el.addEventListener("click", this.handlePieceSkinChoice)
      this.el.addEventListener("click", this.handlePalettePreset)
      this.el.addEventListener("click", this.handlePaletteReset)
      this.el.addEventListener("input", this.handlePaletteColor)
      this.el.addEventListener("change", this.handlePaletteColor)
      this.el.addEventListener("click", this.handleCosmeticPack)
      this.el.addEventListener("click", this.handleViewJump, true)
      this.recordResult()
      this.renderStats()
      this.renderSoundToggle()
      if (!this.renderModularCosmetics()) {
        this.renderCosmetics()
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
      }
      this.renderChatTimes()
      this.keepChatAtLatest()
      this.emitDesktopView()
      this.emitDesktopState(this.soundState(), null)
    },

    updated() {
      this.recordResult()
      this.renderStats()
      this.renderSoundToggle()
      if (!this.renderModularCosmetics()) {
        this.renderCosmetics()
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
      }
      this.renderChatTimes()
      this.keepViewInFrame()
      this.emitDesktopView()
      this.keepChatAtLatest()
      this.playChangedSound()
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleReset)
      this.el.removeEventListener("click", this.handleInviteCopy)
      this.el.removeEventListener("click", this.handleSoundToggle)
      this.el.removeEventListener("input", this.handleSoundVolume)
      this.el.removeEventListener("change", this.handleSoundVolume)
      this.el.removeEventListener("click", this.handleCosmeticUnlock)
      this.el.removeEventListener("click", this.handleSoundAction)
      this.el.removeEventListener("click", this.handleSkinChoice)
      this.el.removeEventListener("click", this.handlePieceSkinChoice)
      this.el.removeEventListener("click", this.handlePalettePreset)
      this.el.removeEventListener("click", this.handlePaletteReset)
      this.el.removeEventListener("input", this.handlePaletteColor)
      this.el.removeEventListener("change", this.handlePaletteColor)
      this.el.removeEventListener("click", this.handleCosmeticPack)
      this.el.removeEventListener("click", this.handleViewJump, true)
    },

    localStatsController() {
      return window.ManaChessLocalStats
    },

    readStats() {
      return this.localStatsController().read(this.storageKey)
    },

    writeStats(stats) {
      this.localStatsController().write(this.storageKey, stats)
    },

    emptyStats() {
      return this.localStatsController().empty()
    },

    recordResult() {
      const result = this.localStatsController().record({
        storageKey: this.storageKey,
        resultKey: this.el.dataset.resultKey,
        outcome: this.el.dataset.resultOutcome,
        lastResultKey: this.lastResultKey,
      })

      this.lastResultKey = result.lastResultKey
      if (result.recorded) {
        this.sendDesktopEvent(
          "match.finished",
          {result: result.outcome, resultKey: result.resultKey},
          `match.finished:${result.resultKey}`
        )
      }
    },

    desktopBridge() {
      const bridge = window.ManaChessDesktop
      return bridge && typeof bridge.sendEvent === "function" ? bridge : null
    },

    desktopPayload(payload = {}) {
      const state = this.soundState()
      return {
        path: window.location.pathname,
        screen: state.gameId ? "game" : "lobby",
        view: this.viewKey(),
        gameId: state.gameId,
        status: state.status,
        ...payload,
      }
    },

    sendDesktopEvent(name, payload = {}, key = "") {
      const bridge = this.desktopBridge()
      if (!bridge) return

      const eventKey = key || `${name}:${payload.gameId || ""}:${payload.status || ""}:${payload.result || ""}`
      if (eventKey && this.lastDesktopEventKeys.has(eventKey)) return

      if (eventKey) {
        this.lastDesktopEventKeys.add(eventKey)
        if (this.lastDesktopEventKeys.size > 80) {
          this.lastDesktopEventKeys = new Set([...this.lastDesktopEventKeys].slice(-40))
        }
      }

      try {
        bridge.sendEvent(name, this.desktopPayload(payload))
      } catch (_error) {
      }
    },

    emitDesktopView() {
      const state = this.soundState()
      const screen = state.gameId ? "game" : "lobby"
      const key = `${screen}:${state.gameId || "lobby"}:${window.location.pathname}`
      if (key === this.lastDesktopViewKey) return

      this.lastDesktopViewKey = key
      this.sendDesktopEvent("screen.viewed", {screen}, `screen.viewed:${key}`)
    },

    emitDesktopState(current, previous) {
      if (!current.gameId) return

      if (!previous || current.gameId !== previous.gameId) {
        this.sendDesktopEvent("match.opened", {}, `match.opened:${current.gameId}`)
      }

      if (!current.status || (previous && current.status === previous.status)) return

      this.sendDesktopEvent(
        "match.status_changed",
        {previousStatus: previous?.status || ""},
        `match.status_changed:${current.gameId}:${current.status}`
      )

      if (this.desktopStatusIsPlaying(current.status) && !this.desktopStatusIsPlaying(previous?.status || "")) {
        this.sendDesktopEvent("match.started", {}, `match.started:${current.gameId}`)
      }
    },

    desktopStatusIsPlaying(status) {
      return status === ":playing" || status.includes("starting") || status.includes("promotion")
    },

    renderStats() {
      this.localStatsController().render(this.el, this.storageKey)
    },

    soundController() {
      return window.ManaChessSound
    },

    soundEnabled() {
      return this.soundController().enabled(this.soundKey)
    },

    setSoundEnabled(enabled) {
      this.soundController().setEnabled(this.soundKey, enabled)
    },

    soundVolume() {
      return this.soundController().volume(this.soundVolumeKey)
    },

    setSoundVolume(value) {
      this.soundController().setVolume(this.soundVolumeKey, value)
    },

    renderSoundToggle() {
      this.soundController().render(this.el, {
        soundKey: this.soundKey,
        volumeKey: this.soundVolumeKey,
      })
    },

    cosmeticsController() {
      return window.ManaChessCosmetics || null
    },

    renderModularCosmetics() {
      const controller = this.cosmeticsController()
      if (!controller) return false

      controller.render()
      return true
    },

    readCosmeticUnlocks() {
      try {
        return JSON.parse(localStorage.getItem(this.cosmeticUnlockKey)) || []
      } catch (_error) {
        return []
      }
    },

    writeCosmeticUnlocks(unlocks) {
      localStorage.setItem(this.cosmeticUnlockKey, JSON.stringify([...new Set(unlocks)]))
    },

    cosmeticUnlocked(id) {
      return this.readCosmeticUnlocks().includes(id)
    },

    unlockCosmetic(id) {
      const unlocks = this.readCosmeticUnlocks()
      const next = [...unlocks, id]

      if (id === "board:custom" || id === "piece:custom" || id === "palette:custom") {
        next.push("board:custom", "piece:custom", "palette:custom")
      }

      this.writeCosmeticUnlocks(next)
    },

    cosmeticAllowed(id) {
      return !id || this.cosmeticUnlocked(id)
    },

    cosmeticPackConfig(pack) {
      const packs = {
        classic: {board: "classic", piece: "classic", included: true},
        mana: {board: "gilded", piece: "runes", included: true},
        arcane: {board: "arcane", piece: "crystal", unlocks: ["board:arcane", "piece:crystal"]},
      }

      return packs[pack] || null
    },

    cosmeticPackUnlocked(pack) {
      const config = this.cosmeticPackConfig(pack)
      if (!config) return false
      if (config.included) return true
      return (config.unlocks || []).every(id => this.cosmeticUnlocked(id))
    },

    applyCosmeticPack(pack) {
      const config = this.cosmeticPackConfig(pack)
      if (!config) return

      ;(config.unlocks || []).forEach(id => this.unlockCosmetic(id))
      this.setBoardSkin(config.board)
      this.setPieceSkin(config.piece)
    },

    premiumIdForBoardSkin(skin) {
      return skin === "arcane" || skin === "custom" ? `board:${skin}` : null
    },

    premiumIdForPieceSkin(skin) {
      return skin === "crystal" || skin === "custom" ? `piece:${skin}` : null
    },

    activateCosmeticControl(control) {
      if (control.matches("[data-palette-unlock]")) {
        this.setBoardSkin("custom")
        this.setPieceSkin("custom")
        this.renderBoardSkin()
        this.renderPieceSkin()
        this.renderPalette()
        return
      }

      if (control.dataset.boardSkinChoice) {
        this.setBoardSkin(control.dataset.boardSkinChoice)
        this.renderBoardSkin()
      }

      if (control.dataset.pieceSkinChoice) {
        this.setPieceSkin(control.dataset.pieceSkinChoice)
        this.renderPieceSkin()
      }
    },

    renderCosmetics() {
      this.el.querySelectorAll("[data-cosmetic-premium]").forEach(control => {
        const unlocked = this.cosmeticUnlocked(control.dataset.cosmeticPremium)
        control.classList.toggle("mc-skin-locked", !unlocked)
        control.classList.toggle("mc-skin-unlocked", unlocked)
        control.setAttribute("aria-disabled", "false")
        control.title = unlocked ? "Cosmetico desbloqueado localmente" : "Premium proximamente; probar localmente"
        control.querySelectorAll("[data-cosmetic-status]").forEach(status => {
          status.textContent = unlocked ? "Local" : "Premium proximamente"
          status.dataset.cosmeticState = unlocked ? "local" : "premium"
        })
      })

      this.el.querySelectorAll("[data-palette-editor]").forEach(editor => {
        const unlocked = this.cosmeticUnlocked("palette:custom")
        editor.classList.toggle("is-locked", !unlocked)
        editor.classList.toggle("is-unlocked", unlocked)
        editor.querySelectorAll("[data-palette-status]").forEach(status => {
          status.textContent = unlocked ? "Local" : "Premium proximamente"
          status.dataset.paletteState = unlocked ? "local" : "premium"
        })
        editor.querySelectorAll("[data-palette-unlock]").forEach(control => {
          control.setAttribute("aria-disabled", "false")
        })
        editor.querySelectorAll("[data-palette-color]").forEach(control => {
          control.disabled = !unlocked
        })
      })

      const paletteUnlocked = this.cosmeticUnlocked("palette:custom")
      this.el.querySelectorAll("[data-palette-preset], [data-palette-reset], [data-palette-color]").forEach(control => {
        control.disabled = !paletteUnlocked
      })

      this.renderCosmeticPacks()
    },

    renderCosmeticPacks() {
      const board = this.boardSkin()
      const piece = this.pieceSkin()

      this.el.querySelectorAll("[data-cosmetic-pack]").forEach(control => {
        const pack = control.dataset.cosmeticPack
        const config = this.cosmeticPackConfig(pack)
        if (!config) return

        const unlocked = this.cosmeticPackUnlocked(pack)
        const selected = unlocked && config.board === board && config.piece === piece
        control.classList.toggle("mc-skin-selected", selected)
        control.classList.toggle("mc-skin-locked", !unlocked)
        control.classList.toggle("mc-skin-unlocked", unlocked && !config.included)
        control.setAttribute("aria-pressed", selected ? "true" : "false")
        control.setAttribute("aria-disabled", "false")
        control.title = unlocked ? "Pack disponible localmente" : "Premium proximamente; probar localmente"
        control.querySelectorAll("[data-cosmetic-pack-status]").forEach(status => {
          status.textContent = config.included ? "Incluido" : unlocked ? "Local" : "Premium proximamente"
          status.dataset.cosmeticState = config.included ? "included" : unlocked ? "local" : "premium"
        })
      })
    },

    boardSkin() {
      const skin = localStorage.getItem(this.skinKey)
      if (skin === "mana") return "gilded"
      if (this.cosmeticAllowed(this.premiumIdForBoardSkin(skin))) {
        return ["classic", "arcane", "gilded", "custom"].includes(skin) ? skin : "classic"
      }
      return "classic"
    },

    setBoardSkin(skin) {
      if (!["classic", "arcane", "gilded", "custom"].includes(skin)) return
      if (!this.cosmeticAllowed(this.premiumIdForBoardSkin(skin))) return
      localStorage.setItem(this.skinKey, skin)
    },

    renderBoardSkin() {
      const skin = this.boardSkin()

      this.el.querySelectorAll("[data-board-skin-target]").forEach(node => {
        node.dataset.boardSkin = skin
      })

      this.el.querySelectorAll("[data-board-skin-choice]").forEach(button => {
        const selected = button.dataset.boardSkinChoice === skin
        button.classList.toggle("mc-skin-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })

      this.renderCosmeticPreview()
    },

    pieceSkin() {
      const skin = localStorage.getItem(this.pieceSkinKey)
      if (this.cosmeticAllowed(this.premiumIdForPieceSkin(skin))) {
        return ["classic", "runes", "crystal", "custom"].includes(skin) ? skin : "classic"
      }
      return "classic"
    },

    setPieceSkin(skin) {
      if (!["classic", "runes", "crystal", "custom"].includes(skin)) return
      if (!this.cosmeticAllowed(this.premiumIdForPieceSkin(skin))) return
      localStorage.setItem(this.pieceSkinKey, skin)
    },

    renderPieceSkin() {
      const skin = this.pieceSkin()
      this.el.dataset.pieceSkin = skin
      this.el.classList.toggle("mc-piece-skin-classic", skin === "classic")
      this.el.classList.toggle("mc-piece-skin-runes", skin === "runes")
      this.el.classList.toggle("mc-piece-skin-crystal", skin === "crystal")
      this.el.classList.toggle("mc-piece-skin-custom", skin === "custom")
      document.documentElement.dataset.pieceSkin = skin

      this.el.querySelectorAll("[data-piece-skin-choice]").forEach(button => {
        const selected = button.dataset.pieceSkinChoice === skin
        button.classList.toggle("mc-skin-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })

      this.renderCosmeticPreview()
    },

    defaultPalette() {
      return {
        boardLight: "#d9c58f",
        boardDark: "#243a31",
        pieceWhite: "#f6f1df",
        pieceBlack: "#241745",
      }
    },

    palettePreset(name) {
      const presets = {
        midnight: {boardLight: "#8067c9", boardDark: "#151020", pieceWhite: "#f7f2ff", pieceBlack: "#241745"},
        emerald: {boardLight: "#8bd9bd", boardDark: "#17342b", pieceWhite: "#f5f9de", pieceBlack: "#0b2c24"},
        frost: {boardLight: "#d9f0ff", boardDark: "#22354f", pieceWhite: "#ffffff", pieceBlack: "#2f5e8f"},
        solar: {boardLight: "#f2c15f", boardDark: "#174a45", pieceWhite: "#fff4d2", pieceBlack: "#31204f"},
        ruby: {boardLight: "#f0b7a6", boardDark: "#3b141c", pieceWhite: "#fff0ea", pieceBlack: "#4c0f23"},
      }

      return presets[name] || this.defaultPalette()
    },

    paletteEquals(first, second) {
      return Object.keys(this.defaultPalette()).every(key => {
        const a = (first[key] || "").toLowerCase()
        const b = (second[key] || "").toLowerCase()
        return a === b
      })
    },

    activePalettePreset(palette) {
      const normalized = {...this.defaultPalette(), ...palette}
      if (this.paletteEquals(normalized, this.defaultPalette())) return "base"
      return ["midnight", "emerald", "frost", "solar", "ruby"].find(name => this.paletteEquals(normalized, this.palettePreset(name))) || null
    },
    readPalette() {
      try {
        return {...this.defaultPalette(), ...(JSON.parse(localStorage.getItem(this.paletteKey)) || {})}
      } catch (_error) {
        return this.defaultPalette()
      }
    },

    setPalette(palette) {
      localStorage.setItem(this.paletteKey, JSON.stringify({...this.defaultPalette(), ...palette}))
    },

    renderPalette() {
      const palette = this.readPalette()
      this.applyPalette(palette)

      this.el.querySelectorAll("[data-palette-color]").forEach(input => {
        if (palette[input.dataset.paletteColor]) input.value = palette[input.dataset.paletteColor]
      })
      const activePreset = this.activePalettePreset(palette)
      this.el.querySelectorAll("[data-palette-reset]").forEach(button => {
        const selected = activePreset === "base"
        button.classList.toggle("mc-palette-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })
      this.el.querySelectorAll("[data-palette-preset]").forEach(button => {
        const selected = button.dataset.palettePreset === activePreset
        button.classList.toggle("mc-palette-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })
      this.renderCosmeticPreview()
    },

    boardPreviewPalette(skin, palette) {
      const palettes = {
        classic: {frame: "#f7f2e8", light: "#f3eee2", dark: "#171817"},
        gilded: {frame: "#fff0b6", light: "#f4d477", dark: "#6e3b1f"},
        arcane: {frame: "#8b6bea", light: "#8bd9bd", dark: "#241745"},
        custom: {frame: palette.boardLight, light: palette.boardLight, dark: palette.boardDark},
      }

      return palettes[skin] || palettes.classic
    },

    piecePreviewPalette(skin, palette) {
      const palettes = {
        classic: {
          frame: "#e6bd68",
          white: "#f7ebce",
          black: "#171a17",
          whiteText: "#171a12",
          blackText: "#7c5bd6",
          whiteGlow: "rgba(247, 235, 206, .36)",
          blackGlow: "rgba(124, 91, 214, .44)",
        },
        runes: {
          frame: "#8bd9bd",
          white: "#8bd9bd",
          black: "#120b22",
          whiteText: "#03251d",
          blackText: "#c7b3ff",
          whiteGlow: "rgba(139, 217, 189, .48)",
          blackGlow: "rgba(168, 132, 255, .52)",
        },
        crystal: {
          frame: "#fff0b6",
          white: "#c7d2ff",
          black: "#101623",
          whiteText: "#101629",
          blackText: "#fff0b6",
          whiteGlow: "rgba(109, 143, 255, .48)",
          blackGlow: "rgba(255, 240, 182, .5)",
        },
        custom: {
          frame: palette.boardLight,
          white: palette.pieceWhite,
          black: palette.pieceBlack,
          whiteText: this.readableTextColor(palette.pieceWhite),
          blackText: this.readableTextColor(palette.pieceBlack),
          whiteGlow: this.hexToRgba(palette.pieceWhite, 0.42),
          blackGlow: this.hexToRgba(palette.pieceBlack, 0.5),
        },
      }

      return palettes[skin] || palettes.classic
    },

    renderCosmeticPreview() {
      const palette = this.readPalette()
      const boardSkin = this.boardSkin()
      const pieceSkin = this.pieceSkin()
      const board = this.boardPreviewPalette(boardSkin, palette)
      const piece = this.piecePreviewPalette(pieceSkin, palette)
      const vars = {
        "--mc-preview-board-frame": board.frame,
        "--mc-preview-board-light": board.light,
        "--mc-preview-board-dark": board.dark,
        "--mc-preview-piece-frame": piece.frame,
        "--mc-preview-piece-white": piece.white,
        "--mc-preview-piece-black": piece.black,
        "--mc-preview-piece-white-text": piece.whiteText,
        "--mc-preview-piece-black-text": piece.blackText,
        "--mc-preview-piece-white-glow": piece.whiteGlow,
        "--mc-preview-piece-black-glow": piece.blackGlow,
      }

      this.el.querySelectorAll("[data-palette-live-preview]").forEach(preview => {
        preview.dataset.boardSkin = boardSkin
        preview.dataset.pieceSkin = pieceSkin
        for (const [name, value] of Object.entries(vars)) {
          preview.style.setProperty(name, value)
        }
      })
    },

    applyPalette(palette) {
      const root = document.documentElement
      const vars = {
        "--mc-custom-board-light": palette.boardLight,
        "--mc-custom-board-dark": palette.boardDark,
        "--mc-custom-board-frame": palette.boardLight,
        "--mc-custom-piece-white": palette.pieceWhite,
        "--mc-custom-piece-black": palette.pieceBlack,
        "--mc-custom-piece-white-text": this.readableTextColor(palette.pieceWhite),
        "--mc-custom-piece-black-text": this.readableTextColor(palette.pieceBlack),
        "--mc-custom-piece-white-glow": this.hexToRgba(palette.pieceWhite, 0.42),
        "--mc-custom-piece-black-glow": this.hexToRgba(palette.pieceBlack, 0.5),
      }

      for (const [name, value] of Object.entries(vars)) {
        root.style.setProperty(name, value)
        this.el.style.setProperty(name, value)
      }
    },

    readableTextColor(hex) {
      const rgb = this.hexToRgb(hex)
      if (!rgb) return "#10140f"
      const luminance = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255
      return luminance > 0.56 ? "#10140f" : "#fff8dc"
    },

    hexToRgba(hex, alpha) {
      const rgb = this.hexToRgb(hex)
      if (!rgb) return `rgba(255, 255, 255, ${alpha})`
      return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`
    },

    hexToRgb(hex) {
      const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || "")
      if (!match) return null
      return {
        r: Number.parseInt(match[1], 16),
        g: Number.parseInt(match[2], 16),
        b: Number.parseInt(match[3], 16),
      }
    },

    renderChatTimes() {
      this.el.querySelectorAll("[data-chat-time]").forEach(node => {
        if (node.dataset.chatTimeRendered === node.dataset.chatTime) return

        const seconds = Number.parseInt(node.dataset.chatTime || "", 10)
        if (Number.isNaN(seconds)) return

        node.textContent = new Date(seconds * 1000).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit", hour12: false})
        node.dataset.chatTimeRendered = node.dataset.chatTime
      })
    },

    soundState() {
      return {
        gameId: this.el.dataset.soundGameId || "",
        status: this.el.dataset.soundStatus || "",
        logCount: Number.parseInt(this.el.dataset.soundLogCount || "0", 10),
        logKind: this.el.dataset.soundLogKind || "",
        chatCount: Number.parseInt(this.el.dataset.soundChatCount || "0", 10),
        alert: this.el.dataset.soundAlert || "",
        alertKind: this.el.dataset.soundAlertKind || "",
        resultKey: this.el.dataset.resultKey || "",
        result: this.el.dataset.resultOutcome || "",
      }
    },

    viewKey() {
      return this.el.dataset.soundGameId || "lobby"
    },

    chatScrollState() {
      return {
        gameId: this.el.dataset.soundGameId || "",
        chatCount: Number.parseInt(this.el.dataset.soundChatCount || "0", 10),
      }
    },

    keepChatAtLatest() {
      const current = this.chatScrollState()
      const previous = this.lastChatScrollState
      this.lastChatScrollState = current

      if (!current.gameId) return
      if (previous && current.gameId === previous.gameId && current.chatCount <= previous.chatCount) return

      this.scrollChatListsToEnd()
    },

    scrollChatListsToEnd() {
      const scroll = () => {
        this.el.querySelectorAll("[data-chat-list]").forEach(list => {
          list.scrollTop = list.scrollHeight
        })
      }
      window.requestAnimationFrame(scroll)
      window.setTimeout(scroll, 80)
    },

    keepViewInFrame() {
      const current = this.viewKey()
      if (current === this.lastViewKey) return

      this.lastViewKey = current
      this.scrollViewToTop()
    },

    keepInitialViewInFrame() {
      if (this.viewKey() !== "lobby") this.scrollViewToTop()
    },

    scrollViewToTop() {
      window.requestAnimationFrame(() => window.scrollTo(0, 0))
      window.setTimeout(() => window.scrollTo(0, 0), 80)
      window.setTimeout(() => window.scrollTo(0, 0), 260)
    },

    playChangedSound() {
      const current = this.soundState()
      const previous = this.lastSoundState
      this.lastSoundState = current
      this.emitDesktopState(current, previous)

      if (!previous || !this.soundEnabled()) return

      if (current.result && current.resultKey && current.resultKey !== previous.resultKey) {
        this.playSound(current.result === "win" ? "win" : current.result === "loss" ? "loss" : "draw")
        return
      }

      if (current.alert && current.alert !== previous.alert) {
        this.playSound(current.alertKind === "check" ? "check" : current.alertKind === "reset" ? "reset" : "alert")
        return
      }

      if (current.gameId && current.gameId === previous.gameId && current.logCount > previous.logCount) {
        this.playSound(current.logKind === "capture" ? "capture" : current.logKind === "alert" ? "alert" : "move")
        return
      }

      if (current.gameId && current.gameId === previous.gameId && current.chatCount > previous.chatCount) {
        this.playSound("chat")
        return
      }

      if (current.status && current.status !== previous.status) {
        this.playSound("state")
      }
    },

    playSound(kind) {
      this.soundController().play(kind, {
        soundKey: this.soundKey,
        volumeKey: this.soundVolumeKey,
      })
    },

    copyInvite(button) {
      const inviteUrl = new URL(button.dataset.copyInvite, window.location.origin).toString()
      const originalHtml = button.innerHTML
      const copiedLabel = button.dataset.copySuccess || "Copiado"
      const markCopied = () => {
        button.dataset.copied = "true"
        button.textContent = copiedLabel
        this.playSound("copy")
        window.clearTimeout(button.copyInviteTimer)
        button.copyInviteTimer = window.setTimeout(() => {
          button.innerHTML = originalHtml
          delete button.dataset.copied
        }, 1400)
      }

      const desktop = this.desktopBridge()
      if (desktop && typeof desktop.copyShareLink === "function") {
        desktop.copyShareLink(inviteUrl).then(markCopied).catch(() => {
          this.fallbackCopy(inviteUrl, markCopied)
        })
      } else if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(inviteUrl).then(markCopied).catch(() => {
          this.fallbackCopy(inviteUrl, markCopied)
        })
      } else {
        this.fallbackCopy(inviteUrl, markCopied)
      }
    },

    fallbackCopy(text, callback) {
      const field = document.createElement("textarea")
      field.value = text
      field.setAttribute("readonly", "")
      field.style.position = "fixed"
      field.style.top = "-1000px"
      field.style.opacity = "0"
      document.body.appendChild(field)
      field.select()

      try {
        document.execCommand("copy")
        callback()
      } finally {
        field.remove()
      }
    },
  },

  BoardDrag: {
    mounted() {
      this.drag = null
      this.suppressClick = false

      this.el.addEventListener("pointerdown", event => {
        const square = event.target.closest(".mc-square")
        const piece = square && square.querySelector(".mc-piece:not(:empty)")

        this.clearLegalPreview()
        this.clearBlockedPreview()
        if (!square || !piece) return

        const legalMoves = this.legalMoves(square)
        if (legalMoves.length === 0) {
          this.flashBlockedSquare(square)
          return
        }

        this.showLegalPreview(square, legalMoves)

        this.drag = {
          fromR: square.dataset.r,
          fromC: square.dataset.c,
          legalMoves,
          pointerId: event.pointerId,
          startX: event.clientX,
          startY: event.clientY,
          square,
          piece,
          ghost: null,
          moved: false,
        }

        square.setPointerCapture(event.pointerId)
      })

      this.el.addEventListener("pointermove", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return

        const delta = Math.abs(event.clientX - this.drag.startX) + Math.abs(event.clientY - this.drag.startY)

        if (delta > 8) {
          this.drag.moved = true
          this.el.classList.add("mc-dragging")
          this.drag.square.classList.add("mc-drag-source")
          if (!this.drag.ghost) {
            this.drag.ghost = this.createDragGhost(this.drag.piece, event.clientX, event.clientY)
          }
        }

        if (this.drag.ghost) this.moveDragGhost(this.drag.ghost, event.clientX, event.clientY)
      })

      this.el.addEventListener("pointerup", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return

        const drag = this.drag
        this.drag = null
        this.clearDragVisuals(drag)

        if (!drag.moved) return
        this.suppressClick = true
        this.clearLegalPreview()

        const target = document.elementFromPoint(event.clientX, event.clientY)
        const square = target && target.closest(".mc-square")

        if (!square) {
          this.flashBlockedSquare(drag.square)
          this.pushEvent("drag_invalid", {
            from_r: drag.fromR,
            from_c: drag.fromC,
          })
          return
        }

        if (!this.legalTarget(drag, square)) {
          this.flashBlockedSquare(square)
        }

        this.pushEvent("drag_move", {
          from_r: drag.fromR,
          from_c: drag.fromC,
          to_r: square.dataset.r,
          to_c: square.dataset.c,
        })
      })

      this.el.addEventListener("pointercancel", _event => {
        const drag = this.drag
        this.drag = null
        this.clearDragVisuals(drag)
        this.clearLegalPreview()
        this.clearBlockedPreview()
      })

      this.el.addEventListener("click", event => {
        if (this.suppressClick) {
          this.suppressClick = false
          event.preventDefault()
          event.stopPropagation()
        }
      }, true)
    },

    updated() {
      this.clearLegalPreview()
      this.clearBlockedPreview()
    },

    destroyed() {
      this.clearLegalPreview()
      this.clearBlockedPreview()
    },

    legalMoves(square) {
      return (square.dataset.legalMoves || "").trim().split(/\s+/).filter(Boolean)
    },

    legalTarget(drag, square) {
      return drag.legalMoves.includes(`${square.dataset.r},${square.dataset.c}`)
    },

    showLegalPreview(square, moves = this.legalMoves(square)) {
      if (moves.length === 0) return

      square.classList.add("mc-selected", "mc-client-selected")

      moves.forEach(move => {
        const [r, c] = move.split(",")
        const target = this.el.querySelector(`.mc-square[data-r="${r}"][data-c="${c}"]`)
        if (target) target.classList.add("mc-valid", "mc-client-valid")
      })
    },

    clearLegalPreview() {
      this.el.querySelectorAll(".mc-client-selected").forEach(square => {
        square.classList.remove("mc-selected", "mc-client-selected")
      })
      this.el.querySelectorAll(".mc-client-valid").forEach(square => {
        square.classList.remove("mc-valid", "mc-client-valid")
      })
    },

    flashBlockedSquare(square) {
      if (!square) return
      square.classList.remove("mc-client-blocked")
      void square.offsetWidth
      square.classList.add("mc-client-blocked")
      window.clearTimeout(square.blockedPreviewTimer)
      square.blockedPreviewTimer = window.setTimeout(() => {
        square.classList.remove("mc-client-blocked")
      }, 620)
    },

    clearBlockedPreview() {
      this.el.querySelectorAll(".mc-client-blocked").forEach(square => {
        window.clearTimeout(square.blockedPreviewTimer)
        square.classList.remove("mc-client-blocked")
      })
    },

    createDragGhost(piece, x, y) {
      const rect = piece.getBoundingClientRect()
      const ghost = piece.cloneNode(true)
      ghost.classList.add("mc-drag-ghost")
      ghost.style.width = `${rect.width}px`
      ghost.style.height = `${rect.height}px`
      document.body.appendChild(ghost)
      this.moveDragGhost(ghost, x, y)
      return ghost
    },

    moveDragGhost(ghost, x, y) {
      ghost.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -58%) scale(1.08)`
    },

    clearDragVisuals(drag) {
      this.el.classList.remove("mc-dragging")
      if (!drag) return
      drag.square && drag.square.classList.remove("mc-drag-source")
      drag.ghost && drag.ghost.remove()
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
