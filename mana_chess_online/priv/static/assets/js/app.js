const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
  LocalStats: {
    mounted() {
      this.lastResultKey = null;
      this.storageKey = "mana-chess-local-stats";
      this.soundKey = "mana-chess-sound-enabled";
      this.soundVolumeKey = "mana-chess-sound-volume";
      this.skinKey = "mana-chess-board-skin";
      this.pieceSkinKey = "mana-chess-piece-skin";
      this.cosmeticUnlockKey = "mana-chess-cosmetic-unlocks";
      this.paletteKey = "mana-chess-custom-palette";
      this.lastSoundState = this.soundState();
      this.lastChatScrollState = null;
      this.desktopState = this.desktopSessionController().state(this);
      this.lastViewKey = this.viewKey();
      this.keepInitialViewInFrame();
      this.localStatsEventsController().bind(this);
      this.recordResult();
      this.renderStats();
      this.renderSoundToggle();
      if (!this.renderModularCosmetics()) {
        this.renderCosmetics();
        this.renderBoardSkin();
        this.renderPieceSkin();
        this.renderPalette();
      }
      this.renderChatTimes();
      this.keepChatAtLatest();
      this.emitDesktopView();
      this.emitDesktopState(this.soundState(), null);
    },

    updated() {
      this.recordResult();
      this.renderStats();
      this.renderSoundToggle();
      if (!this.renderModularCosmetics()) {
        this.renderCosmetics();
        this.renderBoardSkin();
        this.renderPieceSkin();
        this.renderPalette();
      }
      this.renderChatTimes();
      this.keepViewInFrame();
      this.emitDesktopView();
      this.keepChatAtLatest();
      this.playChangedSound();
    },

    destroyed() {
      this.localStatsEventsController().unbind(this);
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

    soundController() {
      return window.ManaChessSound;
    },

    soundEnabled() {
      return this.soundController().enabled(this.soundKey);
    },

    setSoundEnabled(enabled) {
      this.soundController().setEnabled(this.soundKey, enabled);
    },

    soundVolume() {
      return this.soundController().volume(this.soundVolumeKey);
    },

    setSoundVolume(value) {
      this.soundController().setVolume(this.soundVolumeKey, value);
    },

    renderSoundToggle() {
      this.soundController().render(this.el, {
        soundKey: this.soundKey,
        volumeKey: this.soundVolumeKey
      });
    },

    cosmeticsController() {
      return window.ManaChessCosmetics || null;
    },

    cosmeticActionsController() {
      return window.ManaChessCosmeticActions;
    },

    cosmeticFallbackController() {
      return window.ManaChessCosmeticFallback;
    },

    renderModularCosmetics() {
      const controller = this.cosmeticsController();
      if (!controller) return false;

      controller.render();
      return true;
    },

    readCosmeticUnlocks() {
      return this.cosmeticFallbackController().readCosmeticUnlocks(this);
    },

    writeCosmeticUnlocks(unlocks) {
      this.cosmeticFallbackController().writeCosmeticUnlocks(this, unlocks);
    },

    cosmeticUnlocked(id) {
      return this.cosmeticFallbackController().cosmeticUnlocked(this, id);
    },

    unlockCosmetic(id) {
      this.cosmeticFallbackController().unlockCosmetic(this, id);
    },

    cosmeticAllowed(id) {
      return this.cosmeticFallbackController().cosmeticAllowed(this, id);
    },

    cosmeticPackConfig(pack) {
      return this.cosmeticFallbackController().cosmeticPackConfig(pack);
    },

    cosmeticPackUnlocked(pack) {
      return this.cosmeticFallbackController().cosmeticPackUnlocked(this, pack);
    },

    applyCosmeticPack(pack) {
      this.cosmeticFallbackController().applyCosmeticPack(this, pack);
    },

    premiumIdForBoardSkin(skin) {
      return this.cosmeticFallbackController().premiumIdForBoardSkin(skin);
    },

    premiumIdForPieceSkin(skin) {
      return this.cosmeticFallbackController().premiumIdForPieceSkin(skin);
    },

    activateCosmeticControl(control) {
      this.cosmeticFallbackController().activateCosmeticControl(this, control);
    },

    renderCosmetics() {
      this.cosmeticFallbackController().renderCosmetics(this);
    },

    renderCosmeticPacks() {
      this.cosmeticFallbackController().renderCosmeticPacks(this);
    },

    boardSkin() {
      return this.cosmeticFallbackController().boardSkin(this);
    },

    setBoardSkin(skin) {
      this.cosmeticFallbackController().setBoardSkin(this, skin);
    },

    renderBoardSkin() {
      this.cosmeticFallbackController().renderBoardSkin(this);
    },

    pieceSkin() {
      return this.cosmeticFallbackController().pieceSkin(this);
    },

    setPieceSkin(skin) {
      this.cosmeticFallbackController().setPieceSkin(this, skin);
    },

    renderPieceSkin() {
      this.cosmeticFallbackController().renderPieceSkin(this);
    },

    defaultPalette() {
      return this.cosmeticFallbackController().defaultPalette();
    },

    palettePreset(name) {
      return this.cosmeticFallbackController().palettePreset(name);
    },

    paletteEquals(first, second) {
      return this.cosmeticFallbackController().paletteEquals(first, second);
    },

    activePalettePreset(palette) {
      return this.cosmeticFallbackController().activePalettePreset(palette);
    },
    readPalette() {
      return this.cosmeticFallbackController().readPalette(this);
    },

    setPalette(palette) {
      this.cosmeticFallbackController().setPalette(this, palette);
    },

    renderPalette() {
      this.cosmeticFallbackController().renderPalette(this);
    },

    boardPreviewPalette(skin, palette) {
      return this.cosmeticFallbackController().boardPreviewPalette(skin, palette);
    },

    piecePreviewPalette(skin, palette) {
      return this.cosmeticFallbackController().piecePreviewPalette(skin, palette);
    },

    renderCosmeticPreview() {
      this.cosmeticFallbackController().renderCosmeticPreview(this);
    },

    applyPalette(palette) {
      this.cosmeticFallbackController().applyPalette(this, palette);
    },

    readableTextColor(hex) {
      return this.cosmeticFallbackController().readableTextColor(hex);
    },

    hexToRgba(hex, alpha) {
      return this.cosmeticFallbackController().hexToRgba(hex, alpha);
    },

    hexToRgb(hex) {
      return this.cosmeticFallbackController().hexToRgb(hex);
    },

    chatController() {
      return window.ManaChessChat;
    },

    renderChatTimes() {
      this.chatController().renderTimes(this.el);
    },

    soundStateController() {
      return window.ManaChessSoundState;
    },

    soundState() {
      return this.soundStateController().state(this.el);
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
      const current = this.soundState();
      const previous = this.lastSoundState;
      this.lastSoundState = current;
      this.emitDesktopState(current, previous);
      const changedSound = this.soundStateController().changedSound(current, previous, this.soundEnabled());

      if (changedSound) this.playSound(changedSound);
    },

    playSound(kind) {
      this.soundController().play(kind, {
        soundKey: this.soundKey,
        volumeKey: this.soundVolumeKey
      });
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
      this.drag = null;
      this.suppressClick = false;

      this.el.addEventListener("pointerdown", event => {
        const square = event.target.closest(".mc-square");
        const piece = square && square.querySelector(".mc-piece:not(:empty)");

        this.clearLegalPreview();
        this.clearBlockedPreview();
        if (!square || !piece) return;

        const legalMoves = this.legalMoves(square);
        if (legalMoves.length === 0) {
          this.flashBlockedSquare(square);
          return;
        }

        this.showLegalPreview(square, legalMoves);

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
          moved: false
        };

        square.setPointerCapture(event.pointerId);
      });

      this.el.addEventListener("pointermove", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return;

        const delta = Math.abs(event.clientX - this.drag.startX) + Math.abs(event.clientY - this.drag.startY);

        if (delta > 8) {
          this.drag.moved = true;
          this.el.classList.add("mc-dragging");
          this.drag.square.classList.add("mc-drag-source");
          if (!this.drag.ghost) {
            this.drag.ghost = this.createDragGhost(this.drag.piece, event.clientX, event.clientY);
          }
        }

        if (this.drag.ghost) this.moveDragGhost(this.drag.ghost, event.clientX, event.clientY);
      });

      this.el.addEventListener("pointerup", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return;

        const drag = this.drag;
        this.drag = null;
        this.clearDragVisuals(drag);

        if (!drag.moved) return;
        this.suppressClick = true;
        this.clearLegalPreview();

        const target = document.elementFromPoint(event.clientX, event.clientY);
        const square = target && target.closest(".mc-square");

        if (!square) {
          this.flashBlockedSquare(drag.square);
          this.pushEvent("drag_invalid", {
            from_r: drag.fromR,
            from_c: drag.fromC
          });
          return;
        }

        if (!this.legalTarget(drag, square)) {
          this.flashBlockedSquare(square);
        }

        this.pushEvent("drag_move", {
          from_r: drag.fromR,
          from_c: drag.fromC,
          to_r: square.dataset.r,
          to_c: square.dataset.c
        });
      });

      this.el.addEventListener("pointercancel", _event => {
        const drag = this.drag;
        this.drag = null;
        this.clearDragVisuals(drag);
        this.clearLegalPreview();
        this.clearBlockedPreview();
      });

      this.el.addEventListener("click", event => {
        if (this.suppressClick) {
          this.suppressClick = false;
          event.preventDefault();
          event.stopPropagation();
        }
      }, true);
    },

    updated() {
      this.clearLegalPreview();
      this.clearBlockedPreview();
    },

    destroyed() {
      this.clearLegalPreview();
      this.clearBlockedPreview();
    },

    legalMoves(square) {
      return (square.dataset.legalMoves || "").trim().split(/\s+/).filter(Boolean);
    },

    legalTarget(drag, square) {
      return drag.legalMoves.includes(`${square.dataset.r},${square.dataset.c}`);
    },

    showLegalPreview(square, moves = this.legalMoves(square)) {
      if (moves.length === 0) return;

      square.classList.add("mc-selected", "mc-client-selected");

      moves.forEach(move => {
        const [r, c] = move.split(",");
        const target = this.el.querySelector(`.mc-square[data-r="${r}"][data-c="${c}"]`);
        if (target) target.classList.add("mc-valid", "mc-client-valid");
      });
    },

    clearLegalPreview() {
      this.el.querySelectorAll(".mc-client-selected").forEach(square => {
        square.classList.remove("mc-selected", "mc-client-selected");
      });
      this.el.querySelectorAll(".mc-client-valid").forEach(square => {
        square.classList.remove("mc-valid", "mc-client-valid");
      });
    },

    flashBlockedSquare(square) {
      if (!square) return;
      square.classList.remove("mc-client-blocked");
      void square.offsetWidth;
      square.classList.add("mc-client-blocked");
      window.clearTimeout(square.blockedPreviewTimer);
      square.blockedPreviewTimer = window.setTimeout(() => {
        square.classList.remove("mc-client-blocked");
      }, 620);
    },

    clearBlockedPreview() {
      this.el.querySelectorAll(".mc-client-blocked").forEach(square => {
        window.clearTimeout(square.blockedPreviewTimer);
        square.classList.remove("mc-client-blocked");
      });
    },

    createDragGhost(piece, x, y) {
      const rect = piece.getBoundingClientRect();
      const ghost = piece.cloneNode(true);
      ghost.classList.add("mc-drag-ghost");
      ghost.style.width = `${rect.width}px`;
      ghost.style.height = `${rect.height}px`;
      document.body.appendChild(ghost);
      this.moveDragGhost(ghost, x, y);
      return ghost;
    },

    moveDragGhost(ghost, x, y) {
      ghost.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -58%) scale(1.08)`;
    },

    clearDragVisuals(drag) {
      this.el.classList.remove("mc-dragging");
      if (!drag) return;
      drag.square && drag.square.classList.remove("mc-drag-source");
      drag.ghost && drag.ghost.remove();
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
