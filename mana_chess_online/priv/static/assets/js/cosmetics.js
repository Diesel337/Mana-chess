// Source of the cosmetic shop controller. Keep the priv/static copy in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const catalog = window.ManaChessCosmeticCatalog;
  const progression = window.ManaChessCosmeticProgression;
  if (!catalog || !progression) return;

  const boardKey = "mana-chess-board-skin";
  const pieceKey = "mana-chess-piece-skin";
  const unlockKey = "mana-chess-cosmetic-unlocks";
  const paletteKey = "mana-chess-custom-palette";
  const statsKey = "mana-chess-local-stats";
  const boards = [...catalog.boards];
  const pieces = [...catalog.pieces];
  const cosmeticLabels = {
    included: "Incluido",
    unlocked: "Ganado"
  };
  const packs = catalog.packs;
  const included = new Set(catalog.includedIds);
  const defaultPalette = {
    boardLight: "#d9c58f",
    boardDark: "#243a31",
    pieceWhite: "#f6f1df",
    pieceBlack: "#241745"
  };
  const palettePresets = {
    midnight: {boardLight: "#8067c9", boardDark: "#151020", pieceWhite: "#f7f2ff", pieceBlack: "#241745"},
    emerald: {boardLight: "#8bd9bd", boardDark: "#17342b", pieceWhite: "#f5f9de", pieceBlack: "#0b2c24"},
    frost: {boardLight: "#d9f0ff", boardDark: "#22354f", pieceWhite: "#ffffff", pieceBlack: "#2f5e8f"},
    solar: {boardLight: "#f2c15f", boardDark: "#174a45", pieceWhite: "#fff4d2", pieceBlack: "#31204f"},
    ruby: {boardLight: "#f0b7a6", boardDark: "#3b141c", pieceWhite: "#fff0ea", pieceBlack: "#4c0f23"}
  };
  const previewLabels = {
    board: {
      classic: "Tablero clásico B/N",
      gilded: "Tablero dorado",
      arcane: "Tablero Arcano oscuro",
      crystal: "Tablero Prisma de cristal",
      elemental: "Tablero Forja elemental",
      celestial: "Tablero Firmamento",
      custom: "Tablero personalizado"
    },
    piece: {
      classic: "Piezas clásicas",
      runes: "Piezas Runas de mana",
      arcane: "Piezas Orden arcana",
      crystal: "Piezas Cristal boreal",
      elemental: "Piezas Guardianes elementales",
      celestial: "Piezas Corte celestial",
      custom: "Piezas personalizadas"
    },
    pack: {
      classic: "Conjunto Base",
      mana: "Conjunto Mana",
      arcane: "Conjunto Arcano",
      crystal: "Conjunto Cristal",
      elemental: "Conjunto Elemental",
      celestial: "Conjunto Celestial"
    },
    palette: {
      base: "Paleta Base",
      midnight: "Paleta Noche",
      emerald: "Paleta Jade",
      frost: "Paleta Hielo",
      solar: "Paleta Solar",
      ruby: "Paleta Rubí",
      custom: "Paleta personalizada"
    }
  };
  let previewSelection = null;
  const unlockId = (kind, skin) => `${kind}:${skin}`;
  const readUnlocks = () => {
    try {
      return new Set(JSON.parse(localStorage.getItem(unlockKey) || "[]"));
    } catch (_error) {
      return new Set();
    }
  };
  const writeUnlocks = (unlocks) => {
    try {
      localStorage.setItem(unlockKey, JSON.stringify([...new Set(unlocks)]));
    } catch (_error) {}
  };
  const announceUnlocks = (milestoneIds = []) => {
    if (typeof window.dispatchEvent !== "function" || typeof window.CustomEvent !== "function") return;

    milestoneIds.forEach((id) => {
      const milestone = progression.milestones.find(item => item.id === id);
      if (!milestone) return;
      window.dispatchEvent(new window.CustomEvent("mana-chess:cosmetic-unlocked", {
        detail: {id: milestone.id, label: milestone.label || milestone.id},
      }));
    });
  };
  const syncProgression = () => {
    const stats = progression.readStats(localStorage, statsKey);
    const synced = progression.syncUnlocks(stats, readUnlocks());
    if (synced.changed) {
      writeUnlocks(synced.unlocks);
      announceUnlocks(synced.unlockedMilestones);
    }
    return {...synced, stats, unlocks: new Set(synced.unlocks)};
  };
  const isPaletteUnlocked = (unlocks = readUnlocks()) => {
    return unlocks.has("palette:custom") || unlocks.has("board:custom") || unlocks.has("piece:custom");
  };
  const isUnlocked = (kind, skin, unlocks = readUnlocks()) => {
    if (skin === "custom") return isPaletteUnlocked(unlocks);
    return included.has(unlockId(kind, skin)) || unlocks.has(unlockId(kind, skin));
  };
  const isPackUnlocked = (pack, unlocks = readUnlocks()) => {
    const config = packs[pack];
    if (!config) return false;
    if (config.included) return true;
    return (config.unlocks || []).every((id) => {
      const [kind, skin] = id.split(":");
      return isUnlocked(kind, skin, unlocks);
    });
  };
  const lockedTitle = id => `${progression.requirementLabel(id)} para desbloquearlo`;
  const validHex = (value) => /^#[0-9a-f]{6}$/i.test(value || "");
  const normalizePalette = (palette = {}) => {
    const next = {...defaultPalette};
    Object.keys(next).forEach((key) => {
      if (validHex(palette[key])) next[key] = palette[key];
    });
    return next;
  };
  const paletteEquals = (first, second) => Object.keys(defaultPalette).every((key) => {
    const a = (first[key] || "").toLowerCase();
    const b = (second[key] || "").toLowerCase();
    return a === b;
  });
  const activePalettePreset = (palette) => {
    const normalized = normalizePalette(palette);
    if (paletteEquals(normalized, defaultPalette)) return "base";
    return Object.keys(palettePresets).find((name) => paletteEquals(normalized, normalizePalette(palettePresets[name]))) || null;
  };
  const readPalette = () => {
    try {
      return normalizePalette(JSON.parse(localStorage.getItem(paletteKey) || "{}"));
    } catch (_error) {
      return {...defaultPalette};
    }
  };
  const writePalette = (palette) => {
    try {
      localStorage.setItem(paletteKey, JSON.stringify(normalizePalette(palette)));
    } catch (_error) {}
  };
  const hexToRgb = (hex) => {
    const value = hex.replace("#", "");
    return {
      r: parseInt(value.slice(0, 2), 16),
      g: parseInt(value.slice(2, 4), 16),
      b: parseInt(value.slice(4, 6), 16)
    };
  };
  const contrastFor = (hex) => {
    const {r, g, b} = hexToRgb(hex);
    const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    return luminance > 0.58 ? "#10140f" : "#fff8dc";
  };
  const glowFor = (hex, alpha) => {
    const {r, g, b} = hexToRgb(hex);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  };
  const boardPreviewPalette = (skin, palette) => {
    if (skin === "custom") {
      return {frame: palette.boardLight, light: palette.boardLight, dark: palette.boardDark};
    }
    return catalog.boardPreviewPalettes[skin] || catalog.boardPreviewPalettes.classic;
  };
  const piecePreviewPalette = (skin, palette) => {
    if (skin === "custom") {
      return {
        frame: palette.boardLight,
        white: palette.pieceWhite,
        black: palette.pieceBlack,
        whiteText: contrastFor(palette.pieceWhite),
        blackText: contrastFor(palette.pieceBlack),
        whiteGlow: glowFor(palette.pieceWhite, ".42"),
        blackGlow: glowFor(palette.pieceBlack, ".5")
      };
    }
    return catalog.piecePreviewPalettes[skin] || catalog.piecePreviewPalettes.classic;
  };
  const previewVariables = (boardSkin, pieceSkin, palette) => {
    const board = boardPreviewPalette(boardSkin, palette);
    const piece = piecePreviewPalette(pieceSkin, palette);
    return {
      "--mc-preview-board-frame": board.frame,
      "--mc-preview-board-light": board.light,
      "--mc-preview-board-dark": board.dark,
      "--mc-preview-piece-frame": piece.frame,
      "--mc-preview-piece-white": piece.white,
      "--mc-preview-piece-black": piece.black,
      "--mc-preview-piece-white-text": piece.whiteText,
      "--mc-preview-piece-black-text": piece.blackText,
      "--mc-preview-piece-white-glow": piece.whiteGlow,
      "--mc-preview-piece-black-glow": piece.blackGlow
    };
  };
  const applyPreviewTheme = (preview, boardSkin, pieceSkin, palette) => {
    preview.dataset.boardSkin = boardSkin;
    preview.dataset.pieceSkin = pieceSkin;
    Object.entries(previewVariables(boardSkin, pieceSkin, palette)).forEach(([name, value]) => {
      preview.style.setProperty(name, value);
    });
  };
  const updateCosmeticPreview = (boardSkin, pieceSkin, palette) => {
    document.querySelectorAll("[data-palette-live-preview]").forEach((preview) => {
      applyPreviewTheme(preview, boardSkin, pieceSkin, palette);
    });
  };
  const applyPalette = (mastery) => {
    const palette = readPalette();
    const style = document.documentElement.style;
    style.setProperty("--mc-custom-board-light", palette.boardLight);
    style.setProperty("--mc-custom-board-dark", palette.boardDark);
    style.setProperty("--mc-custom-board-frame", palette.boardLight);
    style.setProperty("--mc-custom-piece-white", palette.pieceWhite);
    style.setProperty("--mc-custom-piece-white-text", contrastFor(palette.pieceWhite));
    style.setProperty("--mc-custom-piece-black", palette.pieceBlack);
    style.setProperty("--mc-custom-piece-black-text", contrastFor(palette.pieceBlack));
    style.setProperty("--mc-custom-piece-white-glow", glowFor(palette.pieceWhite, ".42"));
    style.setProperty("--mc-custom-piece-black-glow", glowFor(palette.pieceBlack, ".46"));
    const unlocked = isPaletteUnlocked(mastery.unlocks);
    document.querySelectorAll("[data-palette-color]").forEach((input) => {
      input.value = palette[input.dataset.paletteColor] || defaultPalette[input.dataset.paletteColor];
      input.disabled = !unlocked;
    });
    document.querySelectorAll("[data-palette-preset], [data-palette-reset]").forEach((button) => {
      const previewable = !!button.closest("[data-cosmetic-browser]");
      button.disabled = !unlocked && !previewable;
      button.dataset.cosmeticLocked = unlocked ? "false" : "true";
      button.setAttribute("aria-disabled", !unlocked && !previewable ? "true" : "false");
    });
    const activePreset = activePalettePreset(palette);
    document.querySelectorAll("[data-palette-reset]").forEach((button) => {
      const selected = activePreset === "base";
      button.classList.toggle("mc-palette-selected", selected);
      button.setAttribute("aria-pressed", selected ? "true" : "false");
    });
    document.querySelectorAll("[data-palette-preset]").forEach((button) => {
      const selected = button.dataset.palettePreset === activePreset;
      button.classList.toggle("mc-palette-selected", selected);
      button.setAttribute("aria-pressed", selected ? "true" : "false");
    });
    document.querySelectorAll("[data-palette-editor]").forEach((editor) => {
      editor.classList.toggle("is-locked", !unlocked);
      editor.classList.toggle("is-unlocked", unlocked);
    });
    document.querySelectorAll("[data-palette-unlock]").forEach((button) => {
      const previewable = !!button.closest("[data-cosmetic-browser]");
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked);
      button.dataset.cosmeticLocked = unlocked ? "false" : "true";
      button.setAttribute("aria-disabled", !unlocked && !previewable ? "true" : "false");
      button.title = unlocked ? "Paleta ganada por maestria" : lockedTitle("palette:custom");
    });
    document.querySelectorAll("[data-palette-status]").forEach((status) => {
      status.textContent = unlocked
        ? cosmeticLabels.unlocked
        : progression.progressLabel("palette:custom", mastery.stats);
      status.dataset.paletteState = unlocked ? "local" : "mastery";
    });
  };
  const read = (key, fallback, valid) => {
    try {
      const value = localStorage.getItem(key);
      return valid.includes(value) ? value : fallback;
    } catch (_error) {
      return fallback;
    }
  };
  const write = (key, value, valid) => {
    if (!valid.includes(value)) return;
    try {
      localStorage.setItem(key, value);
    } catch (_error) {}
  };
  const cosmeticRank = (selected, includedItem, unlocked) => {
    if (selected) return 0;
    if (includedItem) return 1;
    if (unlocked) return 2;
    return 3;
  };
  const renderMasterySummary = (mastery) => {
    const summary = progression.summary(mastery.stats, mastery.unlocks);
    document.querySelectorAll("[data-cosmetic-local-count]").forEach((element) => {
      element.textContent = summary.label;
    });
    document.querySelectorAll("[data-cosmetic-mastery-progress]").forEach((meter) => {
      meter.setAttribute("aria-valuemax", String(summary.total));
      meter.setAttribute("aria-valuenow", String(summary.completed));
      meter.querySelectorAll("i").forEach((fill) => {
        fill.style.width = `${summary.percent}%`;
      });
    });
  };
  const orderCosmeticOption = (button, rank) => {
    if (button.closest("[data-cosmetic-browser]")) {
      delete button.dataset.cosmeticRank;
      button.style.removeProperty("order");
      return;
    }
    button.dataset.cosmeticRank = String(rank);
    button.style.order = String(rank);
  };
  const selectionDetails = (selection, board, piece, palette, mastery) => {
    if (!selection) {
      return {
        board,
        piece,
        palette,
        title: "Tu estilo actual",
        rewardId: null,
        unlocked: true,
        equipped: true
      };
    }

    if (selection.kind === "board") {
      return {
        board: selection.value,
        piece,
        palette,
        title: previewLabels.board[selection.value],
        rewardId: unlockId("board", selection.value),
        unlocked: isUnlocked("board", selection.value, mastery.unlocks),
        equipped: selection.value === board
      };
    }

    if (selection.kind === "piece") {
      return {
        board,
        piece: selection.value,
        palette,
        title: previewLabels.piece[selection.value],
        rewardId: unlockId("piece", selection.value),
        unlocked: isUnlocked("piece", selection.value, mastery.unlocks),
        equipped: selection.value === piece
      };
    }

    if (selection.kind === "pack") {
      const config = packs[selection.value];
      return {
        board: config.board,
        piece: config.piece,
        palette,
        title: previewLabels.pack[selection.value],
        rewardId: `pack:${selection.value}`,
        unlocked: isPackUnlocked(selection.value, mastery.unlocks),
        equipped: config.board === board && config.piece === piece
      };
    }

    const selectedPalette = selection.value === "base"
      ? defaultPalette
      : palettePresets[selection.value] || palette;
    return {
      board: "custom",
      piece: "custom",
      palette: selectedPalette,
      title: previewLabels.palette[selection.value] || previewLabels.palette.custom,
      rewardId: "palette:custom",
      unlocked: isPaletteUnlocked(mastery.unlocks),
      equipped: board === "custom" && piece === "custom" && (
        selection.value === "custom" || paletteEquals(palette, selectedPalette)
      )
    };
  };
  const selectionControl = (browser, selection) => {
    if (!selection) return null;
    if (selection.kind === "board") {
      return browser.querySelector(`[data-board-skin-choice="${selection.value}"]`);
    }
    if (selection.kind === "piece") {
      return browser.querySelector(`[data-piece-skin-choice="${selection.value}"]`);
    }
    if (selection.kind === "pack") {
      return browser.querySelector(`[data-cosmetic-pack="${selection.value}"]`);
    }
    if (selection.value === "base") return browser.querySelector("[data-palette-reset]");
    if (selection.value === "custom") return browser.querySelector("[data-palette-unlock]");
    return browser.querySelector(`[data-palette-preset="${selection.value}"]`);
  };
  const renderCosmeticBrowser = (mastery, board, piece) => {
    const palette = readPalette();
    const details = selectionDetails(previewSelection, board, piece, palette, mastery);

    document.querySelectorAll("[data-cosmetic-browser]").forEach((browser) => {
      browser.querySelectorAll(".mc-skin-previewing").forEach((control) => {
        control.classList.remove("mc-skin-previewing");
      });
      const activeControl = selectionControl(browser, previewSelection);
      if (activeControl) activeControl.classList.add("mc-skin-previewing");

      browser.querySelectorAll("[data-cosmetic-preview-stage]").forEach((stage) => {
        applyPreviewTheme(stage, details.board, details.piece, details.palette);
      });
      browser.querySelectorAll("[data-cosmetic-preview-title]").forEach((title) => {
        title.textContent = details.title;
      });
      browser.querySelectorAll("[data-cosmetic-preview-status]").forEach((status) => {
        status.textContent = details.equipped
          ? "Equipado"
          : details.unlocked ? "Disponible" : "Bloqueado";
        status.dataset.previewState = details.equipped
          ? "equipped"
          : details.unlocked ? "available" : "locked";
      });
      browser.querySelectorAll("[data-cosmetic-preview-requirement]").forEach((requirement) => {
        requirement.textContent = details.equipped
          ? "Activo ahora"
          : details.unlocked
            ? "Listo para equipar"
            : progression.requirementLabel(details.rewardId);
      });
      browser.querySelectorAll("[data-cosmetic-preview-equip]").forEach((button) => {
        button.disabled = details.equipped || !details.unlocked;
        button.textContent = details.equipped
          ? "Equipado"
          : details.unlocked ? "Equipar" : "Bloqueado";
        button.dataset.previewState = details.equipped
          ? "equipped"
          : details.unlocked ? "available" : "locked";
      });
    });
  };
  const render = () => {
    const mastery = syncProgression();
    const storedBoard = read(boardKey, "classic", boards);
    const storedPiece = read(pieceKey, "classic", pieces);
    const board = isUnlocked("board", storedBoard, mastery.unlocks) ? storedBoard : "classic";
    const piece = isUnlocked("piece", storedPiece, mastery.unlocks) ? storedPiece : "classic";
    if (board !== storedBoard) write(boardKey, board, boards);
    if (piece !== storedPiece) write(pieceKey, piece, pieces);
    applyPalette(mastery);
    renderMasterySummary(mastery);
    updateCosmeticPreview(board, piece, readPalette());
    document.documentElement.dataset.boardSkin = board;
    document.documentElement.dataset.pieceSkin = piece;
    document.querySelectorAll(".mc-board-stack").forEach((stack) => stack.dataset.boardSkin = board);
    document.querySelectorAll(".mc-shell").forEach((shell) => {
      shell.dataset.pieceSkin = piece;
      pieces.forEach((skin) => shell.classList.toggle(`mc-piece-skin-${skin}`, piece === skin));
    });
    document.querySelectorAll("[data-board-skin-choice]").forEach((button) => {
      const skin = button.dataset.boardSkinChoice;
      const rewardId = unlockId("board", skin);
      const unlocked = isUnlocked("board", skin, mastery.unlocks);
      const includedItem = included.has(rewardId);
      const selected = skin === board && unlocked;
      const previewable = !!button.closest("[data-cosmetic-browser]");
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.dataset.cosmeticLocked = unlocked ? "false" : "true";
      button.setAttribute("aria-disabled", !unlocked && !previewable ? "true" : "false");
      button.setAttribute("aria-pressed", selected ? "true" : "false");
      if (!includedItem) {
        button.title = unlocked ? "Recompensa ganada por maestria" : lockedTitle(rewardId);
      }
      button.querySelectorAll("[data-cosmetic-status]").forEach((status) => {
        if (includedItem) {
          status.textContent = cosmeticLabels.included;
          status.dataset.cosmeticState = "included";
        } else {
          status.textContent = unlocked ? cosmeticLabels.unlocked : progression.progressLabel(rewardId, mastery.stats);
          status.dataset.cosmeticState = unlocked ? "local" : "mastery";
        }
      });
    });
    document.querySelectorAll("[data-piece-skin-choice]").forEach((button) => {
      const skin = button.dataset.pieceSkinChoice;
      const rewardId = unlockId("piece", skin);
      const unlocked = isUnlocked("piece", skin, mastery.unlocks);
      const includedItem = included.has(rewardId);
      const selected = skin === piece && unlocked;
      const previewable = !!button.closest("[data-cosmetic-browser]");
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.dataset.cosmeticLocked = unlocked ? "false" : "true";
      button.setAttribute("aria-disabled", !unlocked && !previewable ? "true" : "false");
      button.setAttribute("aria-pressed", selected ? "true" : "false");
      if (!includedItem) {
        button.title = unlocked ? "Recompensa ganada por maestria" : lockedTitle(rewardId);
      }
      button.querySelectorAll("[data-cosmetic-status]").forEach((status) => {
        if (includedItem) {
          status.textContent = cosmeticLabels.included;
          status.dataset.cosmeticState = "included";
        } else {
          status.textContent = unlocked ? cosmeticLabels.unlocked : progression.progressLabel(rewardId, mastery.stats);
          status.dataset.cosmeticState = unlocked ? "local" : "mastery";
        }
      });
    });
    document.querySelectorAll("[data-cosmetic-pack]").forEach((button) => {
      const pack = button.dataset.cosmeticPack;
      const config = packs[pack];
      if (!config) return;
      const rewardId = `pack:${pack}`;
      const unlocked = isPackUnlocked(pack, mastery.unlocks);
      const includedItem = !!config.included;
      const selected = unlocked && config.board === board && config.piece === piece;
      const previewable = !!button.closest("[data-cosmetic-browser]");
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.dataset.cosmeticLocked = unlocked ? "false" : "true";
      button.setAttribute("aria-disabled", !unlocked && !previewable ? "true" : "false");
      button.setAttribute("aria-pressed", selected ? "true" : "false");
      if (!includedItem) {
        button.title = unlocked ? "Conjunto ganado por maestria" : lockedTitle(rewardId);
      }
      button.querySelectorAll("[data-cosmetic-pack-status]").forEach((status) => {
        status.textContent = includedItem
          ? cosmeticLabels.included
          : unlocked
            ? cosmeticLabels.unlocked
            : progression.progressLabel(rewardId, mastery.stats);
        status.dataset.cosmeticState = includedItem ? "included" : unlocked ? "local" : "mastery";
      });
    });
    renderCosmeticBrowser(mastery, board, piece);
  };
  const setPreviewSelection = (kind, value) => {
    const valid = (
      (kind === "board" && boards.includes(value)) ||
      (kind === "piece" && pieces.includes(value)) ||
      (kind === "pack" && !!packs[value]) ||
      (kind === "palette" && ["base", "custom", ...Object.keys(palettePresets)].includes(value))
    );
    if (!valid) return false;
    previewSelection = {kind, value};
    render();
    return true;
  };
  const equipPreview = () => {
    if (!previewSelection) return false;

    if (previewSelection.kind === "board") {
      if (!isUnlocked("board", previewSelection.value)) return false;
      write(boardKey, previewSelection.value, boards);
    } else if (previewSelection.kind === "piece") {
      if (!isUnlocked("piece", previewSelection.value)) return false;
      write(pieceKey, previewSelection.value, pieces);
    } else if (previewSelection.kind === "pack") {
      const config = packs[previewSelection.value];
      if (!config || !isPackUnlocked(previewSelection.value)) return false;
      write(boardKey, config.board, boards);
      write(pieceKey, config.piece, pieces);
    } else {
      if (!isPaletteUnlocked()) return false;
      if (previewSelection.value === "base") writePalette(defaultPalette);
      if (palettePresets[previewSelection.value]) writePalette(palettePresets[previewSelection.value]);
      write(boardKey, "custom", boards);
      write(pieceKey, "custom", pieces);
    }

    render();
    return true;
  };
  window.ManaChessCosmetics = {
    choosePack: (pack) => {
      const config = packs[pack];
      if (!config || !isPackUnlocked(pack)) return false;
      write(boardKey, config.board, boards);
      write(pieceKey, config.piece, pieces);
      render();
      return true;
    },
    chooseBoard: (skin) => {
      if (!isUnlocked("board", skin)) return false;
      write(boardKey, skin, boards);
      render();
      return true;
    },
    choosePiece: (skin) => {
      if (!isUnlocked("piece", skin)) return false;
      write(pieceKey, skin, pieces);
      render();
      return true;
    },
    choosePalette: (preset) => {
      if (!isPaletteUnlocked()) return false;
      if (palettePresets[preset]) writePalette(palettePresets[preset]);
      write(boardKey, "custom", boards);
      write(pieceKey, "custom", pieces);
      render();
      return true;
    },
    resetPalette: () => {
      if (!isPaletteUnlocked()) return false;
      writePalette(defaultPalette);
      write(boardKey, "custom", boards);
      write(pieceKey, "custom", pieces);
      render();
      return true;
    },
    setPaletteColor: (key, value) => {
      if (!validHex(value) || !Object.prototype.hasOwnProperty.call(defaultPalette, key)) return;
      if (!isPaletteUnlocked()) return false;
      const palette = readPalette();
      palette[key] = value;
      writePalette(palette);
      if (key.startsWith("board")) write(boardKey, "custom", boards);
      if (key.startsWith("piece")) write(pieceKey, "custom", pieces);
      render();
      return true;
    },
    previewBoard: (skin) => setPreviewSelection("board", skin),
    previewPiece: (skin) => setPreviewSelection("piece", skin),
    previewPack: (pack) => setPreviewSelection("pack", pack),
    previewPalette: (preset) => setPreviewSelection("palette", preset),
    equipPreview,
    previewSelection: () => previewSelection ? {...previewSelection} : null,
    render
  };
  document.addEventListener("click", (event) => {
    const browser = event.target.closest("[data-cosmetic-browser]");
    if (browser) {
      const equip = event.target.closest("[data-cosmetic-preview-equip]");
      const pack = event.target.closest("[data-cosmetic-pack]");
      const paletteReset = event.target.closest("[data-palette-reset]");
      const palettePreset = event.target.closest("[data-palette-preset]");
      const paletteUnlock = event.target.closest("[data-palette-unlock]");
      const piece = event.target.closest("[data-piece-skin-choice]");
      const board = event.target.closest("[data-board-skin-choice]");
      const control = equip || pack || paletteReset || palettePreset || paletteUnlock || piece || board;

      if (control) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (equip) equipPreview();
        else if (pack) setPreviewSelection("pack", pack.dataset.cosmeticPack);
        else if (paletteReset) setPreviewSelection("palette", "base");
        else if (palettePreset) setPreviewSelection("palette", palettePreset.dataset.palettePreset);
        else if (paletteUnlock) setPreviewSelection("palette", "custom");
        else if (piece) setPreviewSelection("piece", piece.dataset.pieceSkinChoice);
        else if (board) setPreviewSelection("board", board.dataset.boardSkinChoice);
        return;
      }
    }

    const pack = event.target.closest("[data-cosmetic-pack]");
    if (pack && !pack.disabled) {
      event.preventDefault();
      window.ManaChessCosmetics.choosePack(pack.dataset.cosmeticPack);
      return;
    }
    const paletteReset = event.target.closest("[data-palette-reset]");
    if (paletteReset && !paletteReset.disabled) {
      event.preventDefault();
      window.ManaChessCosmetics.resetPalette();
      return;
    }
    const palettePreset = event.target.closest("[data-palette-preset]");
    if (palettePreset && !palettePreset.disabled) {
      event.preventDefault();
      window.ManaChessCosmetics.choosePalette(palettePreset.dataset.palettePreset);
      return;
    }
    const paletteUnlock = event.target.closest("[data-palette-unlock]");
    if (paletteUnlock) {
      event.preventDefault();
      window.ManaChessCosmetics.choosePalette();
      return;
    }
    const piece = event.target.closest("[data-piece-skin-choice]");
    if (piece && !piece.disabled) {
      event.preventDefault();
      window.ManaChessCosmetics.choosePiece(piece.dataset.pieceSkinChoice);
      return;
    }
    const board = event.target.closest("[data-board-skin-choice]");
    if (board && !board.disabled) {
      event.preventDefault();
      window.ManaChessCosmetics.chooseBoard(board.dataset.boardSkinChoice);
    }
  }, true);
  document.addEventListener("input", (event) => {
    const input = event.target.closest("[data-palette-color]");
    if (!input || input.disabled) return;
    window.ManaChessCosmetics.setPaletteColor(input.dataset.paletteColor, input.value);
  }, true);
  document.addEventListener("DOMContentLoaded", render, {once: true});
  document.addEventListener("phx:page-loading-stop", render);
  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      render();
    });
  }).observe(document.documentElement, {childList: true, subtree: true});
})();
