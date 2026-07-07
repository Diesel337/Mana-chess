// LocalStats hook lifecycle. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const renderCosmetics = hook => {
    if (!hook.renderModularCosmetics()) {
      hook.renderCosmetics();
      hook.renderBoardSkin();
      hook.renderPieceSkin();
      hook.renderPalette();
    }
  };

  const mounted = hook => {
    hook.lastResultKey = null;
    hook.storageKey = "mana-chess-local-stats";
    hook.soundKey = "mana-chess-sound-enabled";
    hook.soundVolumeKey = "mana-chess-sound-volume";
    hook.skinKey = "mana-chess-board-skin";
    hook.pieceSkinKey = "mana-chess-piece-skin";
    hook.cosmeticUnlockKey = "mana-chess-cosmetic-unlocks";
    hook.paletteKey = "mana-chess-custom-palette";
    hook.lastSoundState = hook.soundState();
    hook.lastChatScrollState = null;
    hook.desktopState = hook.desktopSessionController().state(hook);
    hook.lastViewKey = hook.viewKey();
    hook.keepInitialViewInFrame();
    hook.localStatsEventsController().bind(hook);
    hook.recordResult();
    hook.renderStats();
    hook.renderSoundToggle();
    renderCosmetics(hook);
    hook.renderChatTimes();
    hook.keepChatAtLatest();
    hook.emitDesktopView();
    hook.emitDesktopState(hook.soundState(), null);
  };

  const updated = hook => {
    hook.recordResult();
    hook.renderStats();
    hook.renderSoundToggle();
    renderCosmetics(hook);
    hook.renderChatTimes();
    hook.keepViewInFrame();
    hook.emitDesktopView();
    hook.keepChatAtLatest();
    hook.playChangedSound();
  };

  const destroyed = hook => {
    hook.localStatsEventsController().unbind(hook);
  };

  window.ManaChessLocalStatsLifecycle = {destroyed, mounted, updated};
})();
