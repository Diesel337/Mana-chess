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
  const syncProgression = () => {
    const stats = progression.readStats(localStorage, statsKey);
    const synced = progression.syncUnlocks(stats, readUnlocks());
    if (synced.changed) writeUnlocks(synced.unlocks);
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
  const updateCosmeticPreview = (boardSkin, pieceSkin, palette) => {
    const board = boardPreviewPalette(boardSkin, palette);
    const piece = piecePreviewPalette(pieceSkin, palette);
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
      "--mc-preview-piece-black-glow": piece.blackGlow
    };
    document.querySelectorAll("[data-palette-live-preview]").forEach((preview) => {
      preview.dataset.boardSkin = boardSkin;
      preview.dataset.pieceSkin = pieceSkin;
      Object.entries(vars).forEach(([name, value]) => preview.style.setProperty(name, value));
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
      button.disabled = !unlocked;
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
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked);
      button.setAttribute("aria-disabled", unlocked ? "false" : "true");
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
    button.dataset.cosmeticRank = String(rank);
    button.style.order = String(rank);
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
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.setAttribute("aria-disabled", unlocked ? "false" : "true");
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
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.setAttribute("aria-disabled", unlocked ? "false" : "true");
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
      orderCosmeticOption(button, cosmeticRank(selected, includedItem, unlocked));
      button.classList.toggle("mc-skin-selected", selected);
      button.classList.toggle("mc-skin-locked", !unlocked);
      button.classList.toggle("mc-skin-unlocked", unlocked && !includedItem);
      button.setAttribute("aria-disabled", unlocked ? "false" : "true");
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
    render
  };
  document.addEventListener("click", (event) => {
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
