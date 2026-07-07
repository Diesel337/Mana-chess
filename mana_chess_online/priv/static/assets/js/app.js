const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
  LocalStats: {
    mounted() {
      window.ManaChessLocalStatsLifecycle.mounted(this);
    },

    updated() {
      window.ManaChessLocalStatsLifecycle.updated(this);
    },

    destroyed() {
      window.ManaChessLocalStatsLifecycle.destroyed(this);
    },

    localStatsEventsController() {
      return window.ManaChessLocalStatsEvents;
    },

    localStatsController() {
      return window.ManaChessLocalStats;
    },

    resultRecordingController() {
      return window.ManaChessResultRecording;
    },

    readStats() {
      return this.localStatsController().read(this.storageKey);
    },

    writeStats(stats) {
      this.localStatsController().write(this.storageKey, stats);
    },

    emptyStats() {
      return this.localStatsController().empty();
    },

    recordResult() {
      this.lastResultKey = this.resultRecordingController().record({
        localStats: this.localStatsController(),
        storageKey: this.storageKey,
        resultKey: this.el.dataset.resultKey,
        outcome: this.el.dataset.resultOutcome,
        lastResultKey: this.lastResultKey,
        onRecorded: event => this.sendDesktopEvent(event.name, event.payload, event.key)
      });
    },

    renderStats() {
      this.localStatsController().render(this.el, this.storageKey);
    },

    desktopSessionController() {
      return window.ManaChessDesktopSession;
    },

    sendDesktopEvent(name, payload = {}, key = "") {
      this.desktopSessionController().sendEvent(this, name, payload, key);
    },

    emitDesktopView() {
      this.desktopSessionController().emitView(this);
    },

    emitDesktopState(current, previous) {
      this.desktopSessionController().emitState(this, current, previous);
    },

    desktopController() {
      return window.ManaChessDesktopBridge;
    },

    soundSessionController() {
      return window.ManaChessSoundSession;
    },

    soundEnabled() {
      return this.soundSessionController().enabled(this);
    },

    setSoundEnabled(enabled) {
      this.soundSessionController().setEnabled(this, enabled);
    },

    soundVolume() {
      return this.soundSessionController().volume(this);
    },

    setSoundVolume(value) {
      this.soundSessionController().setVolume(this, value);
    },

    renderSoundToggle() {
      this.soundSessionController().renderToggle(this);
    },

    cosmeticSessionController() {
      return window.ManaChessCosmeticSession;
    },

    cosmeticsController() {
      return this.cosmeticSessionController().cosmetics();
    },

    cosmeticActionsController() {
      return this.cosmeticSessionController().actions();
    },

    cosmeticFallbackController() {
      return this.cosmeticSessionController().fallback();
    },

    renderModularCosmetics() {
      return this.cosmeticSessionController().renderModular();
    },

    readCosmeticUnlocks() {
      return this.cosmeticSessionController().readCosmeticUnlocks(this);
    },

    writeCosmeticUnlocks(unlocks) {
      this.cosmeticSessionController().writeCosmeticUnlocks(this, unlocks);
    },

    cosmeticUnlocked(id) {
      return this.cosmeticSessionController().cosmeticUnlocked(this, id);
    },

    unlockCosmetic(id) {
      this.cosmeticSessionController().unlockCosmetic(this, id);
    },

    cosmeticAllowed(id) {
      return this.cosmeticSessionController().cosmeticAllowed(this, id);
    },

    cosmeticPackConfig(pack) {
      return this.cosmeticSessionController().cosmeticPackConfig(pack);
    },

    cosmeticPackUnlocked(pack) {
      return this.cosmeticSessionController().cosmeticPackUnlocked(this, pack);
    },

    applyCosmeticPack(pack) {
      this.cosmeticSessionController().applyCosmeticPack(this, pack);
    },

    premiumIdForBoardSkin(skin) {
      return this.cosmeticSessionController().premiumIdForBoardSkin(skin);
    },

    premiumIdForPieceSkin(skin) {
      return this.cosmeticSessionController().premiumIdForPieceSkin(skin);
    },

    activateCosmeticControl(control) {
      this.cosmeticSessionController().activateCosmeticControl(this, control);
    },

    renderCosmetics() {
      this.cosmeticSessionController().renderCosmetics(this);
    },

    renderCosmeticPacks() {
      this.cosmeticSessionController().renderCosmeticPacks(this);
    },

    boardSkin() {
      return this.cosmeticSessionController().boardSkin(this);
    },

    setBoardSkin(skin) {
      this.cosmeticSessionController().setBoardSkin(this, skin);
    },

    renderBoardSkin() {
      this.cosmeticSessionController().renderBoardSkin(this);
    },

    pieceSkin() {
      return this.cosmeticSessionController().pieceSkin(this);
    },

    setPieceSkin(skin) {
      this.cosmeticSessionController().setPieceSkin(this, skin);
    },

    renderPieceSkin() {
      this.cosmeticSessionController().renderPieceSkin(this);
    },

    defaultPalette() {
      return this.cosmeticSessionController().defaultPalette();
    },

    palettePreset(name) {
      return this.cosmeticSessionController().palettePreset(name);
    },

    paletteEquals(first, second) {
      return this.cosmeticSessionController().paletteEquals(first, second);
    },

    activePalettePreset(palette) {
      return this.cosmeticSessionController().activePalettePreset(palette);
    },
    readPalette() {
      return this.cosmeticSessionController().readPalette(this);
    },

    setPalette(palette) {
      this.cosmeticSessionController().setPalette(this, palette);
    },

    renderPalette() {
      this.cosmeticSessionController().renderPalette(this);
    },

    boardPreviewPalette(skin, palette) {
      return this.cosmeticSessionController().boardPreviewPalette(skin, palette);
    },

    piecePreviewPalette(skin, palette) {
      return this.cosmeticSessionController().piecePreviewPalette(skin, palette);
    },

    renderCosmeticPreview() {
      this.cosmeticSessionController().renderCosmeticPreview(this);
    },

    applyPalette(palette) {
      this.cosmeticSessionController().applyPalette(this, palette);
    },

    readableTextColor(hex) {
      return this.cosmeticSessionController().readableTextColor(hex);
    },

    hexToRgba(hex, alpha) {
      return this.cosmeticSessionController().hexToRgba(hex, alpha);
    },

    hexToRgb(hex) {
      return this.cosmeticSessionController().hexToRgb(hex);
    },

    chatController() {
      return window.ManaChessChat;
    },

    renderChatTimes() {
      this.chatController().renderTimes(this.el);
    },

    soundState() {
      return this.soundSessionController().state(this);
    },

    chatScrollState() {
      return this.chatController().scrollState(this.el);
    },

    keepChatAtLatest() {
      this.lastChatScrollState = this.chatController().keepAtLatest(this.el, this.lastChatScrollState);
    },

    scrollChatListsToEnd() {
      this.chatController().scrollListsToEnd(this.el);
    },

    navigationController() {
      return window.ManaChessNavigation;
    },

    viewKey() {
      return this.navigationController().viewKey(this.el);
    },

    keepViewInFrame() {
      this.lastViewKey = this.navigationController().keepViewInFrame(this.el, this.lastViewKey);
    },

    keepInitialViewInFrame() {
      this.navigationController().keepInitialViewInFrame(this.el);
    },

    scrollViewToTop() {
      this.navigationController().scrollToTop();
    },

    playChangedSound() {
      this.soundSessionController().playChanged(this);
    },

    playSound(kind) {
      this.soundSessionController().play(this, kind);
    },

    inviteClipboardController() {
      return window.ManaChessInviteClipboard;
    },

    copyInvite(button) {
      this.inviteClipboardController().copy(button, {
        copyShareLink: url => this.desktopSessionController().copyShareLink(this, url),
        onCopied: () => this.playSound("copy")
      });
    },

    fallbackCopy(text, callback) {
      this.inviteClipboardController().fallbackCopy(text, callback);
    }
  },

  BoardDrag: {
    mounted() {
      window.ManaChessBoardDrag.mounted(this);
    },

    updated() {
      window.ManaChessBoardDrag.updated(this);
    },

    destroyed() {
      window.ManaChessBoardDrag.destroyed(this);
    }
  }
};

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});

liveSocket.connect();
window.liveSocket = liveSocket;
