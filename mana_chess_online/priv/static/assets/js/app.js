const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
  LocalStats: {
    mounted() {
      this.lastResultKey = null;
      this.storageKey = "mana-chess-local-stats";
      this.soundKey = "mana-chess-sound-enabled";
      this.skinKey = "mana-chess-board-skin";
      this.pieceSkinKey = "mana-chess-piece-skin";
      this.audioContext = null;
      this.lastSoundState = this.soundState();
      this.handleReset = event => {
        if (!event.target.closest("[data-stats-reset]")) return;
        localStorage.removeItem(this.storageKey);
        this.lastResultKey = null;
        this.renderStats();
      };
      this.handleInviteCopy = event => {
        const button = event.target.closest("[data-copy-invite]");
        if (!button) return;
        event.preventDefault();
        this.copyInvite(button);
      };
      this.handleSoundToggle = event => {
        const button = event.target.closest("[data-sound-toggle]");
        if (!button) return;
        event.preventDefault();
        const enabled = !this.soundEnabled();
        this.setSoundEnabled(enabled);
        this.renderSoundToggle();
        if (enabled) this.playSound("ready");
      };
      this.handleSoundAction = event => {
        const control = event.target.closest("[data-sound-action]");
        if (!control || control.disabled) return;
        if (control.matches("[data-piece-skin-choice]")) {
          event.preventDefault();
          event.stopImmediatePropagation();
          this.setPieceSkin(control.dataset.pieceSkinChoice);
          this.renderPieceSkin();
          if (this.soundEnabled()) this.playSound("skin");
          return;
        }
        if (!this.soundEnabled()) return;
        this.playSound(control.dataset.soundAction || "tap");
      };
      this.handleSkinChoice = event => {
        const control = event.target.closest("[data-board-skin-choice]");
        if (!control || control.disabled) return;
        event.preventDefault();
        this.setBoardSkin(control.dataset.boardSkinChoice);
        this.renderBoardSkin();
        this.playSound("skin");
      };
      this.handlePieceSkinChoice = event => {
        const control = event.target.closest("[data-piece-skin-choice]");
        if (!control || control.disabled) return;
        event.preventDefault();
        this.setPieceSkin(control.dataset.pieceSkinChoice);
        this.renderPieceSkin();
        this.playSound("skin");
      };
      this.el.addEventListener("click", this.handleReset);
      this.el.addEventListener("click", this.handleInviteCopy);
      this.el.addEventListener("click", this.handleSoundToggle);
      this.el.addEventListener("click", this.handleSoundAction);
      this.el.addEventListener("click", this.handleSkinChoice);
      this.el.addEventListener("click", this.handlePieceSkinChoice);
      this.recordResult();
      this.renderStats();
      this.renderSoundToggle();
      this.renderBoardSkin();
      this.renderPieceSkin();
    },

    updated() {
      this.recordResult();
      this.renderStats();
      this.renderSoundToggle();
      this.renderBoardSkin();
      this.renderPieceSkin();
      this.playChangedSound();
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleReset);
      this.el.removeEventListener("click", this.handleInviteCopy);
      this.el.removeEventListener("click", this.handleSoundToggle);
      this.el.removeEventListener("click", this.handleSoundAction);
      this.el.removeEventListener("click", this.handleSkinChoice);
      this.el.removeEventListener("click", this.handlePieceSkinChoice);
    },

    readStats() {
      try {
        return JSON.parse(localStorage.getItem(this.storageKey)) || this.emptyStats();
      } catch (_error) {
        return this.emptyStats();
      }
    },

    writeStats(stats) {
      localStorage.setItem(this.storageKey, JSON.stringify(stats));
    },

    emptyStats() {
      return {played: 0, wins: 0, losses: 0, draws: 0, seen: []};
    },

    recordResult() {
      const key = this.el.dataset.resultKey;
      const outcome = this.el.dataset.resultOutcome;

      if (!key || !outcome) {
        this.lastResultKey = null;
        return;
      }

      if (this.lastResultKey === key) return;

      const stats = this.readStats();
      stats.seen = Array.isArray(stats.seen) ? stats.seen : [];

      if (stats.seen.includes(key)) {
        this.lastResultKey = key;
        return;
      }

      stats.played = (stats.played || 0) + 1;

      if (outcome === "win") stats.wins = (stats.wins || 0) + 1;
      if (outcome === "loss") stats.losses = (stats.losses || 0) + 1;
      if (outcome === "draw") stats.draws = (stats.draws || 0) + 1;

      stats.seen = [key, ...stats.seen].slice(0, 40);
      this.writeStats(stats);
      this.lastResultKey = key;
    },

    renderStats() {
      const stats = this.readStats();

      for (const [name, value] of Object.entries({
        played: stats.played || 0,
        wins: stats.wins || 0,
        losses: stats.losses || 0,
        draws: stats.draws || 0
      })) {
        this.el.querySelectorAll(`[data-stat="${name}"]`).forEach(node => {
          node.textContent = value;
        });
      }
    },

    soundEnabled() {
      return localStorage.getItem(this.soundKey) === "on";
    },

    setSoundEnabled(enabled) {
      if (enabled) {
        localStorage.setItem(this.soundKey, "on");
      } else {
        localStorage.removeItem(this.soundKey);
      }
    },

    renderSoundToggle() {
      const enabled = this.soundEnabled();
      this.el.querySelectorAll("[data-sound-toggle]").forEach(button => {
        button.textContent = enabled ? "Sonido On" : "Sonido Off";
        button.setAttribute("aria-pressed", enabled ? "true" : "false");
        button.classList.toggle("mc-sound-toggle-on", enabled);
      });
    },

    boardSkin() {
      const skin = localStorage.getItem(this.skinKey);
      return ["mana", "arcane"].includes(skin) ? skin : "mana";
    },

    setBoardSkin(skin) {
      if (!["mana", "arcane"].includes(skin)) return;
      localStorage.setItem(this.skinKey, skin);
    },

    renderBoardSkin() {
      const skin = this.boardSkin();

      this.el.querySelectorAll("[data-board-skin-target]").forEach(node => {
        node.dataset.boardSkin = skin;
      });

      this.el.querySelectorAll("[data-board-skin-choice]").forEach(button => {
        const selected = button.dataset.boardSkinChoice === skin;
        button.classList.toggle("mc-skin-selected", selected);
        button.setAttribute("aria-pressed", selected ? "true" : "false");
      });
    },

    pieceSkin() {
      const skin = localStorage.getItem(this.pieceSkinKey);
      return ["classic", "runes"].includes(skin) ? skin : "classic";
    },

    setPieceSkin(skin) {
      if (!["classic", "runes"].includes(skin)) return;
      localStorage.setItem(this.pieceSkinKey, skin);
    },

    renderPieceSkin() {
      const skin = this.pieceSkin();
      this.el.dataset.pieceSkin = skin;
      this.el.classList.toggle("mc-piece-skin-classic", skin === "classic");
      this.el.classList.toggle("mc-piece-skin-runes", skin === "runes");
      document.documentElement.dataset.pieceSkin = skin;

      this.el.querySelectorAll("[data-piece-skin-choice]").forEach(button => {
        const selected = button.dataset.pieceSkinChoice === skin;
        button.classList.toggle("mc-skin-selected", selected);
        button.setAttribute("aria-pressed", selected ? "true" : "false");
      });
    },

    soundState() {
      return {
        gameId: this.el.dataset.soundGameId || "",
        status: this.el.dataset.soundStatus || "",
        logCount: Number.parseInt(this.el.dataset.soundLogCount || "0", 10),
        alert: this.el.dataset.soundAlert || "",
        resultKey: this.el.dataset.resultKey || "",
        result: this.el.dataset.resultOutcome || "",
      };
    },

    playChangedSound() {
      const current = this.soundState();
      const previous = this.lastSoundState;
      this.lastSoundState = current;

      if (!previous || !this.soundEnabled()) return;

      if (current.result && current.resultKey && current.resultKey !== previous.resultKey) {
        this.playSound("final");
        return;
      }

      if (current.alert && current.alert !== previous.alert) {
        this.playSound("alert");
        return;
      }

      if (current.gameId && current.gameId === previous.gameId && current.logCount > previous.logCount) {
        this.playSound("move");
        return;
      }

      if (current.status && current.status !== previous.status) {
        this.playSound("state");
      }
    },

    playSound(kind) {
      if (!this.soundEnabled()) return;

      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) return;

      try {
        this.audioContext = this.audioContext || new AudioContext();
        if (this.audioContext.state === "suspended") this.audioContext.resume();

        const tones = {
          ready: [[660, 0, .06, "sine"], [880, .07, .08, "sine"]],
          tap: [[480, 0, .035, "triangle"]],
          mode: [[520, 0, .045, "sine"], [720, .045, .055, "sine"]],
          private: [[620, 0, .045, "triangle"], [880, .05, .07, "sine"]],
          skin: [[390, 0, .04, "triangle"], [590, .045, .06, "sine"], [780, .095, .06, "sine"]],
          copy: [[760, 0, .04, "sine"], [980, .045, .055, "sine"]],
          reset: [[280, 0, .05, "triangle"], [210, .05, .06, "triangle"]],
          move: [[360, 0, .045, "triangle"], [520, .045, .065, "triangle"]],
          alert: [[220, 0, .08, "sawtooth"], [180, .075, .09, "sawtooth"]],
          state: [[440, 0, .07, "sine"], [660, .07, .08, "sine"]],
          final: [[523, 0, .08, "triangle"], [659, .08, .08, "triangle"], [784, .16, .12, "triangle"]],
        };

        for (const tone of tones[kind] || tones.move) {
          this.playTone(...tone);
        }
      } catch (_error) {
      }
    },

    playTone(frequency, delay, duration, type) {
      const context = this.audioContext;
      const start = context.currentTime + delay;
      const oscillator = context.createOscillator();
      const gain = context.createGain();

      oscillator.type = type;
      oscillator.frequency.setValueAtTime(frequency, start);
      gain.gain.setValueAtTime(0.0001, start);
      gain.gain.linearRampToValueAtTime(0.035, start + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);

      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(start);
      oscillator.stop(start + duration + 0.03);
    },

    copyInvite(button) {
      const inviteUrl = new URL(button.dataset.copyInvite, window.location.origin).toString();
      const originalText = button.textContent;
      const markCopied = () => {
        button.textContent = "Copiado";
        this.playSound("copy");
        window.clearTimeout(button.copyInviteTimer);
        button.copyInviteTimer = window.setTimeout(() => {
          button.textContent = originalText;
        }, 1400);
      };

      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(inviteUrl).then(markCopied).catch(() => {
          this.fallbackCopy(inviteUrl, markCopied);
        });
      } else {
        this.fallbackCopy(inviteUrl, markCopied);
      }
    },

    fallbackCopy(text, callback) {
      const field = document.createElement("textarea");
      field.value = text;
      field.setAttribute("readonly", "");
      field.style.position = "fixed";
      field.style.top = "-1000px";
      field.style.opacity = "0";
      document.body.appendChild(field);
      field.select();

      try {
        document.execCommand("copy");
        callback();
      } finally {
        field.remove();
      }
    }
  },

  BoardDrag: {
    mounted() {
      this.drag = null;
      this.suppressClick = false;

      this.el.addEventListener("pointerdown", event => {
        const square = event.target.closest(".mc-square");
        const piece = square && square.querySelector(".mc-piece:not(:empty)");

        if (!square || !piece) return;

        this.drag = {
          fromR: square.dataset.r,
          fromC: square.dataset.c,
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

        const target = document.elementFromPoint(event.clientX, event.clientY);
        const square = target && target.closest(".mc-square");

        if (!square) return;

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
      });

      this.el.addEventListener("click", event => {
        if (this.suppressClick) {
          this.suppressClick = false;
          event.preventDefault();
          event.stopPropagation();
        }
      }, true);
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
