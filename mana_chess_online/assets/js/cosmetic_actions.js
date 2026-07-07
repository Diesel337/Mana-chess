// Cosmetic action helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const playSkinSound = hook => {
    if (hook.soundEnabled()) hook.playSound("skin")
  }

  const handleUnlock = (event, hook) => {
    const control = event.target.closest("[data-cosmetic-premium], [data-palette-unlock]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return

    const premiumId = control.dataset.cosmeticPremium || "palette:custom"
    if (hook.cosmeticUnlocked(premiumId) && !control.matches("[data-palette-unlock]")) return

    event.preventDefault()
    event.stopImmediatePropagation()
    hook.unlockCosmetic(premiumId)
    hook.activateCosmeticControl(control)
    hook.renderCosmetics()
    playSkinSound(hook)
  }

  const handleSoundAction = (event, hook) => {
    const control = event.target.closest("[data-sound-action]")
    if (!control || control.disabled) return
    if (control.matches("[data-piece-skin-choice]")) {
      if (hook.cosmeticsController()) {
        if (hook.soundEnabled()) hook.playSound(control.dataset.soundAction || "skin")
        return
      }

      event.preventDefault()
      event.stopImmediatePropagation()
      hook.setPieceSkin(control.dataset.pieceSkinChoice)
      hook.renderPieceSkin()
      playSkinSound(hook)
      return
    }
    if (!hook.soundEnabled()) return
    hook.playSound(control.dataset.soundAction || "tap")
  }

  const handleBoardSkinChoice = (event, hook) => {
    const control = event.target.closest("[data-board-skin-choice]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return

    event.preventDefault()
    hook.setBoardSkin(control.dataset.boardSkinChoice)
    hook.renderBoardSkin()
    hook.playSound("skin")
  }

  const handlePieceSkinChoice = (event, hook) => {
    const control = event.target.closest("[data-piece-skin-choice]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return

    event.preventDefault()
    hook.setPieceSkin(control.dataset.pieceSkinChoice)
    hook.renderPieceSkin()
    hook.playSound("skin")
  }

  const handlePalettePreset = (event, hook) => {
    const control = event.target.closest("[data-palette-preset]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return
    if (!hook.cosmeticUnlocked("palette:custom")) return

    event.preventDefault()
    hook.setPalette(hook.palettePreset(control.dataset.palettePreset))
    hook.setBoardSkin("custom")
    hook.setPieceSkin("custom")
    hook.renderBoardSkin()
    hook.renderPieceSkin()
    hook.renderPalette()
    hook.renderCosmetics()
    hook.playSound("skin")
  }

  const handlePaletteReset = (event, hook) => {
    const control = event.target.closest("[data-palette-reset]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return
    if (!hook.cosmeticUnlocked("palette:custom")) return

    event.preventDefault()
    hook.setPalette(hook.defaultPalette())
    hook.setBoardSkin("custom")
    hook.setPieceSkin("custom")
    hook.renderBoardSkin()
    hook.renderPieceSkin()
    hook.renderPalette()
    hook.renderCosmetics()
    hook.playSound("skin")
  }

  const handlePaletteColor = (event, hook) => {
    const input = event.target.closest("[data-palette-color]")
    if (!input || input.disabled) return
    if (hook.cosmeticsController()) return
    if (!hook.cosmeticUnlocked("palette:custom")) return

    hook.setPalette({...hook.readPalette(), [input.dataset.paletteColor]: input.value})
    hook.setBoardSkin("custom")
    hook.setPieceSkin("custom")
    hook.renderBoardSkin()
    hook.renderPieceSkin()
    hook.renderPalette()
    hook.renderCosmetics()
  }

  const handleCosmeticPack = (event, hook) => {
    const control = event.target.closest("[data-cosmetic-pack]")
    if (!control || control.disabled) return
    if (hook.cosmeticsController()) return

    event.preventDefault()
    hook.applyCosmeticPack(control.dataset.cosmeticPack)
    hook.renderBoardSkin()
    hook.renderPieceSkin()
    hook.renderCosmetics()
  }

  window.ManaChessCosmeticActions = {
    handleUnlock,
    handleSoundAction,
    handleBoardSkinChoice,
    handlePieceSkinChoice,
    handlePalettePreset,
    handlePaletteReset,
    handlePaletteColor,
    handleCosmeticPack,
  }
})()
