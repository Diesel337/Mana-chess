// LocalStats DOM event wiring. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const definitions = [
    {
      type: "click",
      name: "handleReset",
      build: hook => event => {
        if (!event.target.closest("[data-stats-reset]")) return;
        localStorage.removeItem(hook.storageKey);
        hook.lastResultKey = null;
        hook.renderStats();
        if (!hook.renderModularCosmetics()) hook.renderCosmetics();
      },
    },
    {
      type: "click",
      name: "handleInviteCopy",
      build: hook => event => {
        const button = event.target.closest("[data-copy-invite]");
        if (!button) return;
        event.preventDefault();
        hook.copyInvite(button);
      },
    },
    {
      type: "click",
      name: "handleSoundToggle",
      build: hook => event => {
        const button = event.target.closest("[data-sound-toggle]");
        if (!button) return;
        event.preventDefault();
        const enabled = !hook.soundEnabled();
        hook.setSoundEnabled(enabled);
        hook.renderSoundToggle();
        if (enabled) hook.playSound("ready");
      },
    },
    {
      type: "input",
      name: "handleSoundVolume",
      build: hook => event => {
        const input = event.target.closest("[data-sound-volume]");
        if (!input) return;
        hook.setSoundVolume(input.value);
        hook.renderSoundToggle();
      },
    },
    {type: "change", name: "handleSoundVolume"},
    {
      type: "click",
      name: "handleCosmeticUnlock",
      build: hook => event => hook.cosmeticActionsController().handleUnlock(event, hook),
    },
    {
      type: "click",
      name: "handleSoundAction",
      build: hook => event => hook.cosmeticActionsController().handleSoundAction(event, hook),
    },
    {
      type: "click",
      name: "handleSkinChoice",
      build: hook => event => hook.cosmeticActionsController().handleBoardSkinChoice(event, hook),
    },
    {
      type: "click",
      name: "handlePieceSkinChoice",
      build: hook => event => hook.cosmeticActionsController().handlePieceSkinChoice(event, hook),
    },
    {
      type: "click",
      name: "handlePalettePreset",
      build: hook => event => hook.cosmeticActionsController().handlePalettePreset(event, hook),
    },
    {
      type: "click",
      name: "handlePaletteReset",
      build: hook => event => hook.cosmeticActionsController().handlePaletteReset(event, hook),
    },
    {
      type: "input",
      name: "handlePaletteColor",
      build: hook => event => hook.cosmeticActionsController().handlePaletteColor(event, hook),
    },
    {type: "change", name: "handlePaletteColor"},
    {
      type: "click",
      name: "handleCosmeticPack",
      build: hook => event => hook.cosmeticActionsController().handleCosmeticPack(event, hook),
    },
  ];

  const bind = hook => {
    definitions.forEach(definition => {
      if (definition.build) hook[definition.name] = definition.build(hook);
      hook.el.addEventListener(definition.type, hook[definition.name]);
    });
  };

  const unbind = hook => {
    definitions.forEach(definition => {
      if (!hook[definition.name]) return;
      hook.el.removeEventListener(definition.type, hook[definition.name]);
    });
  };

  window.ManaChessLocalStatsEvents = {bind, unbind};
})();
