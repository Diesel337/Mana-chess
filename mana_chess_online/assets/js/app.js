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
      this.localStatsEventsController().bind(this)
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
      this.localStatsEventsController().unbind(this)
    },

    localStatsEventsController() {
      return window.ManaChessLocalStatsEvents
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
      window.ManaChessBoardDrag.mounted(this)
    },

    updated() {
      window.ManaChessBoardDrag.updated(this)
    },

    destroyed() {
      window.ManaChessBoardDrag.destroyed(this)
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
