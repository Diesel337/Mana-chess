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
      window.ManaChessLocalStatsLifecycle.mounted(this)
    },

    updated() {
      window.ManaChessLocalStatsLifecycle.updated(this)
    },

    destroyed() {
      window.ManaChessLocalStatsLifecycle.destroyed(this)
    },

    localStatsEventsController() {
      return window.ManaChessLocalStatsEvents
    },

    statsSessionController() {
      return window.ManaChessStatsSession
    },

    localStatsController() {
      return this.statsSessionController().localStats()
    },

    resultRecordingController() {
      return this.statsSessionController().resultRecording()
    },

    readStats() {
      return this.statsSessionController().read(this)
    },

    writeStats(stats) {
      this.statsSessionController().write(this, stats)
    },

    emptyStats() {
      return this.statsSessionController().empty()
    },

    recordResult() {
      this.statsSessionController().recordResult(this)
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
      this.statsSessionController().render(this)
    },

    soundSessionController() {
      return window.ManaChessSoundSession
    },

    soundEnabled() {
      return this.soundSessionController().enabled(this)
    },

    setSoundEnabled(enabled) {
      this.soundSessionController().setEnabled(this, enabled)
    },

    soundVolume() {
      return this.soundSessionController().volume(this)
    },

    setSoundVolume(value) {
      this.soundSessionController().setVolume(this, value)
    },

    renderSoundToggle() {
      this.soundSessionController().renderToggle(this)
    },

    cosmeticSessionController() {
      return window.ManaChessCosmeticSession
    },

    cosmeticsController() {
      return this.cosmeticSessionController().cosmetics()
    },

    cosmeticActionsController() {
      return this.cosmeticSessionController().actions()
    },

    cosmeticFallbackController() {
      return this.cosmeticSessionController().fallback()
    },

    renderModularCosmetics() {
      return this.cosmeticSessionController().renderModular()
    },

    readCosmeticUnlocks() {
      return this.cosmeticSessionController().readCosmeticUnlocks(this)
    },

    writeCosmeticUnlocks(unlocks) {
      this.cosmeticSessionController().writeCosmeticUnlocks(this, unlocks)
    },

    cosmeticUnlocked(id) {
      return this.cosmeticSessionController().cosmeticUnlocked(this, id)
    },

    unlockCosmetic(id) {
      this.cosmeticSessionController().unlockCosmetic(this, id)
    },

    cosmeticAllowed(id) {
      return this.cosmeticSessionController().cosmeticAllowed(this, id)
    },

    cosmeticPackConfig(pack) {
      return this.cosmeticSessionController().cosmeticPackConfig(pack)
    },

    cosmeticPackUnlocked(pack) {
      return this.cosmeticSessionController().cosmeticPackUnlocked(this, pack)
    },

    applyCosmeticPack(pack) {
      this.cosmeticSessionController().applyCosmeticPack(this, pack)
    },

    premiumIdForBoardSkin(skin) {
      return this.cosmeticSessionController().premiumIdForBoardSkin(skin)
    },

    premiumIdForPieceSkin(skin) {
      return this.cosmeticSessionController().premiumIdForPieceSkin(skin)
    },

    activateCosmeticControl(control) {
      this.cosmeticSessionController().activateCosmeticControl(this, control)
    },

    renderCosmetics() {
      this.cosmeticSessionController().renderCosmetics(this)
    },

    renderCosmeticPacks() {
      this.cosmeticSessionController().renderCosmeticPacks(this)
    },

    boardSkin() {
      return this.cosmeticSessionController().boardSkin(this)
    },

    setBoardSkin(skin) {
      this.cosmeticSessionController().setBoardSkin(this, skin)
    },

    renderBoardSkin() {
      this.cosmeticSessionController().renderBoardSkin(this)
    },

    pieceSkin() {
      return this.cosmeticSessionController().pieceSkin(this)
    },

    setPieceSkin(skin) {
      this.cosmeticSessionController().setPieceSkin(this, skin)
    },

    renderPieceSkin() {
      this.cosmeticSessionController().renderPieceSkin(this)
    },

    defaultPalette() {
      return this.cosmeticSessionController().defaultPalette()
    },

    palettePreset(name) {
      return this.cosmeticSessionController().palettePreset(name)
    },

    paletteEquals(first, second) {
      return this.cosmeticSessionController().paletteEquals(first, second)
    },

    activePalettePreset(palette) {
      return this.cosmeticSessionController().activePalettePreset(palette)
    },
    readPalette() {
      return this.cosmeticSessionController().readPalette(this)
    },

    setPalette(palette) {
      this.cosmeticSessionController().setPalette(this, palette)
    },

    renderPalette() {
      this.cosmeticSessionController().renderPalette(this)
    },

    boardPreviewPalette(skin, palette) {
      return this.cosmeticSessionController().boardPreviewPalette(skin, palette)
    },

    piecePreviewPalette(skin, palette) {
      return this.cosmeticSessionController().piecePreviewPalette(skin, palette)
    },

    renderCosmeticPreview() {
      this.cosmeticSessionController().renderCosmeticPreview(this)
    },

    applyPalette(palette) {
      this.cosmeticSessionController().applyPalette(this, palette)
    },

    readableTextColor(hex) {
      return this.cosmeticSessionController().readableTextColor(hex)
    },

    hexToRgba(hex, alpha) {
      return this.cosmeticSessionController().hexToRgba(hex, alpha)
    },

    hexToRgb(hex) {
      return this.cosmeticSessionController().hexToRgb(hex)
    },

    viewSessionController() {
      return window.ManaChessViewSession
    },

    chatController() {
      return this.viewSessionController().chat()
    },

    renderChatTimes() {
      this.viewSessionController().renderChatTimes(this)
    },

    soundState() {
      return this.soundSessionController().state(this)
    },

    chatScrollState() {
      return this.viewSessionController().chatScrollState(this)
    },

    keepChatAtLatest() {
      this.viewSessionController().keepChatAtLatest(this)
    },

    scrollChatListsToEnd() {
      this.viewSessionController().scrollChatListsToEnd(this)
    },

    navigationController() {
      return this.viewSessionController().navigation()
    },

    viewKey() {
      return this.viewSessionController().viewKey(this)
    },

    keepViewInFrame() {
      this.viewSessionController().keepViewInFrame(this)
    },

    keepInitialViewInFrame() {
      this.viewSessionController().keepInitialViewInFrame(this)
    },

    scrollViewToTop() {
      this.viewSessionController().scrollViewToTop()
    },

    playChangedSound() {
      this.soundSessionController().playChanged(this)
    },

    playSound(kind) {
      this.soundSessionController().play(this, kind)
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
