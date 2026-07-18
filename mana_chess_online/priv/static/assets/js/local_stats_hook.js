// LocalStats Phoenix hook facade. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  window.ManaChessLocalStatsHook = {
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
  }
})()
