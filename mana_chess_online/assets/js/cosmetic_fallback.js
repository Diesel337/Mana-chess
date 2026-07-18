// Cosmetic fallback helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const catalog = window.ManaChessCosmeticCatalog
  if (!catalog) return

  const boards = [...catalog.boards]
  const pieces = [...catalog.pieces]
  const packs = catalog.packs
  const premiumBoards = new Set(catalog.premiumBoards)
  const premiumPieces = new Set(catalog.premiumPieces)
  const defaultPalette = {
    boardLight: "#d9c58f",
    boardDark: "#243a31",
    pieceWhite: "#f6f1df",
    pieceBlack: "#241745",
  }
  const palettePresets = {
    midnight: {boardLight: "#8067c9", boardDark: "#151020", pieceWhite: "#f7f2ff", pieceBlack: "#241745"},
    emerald: {boardLight: "#8bd9bd", boardDark: "#17342b", pieceWhite: "#f5f9de", pieceBlack: "#0b2c24"},
    frost: {boardLight: "#d9f0ff", boardDark: "#22354f", pieceWhite: "#ffffff", pieceBlack: "#2f5e8f"},
    solar: {boardLight: "#f2c15f", boardDark: "#174a45", pieceWhite: "#fff4d2", pieceBlack: "#31204f"},
    ruby: {boardLight: "#f0b7a6", boardDark: "#3b141c", pieceWhite: "#fff0ea", pieceBlack: "#4c0f23"},
  }

  const api = {
    readCosmeticUnlocks(hook) {
      try {
        return JSON.parse(localStorage.getItem(hook.cosmeticUnlockKey)) || []
      } catch (_error) {
        return []
      }
    },

    writeCosmeticUnlocks(hook, unlocks) {
      localStorage.setItem(hook.cosmeticUnlockKey, JSON.stringify([...new Set(unlocks)]))
    },

    cosmeticUnlocked(hook, id) {
      return api.readCosmeticUnlocks(hook).includes(id)
    },

    unlockCosmetic(hook, id) {
      const unlocks = api.readCosmeticUnlocks(hook)
      const next = [...unlocks, id]

      if (id === "board:custom" || id === "piece:custom" || id === "palette:custom") {
        next.push("board:custom", "piece:custom", "palette:custom")
      }

      api.writeCosmeticUnlocks(hook, next)
    },

    cosmeticAllowed(hook, id) {
      return !id || api.cosmeticUnlocked(hook, id)
    },

    cosmeticPackConfig(pack) {
      return packs[pack] || null
    },

    cosmeticPackUnlocked(hook, pack) {
      const config = api.cosmeticPackConfig(pack)
      if (!config) return false
      if (config.included) return true
      return (config.unlocks || []).every(id => api.cosmeticUnlocked(hook, id))
    },

    applyCosmeticPack(hook, pack) {
      const config = api.cosmeticPackConfig(pack)
      if (!config) return

      ;(config.unlocks || []).forEach(id => api.unlockCosmetic(hook, id))
      api.setBoardSkin(hook, config.board)
      api.setPieceSkin(hook, config.piece)
    },

    premiumIdForBoardSkin(skin) {
      return premiumBoards.has(skin) ? `board:${skin}` : null
    },

    premiumIdForPieceSkin(skin) {
      return premiumPieces.has(skin) ? `piece:${skin}` : null
    },

    activateCosmeticControl(hook, control) {
      if (control.matches("[data-palette-unlock]")) {
        api.setBoardSkin(hook, "custom")
        api.setPieceSkin(hook, "custom")
        api.renderBoardSkin(hook)
        api.renderPieceSkin(hook)
        api.renderPalette(hook)
        return
      }

      if (control.dataset.boardSkinChoice) {
        api.setBoardSkin(hook, control.dataset.boardSkinChoice)
        api.renderBoardSkin(hook)
      }

      if (control.dataset.pieceSkinChoice) {
        api.setPieceSkin(hook, control.dataset.pieceSkinChoice)
        api.renderPieceSkin(hook)
      }
    },

    renderCosmetics(hook) {
      hook.el.querySelectorAll("[data-cosmetic-premium]").forEach(control => {
        const unlocked = api.cosmeticUnlocked(hook, control.dataset.cosmeticPremium)
        control.classList.toggle("mc-skin-locked", !unlocked)
        control.classList.toggle("mc-skin-unlocked", unlocked)
        control.setAttribute("aria-disabled", "false")
        control.title = unlocked ? "Cosmetico desbloqueado localmente" : "Premium proximamente; probar localmente"
        control.querySelectorAll("[data-cosmetic-status]").forEach(status => {
          status.textContent = unlocked ? "Local" : "Premium proximamente"
          status.dataset.cosmeticState = unlocked ? "local" : "premium"
        })
      })

      hook.el.querySelectorAll("[data-palette-editor]").forEach(editor => {
        const unlocked = api.cosmeticUnlocked(hook, "palette:custom")
        editor.classList.toggle("is-locked", !unlocked)
        editor.classList.toggle("is-unlocked", unlocked)
        editor.querySelectorAll("[data-palette-status]").forEach(status => {
          status.textContent = unlocked ? "Local" : "Premium proximamente"
          status.dataset.paletteState = unlocked ? "local" : "premium"
        })
        editor.querySelectorAll("[data-palette-unlock]").forEach(control => {
          control.setAttribute("aria-disabled", "false")
        })
        editor.querySelectorAll("[data-palette-color]").forEach(control => {
          control.disabled = !unlocked
        })
      })

      const paletteUnlocked = api.cosmeticUnlocked(hook, "palette:custom")
      hook.el.querySelectorAll("[data-palette-preset], [data-palette-reset], [data-palette-color]").forEach(control => {
        control.disabled = !paletteUnlocked
      })

      api.renderCosmeticPacks(hook)
    },

    renderCosmeticPacks(hook) {
      const board = api.boardSkin(hook)
      const piece = api.pieceSkin(hook)

      hook.el.querySelectorAll("[data-cosmetic-pack]").forEach(control => {
        const pack = control.dataset.cosmeticPack
        const config = api.cosmeticPackConfig(pack)
        if (!config) return

        const unlocked = api.cosmeticPackUnlocked(hook, pack)
        const selected = unlocked && config.board === board && config.piece === piece
        control.classList.toggle("mc-skin-selected", selected)
        control.classList.toggle("mc-skin-locked", !unlocked)
        control.classList.toggle("mc-skin-unlocked", unlocked && !config.included)
        control.setAttribute("aria-pressed", selected ? "true" : "false")
        control.setAttribute("aria-disabled", "false")
        control.title = unlocked ? "Pack disponible localmente" : "Premium proximamente; probar localmente"
        control.querySelectorAll("[data-cosmetic-pack-status]").forEach(status => {
          status.textContent = config.included ? "Incluido" : unlocked ? "Local" : "Premium proximamente"
          status.dataset.cosmeticState = config.included ? "included" : unlocked ? "local" : "premium"
        })
      })
    },

    boardSkin(hook) {
      const skin = localStorage.getItem(hook.skinKey)
      if (skin === "mana") return "gilded"
      if (api.cosmeticAllowed(hook, api.premiumIdForBoardSkin(skin))) {
        return boards.includes(skin) ? skin : "classic"
      }
      return "classic"
    },

    setBoardSkin(hook, skin) {
      if (!boards.includes(skin)) return
      if (!api.cosmeticAllowed(hook, api.premiumIdForBoardSkin(skin))) return
      localStorage.setItem(hook.skinKey, skin)
    },

    renderBoardSkin(hook) {
      const skin = api.boardSkin(hook)

      hook.el.querySelectorAll("[data-board-skin-target]").forEach(node => {
        node.dataset.boardSkin = skin
      })

      hook.el.querySelectorAll("[data-board-skin-choice]").forEach(button => {
        const selected = button.dataset.boardSkinChoice === skin
        button.classList.toggle("mc-skin-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })

      api.renderCosmeticPreview(hook)
    },

    pieceSkin(hook) {
      const skin = localStorage.getItem(hook.pieceSkinKey)
      if (api.cosmeticAllowed(hook, api.premiumIdForPieceSkin(skin))) {
        return pieces.includes(skin) ? skin : "classic"
      }
      return "classic"
    },

    setPieceSkin(hook, skin) {
      if (!pieces.includes(skin)) return
      if (!api.cosmeticAllowed(hook, api.premiumIdForPieceSkin(skin))) return
      localStorage.setItem(hook.pieceSkinKey, skin)
    },

    renderPieceSkin(hook) {
      const skin = api.pieceSkin(hook)
      hook.el.dataset.pieceSkin = skin
      pieces.forEach(name => hook.el.classList.toggle(`mc-piece-skin-${name}`, skin === name))
      document.documentElement.dataset.pieceSkin = skin

      hook.el.querySelectorAll("[data-piece-skin-choice]").forEach(button => {
        const selected = button.dataset.pieceSkinChoice === skin
        button.classList.toggle("mc-skin-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })

      api.renderCosmeticPreview(hook)
    },

    defaultPalette() {
      return {...defaultPalette}
    },

    palettePreset(name) {
      return palettePresets[name] || api.defaultPalette()
    },

    paletteEquals(first, second) {
      return Object.keys(defaultPalette).every(key => {
        const a = (first[key] || "").toLowerCase()
        const b = (second[key] || "").toLowerCase()
        return a === b
      })
    },

    activePalettePreset(palette) {
      const normalized = {...defaultPalette, ...palette}
      if (api.paletteEquals(normalized, defaultPalette)) return "base"
      return Object.keys(palettePresets).find(name => api.paletteEquals(normalized, api.palettePreset(name))) || null
    },

    readPalette(hook) {
      try {
        return {...defaultPalette, ...(JSON.parse(localStorage.getItem(hook.paletteKey)) || {})}
      } catch (_error) {
        return api.defaultPalette()
      }
    },

    setPalette(hook, palette) {
      localStorage.setItem(hook.paletteKey, JSON.stringify({...defaultPalette, ...palette}))
    },

    renderPalette(hook) {
      const palette = api.readPalette(hook)
      api.applyPalette(hook, palette)

      hook.el.querySelectorAll("[data-palette-color]").forEach(input => {
        if (palette[input.dataset.paletteColor]) input.value = palette[input.dataset.paletteColor]
      })
      const activePreset = api.activePalettePreset(palette)
      hook.el.querySelectorAll("[data-palette-reset]").forEach(button => {
        const selected = activePreset === "base"
        button.classList.toggle("mc-palette-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })
      hook.el.querySelectorAll("[data-palette-preset]").forEach(button => {
        const selected = button.dataset.palettePreset === activePreset
        button.classList.toggle("mc-palette-selected", selected)
        button.setAttribute("aria-pressed", selected ? "true" : "false")
      })
      api.renderCosmeticPreview(hook)
    },

    boardPreviewPalette(skin, palette) {
      if (skin === "custom") {
        return {frame: palette.boardLight, light: palette.boardLight, dark: palette.boardDark}
      }
      return catalog.boardPreviewPalettes[skin] || catalog.boardPreviewPalettes.classic
    },

    piecePreviewPalette(skin, palette) {
      if (skin === "custom") {
        return {
          frame: palette.boardLight,
          white: palette.pieceWhite,
          black: palette.pieceBlack,
          whiteText: api.readableTextColor(palette.pieceWhite),
          blackText: api.readableTextColor(palette.pieceBlack),
          whiteGlow: api.hexToRgba(palette.pieceWhite, 0.42),
          blackGlow: api.hexToRgba(palette.pieceBlack, 0.5),
        }
      }
      return catalog.piecePreviewPalettes[skin] || catalog.piecePreviewPalettes.classic
    },

    renderCosmeticPreview(hook) {
      const palette = api.readPalette(hook)
      const boardSkin = api.boardSkin(hook)
      const pieceSkin = api.pieceSkin(hook)
      const board = api.boardPreviewPalette(boardSkin, palette)
      const piece = api.piecePreviewPalette(pieceSkin, palette)
      const vars = {
        "--mc-preview-board-frame": board.frame,
        "--mc-preview-board-light": board.light,
        "--mc-preview-board-dark": board.dark,
        "--mc-preview-piece-frame": piece.frame,
        "--mc-preview-piece-white": piece.white,
        "--mc-preview-piece-black": piece.black,
        "--mc-preview-piece-white-text": piece.whiteText,
        "--mc-preview-piece-black-text": piece.blackText,
        "--mc-preview-piece-white-glow": piece.whiteGlow,
        "--mc-preview-piece-black-glow": piece.blackGlow,
      }

      hook.el.querySelectorAll("[data-palette-live-preview]").forEach(preview => {
        preview.dataset.boardSkin = boardSkin
        preview.dataset.pieceSkin = pieceSkin
        for (const [name, value] of Object.entries(vars)) {
          preview.style.setProperty(name, value)
        }
      })
    },

    applyPalette(hook, palette) {
      const root = document.documentElement
      const vars = {
        "--mc-custom-board-light": palette.boardLight,
        "--mc-custom-board-dark": palette.boardDark,
        "--mc-custom-board-frame": palette.boardLight,
        "--mc-custom-piece-white": palette.pieceWhite,
        "--mc-custom-piece-black": palette.pieceBlack,
        "--mc-custom-piece-white-text": api.readableTextColor(palette.pieceWhite),
        "--mc-custom-piece-black-text": api.readableTextColor(palette.pieceBlack),
        "--mc-custom-piece-white-glow": api.hexToRgba(palette.pieceWhite, 0.42),
        "--mc-custom-piece-black-glow": api.hexToRgba(palette.pieceBlack, 0.5),
      }

      for (const [name, value] of Object.entries(vars)) {
        root.style.setProperty(name, value)
        hook.el.style.setProperty(name, value)
      }
    },

    readableTextColor(hex) {
      const rgb = api.hexToRgb(hex)
      if (!rgb) return "#10140f"
      const luminance = (0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b) / 255
      return luminance > 0.56 ? "#10140f" : "#fff8dc"
    },

    hexToRgba(hex, alpha) {
      const rgb = api.hexToRgb(hex)
      if (!rgb) return `rgba(255, 255, 255, ${alpha})`
      return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${alpha})`
    },

    hexToRgb(hex) {
      const match = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || "")
      if (!match) return null
      return {
        r: Number.parseInt(match[1], 16),
        g: Number.parseInt(match[2], 16),
        b: Number.parseInt(match[3], 16),
      }
    },
  }

  window.ManaChessCosmeticFallback = api
})()
