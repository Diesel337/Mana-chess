// Shared cosmetic catalog. Keep the priv/static copy in sync until the JS
// pipeline bundles these modules.
(() => {
  const boardPreviewPalettes = {
    classic: {frame: "#f7f2e8", light: "#f3eee2", dark: "#171817"},
    gilded: {frame: "#fff0b6", light: "#f4d477", dark: "#6e3b1f"},
    arcane: {frame: "#9a7dff", light: "#8fe7c8", dark: "#241745"},
    crystal: {frame: "#dff8ff", light: "#ccecff", dark: "#27456f"},
    elemental: {frame: "#ffd27a", light: "#efb24f", dark: "#164f50"},
  }

  const piecePreviewPalettes = {
    classic: {
      frame: "#e6bd68",
      white: "#f7ebce",
      black: "#171a17",
      whiteText: "#171a12",
      blackText: "#7c5bd6",
      whiteGlow: "rgba(247, 235, 206, .36)",
      blackGlow: "rgba(124, 91, 214, .44)",
    },
    runes: {
      frame: "#8bd9bd",
      white: "#8bd9bd",
      black: "#120b22",
      whiteText: "#03251d",
      blackText: "#c7b3ff",
      whiteGlow: "rgba(139, 217, 189, .48)",
      blackGlow: "rgba(168, 132, 255, .52)",
    },
    arcane: {
      frame: "#9a7dff",
      white: "#f2d989",
      black: "#160d2b",
      whiteText: "#10251f",
      blackText: "#d5c6ff",
      whiteGlow: "rgba(242, 217, 137, .5)",
      blackGlow: "rgba(154, 125, 255, .56)",
    },
    crystal: {
      frame: "#dff8ff",
      white: "#96e7ff",
      black: "#13243f",
      whiteText: "#10233f",
      blackText: "#b8efff",
      whiteGlow: "rgba(91, 139, 230, .54)",
      blackGlow: "rgba(122, 163, 255, .5)",
    },
    elemental: {
      frame: "#ffd27a",
      white: "#ffd474",
      black: "#103c42",
      whiteText: "#3d1707",
      blackText: "#8ff3dc",
      whiteGlow: "rgba(255, 132, 63, .56)",
      blackGlow: "rgba(66, 222, 196, .5)",
    },
  }

  window.ManaChessCosmeticCatalog = Object.freeze({
    boards: ["classic", "gilded", "arcane", "crystal", "elemental", "custom"],
    pieces: ["classic", "runes", "arcane", "crystal", "elemental", "custom"],
    packs: {
      classic: {board: "classic", piece: "classic", included: true, unlocks: []},
      mana: {board: "gilded", piece: "runes", included: true, unlocks: []},
      arcane: {board: "arcane", piece: "arcane", unlocks: ["board:arcane", "piece:arcane"]},
      crystal: {board: "crystal", piece: "crystal", unlocks: ["board:crystal", "piece:crystal"]},
      elemental: {board: "elemental", piece: "elemental", unlocks: ["board:elemental", "piece:elemental"]},
    },
    includedIds: ["board:classic", "board:gilded", "piece:classic", "piece:runes"],
    premiumBoards: ["arcane", "crystal", "elemental", "custom"],
    premiumPieces: ["arcane", "crystal", "elemental", "custom"],
    localUnlockIds: [
      "board:arcane",
      "board:crystal",
      "board:elemental",
      "piece:arcane",
      "piece:crystal",
      "piece:elemental",
      "board:custom",
      "piece:custom",
      "palette:custom",
    ],
    boardPreviewPalettes,
    piecePreviewPalettes,
  })
})()
