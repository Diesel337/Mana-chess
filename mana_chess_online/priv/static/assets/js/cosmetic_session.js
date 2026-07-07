// Cosmetic hook adapter. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const cosmetics = () => window.ManaChessCosmetics || null;
  const actions = () => window.ManaChessCosmeticActions;
  const fallback = () => window.ManaChessCosmeticFallback;

  const renderModular = () => {
    const controller = cosmetics();
    if (!controller) return false;

    controller.render();
    return true;
  };

  const withHook = {
    readCosmeticUnlocks: hook => fallback().readCosmeticUnlocks(hook),
    writeCosmeticUnlocks: (hook, unlocks) => fallback().writeCosmeticUnlocks(hook, unlocks),
    cosmeticUnlocked: (hook, id) => fallback().cosmeticUnlocked(hook, id),
    unlockCosmetic: (hook, id) => fallback().unlockCosmetic(hook, id),
    cosmeticAllowed: (hook, id) => fallback().cosmeticAllowed(hook, id),
    cosmeticPackUnlocked: (hook, pack) => fallback().cosmeticPackUnlocked(hook, pack),
    applyCosmeticPack: (hook, pack) => fallback().applyCosmeticPack(hook, pack),
    activateCosmeticControl: (hook, control) => fallback().activateCosmeticControl(hook, control),
    renderCosmetics: hook => fallback().renderCosmetics(hook),
    renderCosmeticPacks: hook => fallback().renderCosmeticPacks(hook),
    boardSkin: hook => fallback().boardSkin(hook),
    setBoardSkin: (hook, skin) => fallback().setBoardSkin(hook, skin),
    renderBoardSkin: hook => fallback().renderBoardSkin(hook),
    pieceSkin: hook => fallback().pieceSkin(hook),
    setPieceSkin: (hook, skin) => fallback().setPieceSkin(hook, skin),
    renderPieceSkin: hook => fallback().renderPieceSkin(hook),
    readPalette: hook => fallback().readPalette(hook),
    setPalette: (hook, palette) => fallback().setPalette(hook, palette),
    renderPalette: hook => fallback().renderPalette(hook),
    renderCosmeticPreview: hook => fallback().renderCosmeticPreview(hook),
    applyPalette: (hook, palette) => fallback().applyPalette(hook, palette),
  };

  window.ManaChessCosmeticSession = {
    actions,
    cosmetics,
    fallback,
    renderModular,
    ...withHook,
    activePalettePreset: palette => fallback().activePalettePreset(palette),
    boardPreviewPalette: (skin, palette) => fallback().boardPreviewPalette(skin, palette),
    cosmeticPackConfig: pack => fallback().cosmeticPackConfig(pack),
    defaultPalette: () => fallback().defaultPalette(),
    hexToRgb: hex => fallback().hexToRgb(hex),
    hexToRgba: (hex, alpha) => fallback().hexToRgba(hex, alpha),
    paletteEquals: (first, second) => fallback().paletteEquals(first, second),
    palettePreset: name => fallback().palettePreset(name),
    piecePreviewPalette: (skin, palette) => fallback().piecePreviewPalette(skin, palette),
    premiumIdForBoardSkin: skin => fallback().premiumIdForBoardSkin(skin),
    premiumIdForPieceSkin: skin => fallback().premiumIdForPieceSkin(skin),
    readableTextColor: hex => fallback().readableTextColor(hex),
  };
})();
