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
      this.desktopState = this.desktopSessionController().state(this)
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
        this.cosmeticActionsController().handleUnlock(event, this)
      }
      this.handleSoundAction = event => {
        this.cosmeticActionsController().handleSoundAction(event, this)
      }
      this.handleSkinChoice = event => {
        this.cosmeticActionsController().handleBoardSkinChoice(event, this)
      }
      this.handlePieceSkinChoice = event => {
        this.cosmeticActionsController().handlePieceSkinChoice(event, this)
      }
      this.handlePalettePreset = event => {
        this.cosmeticActionsController().handlePalettePreset(event, this)
      }
      this.handlePaletteReset = event => {
        this.cosmeticActionsController().handlePaletteReset(event, this)
      }
      this.handlePaletteColor = event => {
        this.cosmeticActionsController().handlePaletteColor(event, this)
      }
      this.handleCosmeticPack = event => {
        this.cosmeticActionsController().handleCosmeticPack(event, this)
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
    },

    localStatsController() {
      return window.ManaChessLocalStats
    },

    resultRecordingController() {
      return window.ManaChessResultRecording
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
      this.lastResultKey = this.resultRecordingController().record({
        localStats: this.localStatsController(),
        storageKey: this.storageKey,
        resultKey: this.el.dataset.resultKey,
        outcome: this.el.dataset.resultOutcome,
        lastResultKey: this.lastResultKey,
        onRecorded: event => this.sendDesktopEvent(event.name, event.payload, event.key),
      })
    },

    desktopSessionController() {
      return window.ManaChessDesktopSession
    },

    desktopBridge() {
      return this.desktopSessionController().bridge(this)
    },

    desktopPayload(payload = {}) {
      return this.desktopSessionController().payload(this, payload)
    },

    sendDesktopEvent(name, payload = {}, key = "") {
      this.desktopSessionController().sendEvent(this, name, payload, key)
    },

    emitDesktopView() {
      this.desktopSessionController().emitView(this)
    },

    emitDesktopState(current, previous) {
      this.desktopSessionController().emitState(this, current, previous)
    },

    desktopStatusIsPlaying(status) {
      return this.desktopSessionController().statusIsPlaying(this, status)
    },

    desktopController() {
      return window.ManaChessDesktopBridge
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

    cosmeticActionsController() {
      return window.ManaChessCosmeticActions
    },

    cosmeticFallbackController() {
      return window.ManaChessCosmeticFallback
    },

    renderModularCosmetics() {
      const controller = this.cosmeticsController()
      if (!controller) return false

      controller.render()
      return true
    },

    readCosmeticUnlocks() {
      return this.cosmeticFallbackController().readCosmeticUnlocks(this)
    },

    writeCosmeticUnlocks(unlocks) {
      this.cosmeticFallbackController().writeCosmeticUnlocks(this, unlocks)
    },

    cosmeticUnlocked(id) {
      return this.cosmeticFallbackController().cosmeticUnlocked(this, id)
    },

    unlockCosmetic(id) {
      this.cosmeticFallbackController().unlockCosmetic(this, id)
    },

    cosmeticAllowed(id) {
      return this.cosmeticFallbackController().cosmeticAllowed(this, id)
    },

    cosmeticPackConfig(pack) {
      return this.cosmeticFallbackController().cosmeticPackConfig(pack)
    },

    cosmeticPackUnlocked(pack) {
      return this.cosmeticFallbackController().cosmeticPackUnlocked(this, pack)
    },

    applyCosmeticPack(pack) {
      this.cosmeticFallbackController().applyCosmeticPack(this, pack)
    },

    premiumIdForBoardSkin(skin) {
      return this.cosmeticFallbackController().premiumIdForBoardSkin(skin)
    },

    premiumIdForPieceSkin(skin) {
      return this.cosmeticFallbackController().premiumIdForPieceSkin(skin)
    },

    activateCosmeticControl(control) {
      this.cosmeticFallbackController().activateCosmeticControl(this, control)
    },

    renderCosmetics() {
      this.cosmeticFallbackController().renderCosmetics(this)
    },

    renderCosmeticPacks() {
      this.cosmeticFallbackController().renderCosmeticPacks(this)
    },

    boardSkin() {
      return this.cosmeticFallbackController().boardSkin(this)
    },

    setBoardSkin(skin) {
      this.cosmeticFallbackController().setBoardSkin(this, skin)
    },

    renderBoardSkin() {
      this.cosmeticFallbackController().renderBoardSkin(this)
    },

    pieceSkin() {
      return this.cosmeticFallbackController().pieceSkin(this)
    },

    setPieceSkin(skin) {
      this.cosmeticFallbackController().setPieceSkin(this, skin)
    },

    renderPieceSkin() {
      this.cosmeticFallbackController().renderPieceSkin(this)
    },

    defaultPalette() {
      return this.cosmeticFallbackController().defaultPalette()
    },

    palettePreset(name) {
      return this.cosmeticFallbackController().palettePreset(name)
    },

    paletteEquals(first, second) {
      return this.cosmeticFallbackController().paletteEquals(first, second)
    },

    activePalettePreset(palette) {
      return this.cosmeticFallbackController().activePalettePreset(palette)
    },
    readPalette() {
      return this.cosmeticFallbackController().readPalette(this)
    },

    setPalette(palette) {
      this.cosmeticFallbackController().setPalette(this, palette)
    },

    renderPalette() {
      this.cosmeticFallbackController().renderPalette(this)
    },

    boardPreviewPalette(skin, palette) {
      return this.cosmeticFallbackController().boardPreviewPalette(skin, palette)
    },

    piecePreviewPalette(skin, palette) {
      return this.cosmeticFallbackController().piecePreviewPalette(skin, palette)
    },

    renderCosmeticPreview() {
      this.cosmeticFallbackController().renderCosmeticPreview(this)
    },

    applyPalette(palette) {
      this.cosmeticFallbackController().applyPalette(this, palette)
    },

    readableTextColor(hex) {
      return this.cosmeticFallbackController().readableTextColor(hex)
    },

    hexToRgba(hex, alpha) {
      return this.cosmeticFallbackController().hexToRgba(hex, alpha)
    },

    hexToRgb(hex) {
      return this.cosmeticFallbackController().hexToRgb(hex)
    },

    chatController() {
      return window.ManaChessChat
    },

    renderChatTimes() {
      this.chatController().renderTimes(this.el)
    },

    soundStateController() {
      return window.ManaChessSoundState
    },

    soundState() {
      return this.soundStateController().state(this.el)
    },

    chatScrollState() {
      return this.chatController().scrollState(this.el)
    },

    keepChatAtLatest() {
      this.lastChatScrollState = this.chatController().keepAtLatest(this.el, this.lastChatScrollState)
    },

    scrollChatListsToEnd() {
      this.chatController().scrollListsToEnd(this.el)
    },

    navigationController() {
      return window.ManaChessNavigation
    },

    viewKey() {
      return this.navigationController().viewKey(this.el)
    },

    keepViewInFrame() {
      this.lastViewKey = this.navigationController().keepViewInFrame(this.el, this.lastViewKey)
    },

    keepInitialViewInFrame() {
      this.navigationController().keepInitialViewInFrame(this.el)
    },

    scrollViewToTop() {
      this.navigationController().scrollToTop()
    },

    playChangedSound() {
      const current = this.soundState()
      const previous = this.lastSoundState
      this.lastSoundState = current
      this.emitDesktopState(current, previous)
      const changedSound = this.soundStateController().changedSound(current, previous, this.soundEnabled())

      if (changedSound) this.playSound(changedSound)
    },

    playSound(kind) {
      this.soundController().play(kind, {
        soundKey: this.soundKey,
        volumeKey: this.soundVolumeKey,
      })
    },

    inviteClipboardController() {
      return window.ManaChessInviteClipboard
    },

    copyInvite(button) {
      this.inviteClipboardController().copy(button, {
        copyShareLink: url => this.desktopSessionController().copyShareLink(this, url),
        onCopied: () => this.playSound("copy"),
      })
    },

    fallbackCopy(text, callback) {
      this.inviteClipboardController().fallbackCopy(text, callback)
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
