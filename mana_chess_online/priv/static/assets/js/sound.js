// UI sound helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  let audioContext = null;

  const patterns = {
    ready: [[660, 0, .06, "sine"], [880, .07, .08, "sine"]],
    tap: [[480, 0, .035, "triangle", .028]],
    mode: [[520, 0, .045, "sine", .03], [720, .045, .055, "sine", .026]],
    private: [[620, 0, .045, "triangle", .03], [880, .05, .07, "sine", .026]],
    skin: [[390, 0, .04, "triangle", .026], [590, .045, .06, "sine", .024], [780, .095, .06, "sine", .02]],
    copy: [[760, 0, .04, "sine", .026], [980, .045, .055, "sine", .022]],
    chat: [[620, 0, .04, "sine", .018], [820, .045, .055, "triangle", .016]],
    reset: [[280, 0, .05, "triangle", .032, 230], [210, .05, .06, "triangle", .026, 170]],
    move: [[360, 0, .04, "triangle", .024, 410], [520, .042, .058, "triangle", .02, 470]],
    capture: [[140, 0, .05, "sawtooth", .048, 95], [220, .035, .075, "square", .04, 160], [520, .105, .055, "triangle", .028, 760], [980, .15, .04, "sine", .018, 1180]],
    check: [[988, 0, .045, "square", .042], [698, .04, .075, "triangle", .034], [1175, .11, .06, "square", .032], [1568, .175, .06, "sine", .022]],
    alert: [[220, 0, .08, "sawtooth", .035, 185], [180, .075, .09, "sawtooth", .028, 150]],
    state: [[440, 0, .07, "sine", .026], [660, .07, .08, "sine", .022]],
    draw: [[440, 0, .08, "triangle", .026], [554, .08, .08, "triangle", .022], [440, .18, .11, "sine", .018]],
    final: [[523, 0, .08, "triangle", .03], [659, .08, .08, "triangle", .027], [784, .16, .12, "triangle", .024], [988, .27, .11, "sine", .02]],
    win: [[523, 0, .07, "triangle", .032], [659, .07, .07, "triangle", .03], [784, .14, .1, "triangle", .028], [1046, .24, .13, "sine", .024], [1318, .36, .11, "sine", .018]],
    loss: [[392, 0, .09, "triangle", .032, 360], [330, .095, .11, "triangle", .028, 294], [247, .2, .15, "sine", .024, 220], [196, .34, .12, "sine", .018, 185]]
  };

  const enabled = (soundKey) => localStorage.getItem(soundKey) === "on";

  const setEnabled = (soundKey, nextEnabled) => {
    if (nextEnabled) {
      localStorage.setItem(soundKey, "on");
    } else {
      localStorage.removeItem(soundKey);
    }
  };

  const volume = (volumeKey) => {
    const stored = Number.parseInt(localStorage.getItem(volumeKey) || "70", 10);
    if (Number.isNaN(stored)) return 0.7;
    return Math.min(1, Math.max(0, stored / 100));
  };

  const setVolume = (volumeKey, value) => {
    const percent = Math.min(100, Math.max(0, Number.parseInt(value || "70", 10)));
    localStorage.setItem(volumeKey, String(Number.isNaN(percent) ? 70 : percent));
  };

  const render = (root, {soundKey, volumeKey}) => {
    const isEnabled = enabled(soundKey);
    const percent = Math.round(volume(volumeKey) * 100);

    root.querySelectorAll("[data-sound-control]").forEach((control) => {
      control.classList.toggle("mc-sound-control-muted", !isEnabled);
    });
    root.querySelectorAll("[data-sound-toggle]").forEach((button) => {
      const label = button.querySelector("[data-sound-toggle-label]");
      const copy = button.querySelector("[data-sound-toggle-copy]");
      if (copy) copy.textContent = "Sonido";
      if (label) {
        label.textContent = isEnabled ? "ON" : "OFF";
      } else {
        button.textContent = isEnabled ? "Sonido ON" : "Sonido OFF";
      }
      button.setAttribute("aria-pressed", isEnabled ? "true" : "false");
      button.setAttribute("aria-label", isEnabled ? "Apagar sonido" : "Encender sonido");
      button.title = isEnabled ? "Apagar sonido" : "Encender sonido";
      button.classList.toggle("mc-sound-toggle-on", isEnabled);
    });
    root.querySelectorAll("[data-sound-volume]").forEach((input) => {
      input.value = percent;
      input.style.setProperty("--sound-volume", `${percent}%`);
      input.setAttribute("aria-valuetext", `${percent}%`);
      input.setAttribute("aria-label", `Volumen de sonido ${percent}%`);
    });
    root.querySelectorAll("[data-sound-volume-label]").forEach((label) => {
      label.textContent = `${percent}%`;
    });
  };

  const playTone = (tone, currentVolume) => {
    const [frequency, delay, duration, type, peak = .035, endFrequency = frequency] = tone;
    if (currentVolume <= 0) return;

    const start = audioContext.currentTime + delay;
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();

    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, start);
    if (endFrequency !== frequency) {
      oscillator.frequency.exponentialRampToValueAtTime(Math.max(1, endFrequency), start + duration);
    }
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.linearRampToValueAtTime(peak * currentVolume, start + 0.01);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);

    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.start(start);
    oscillator.stop(start + duration + 0.03);
  };

  const play = (kind, {soundKey, volumeKey}) => {
    if (!enabled(soundKey)) return;

    const AudioContext = window.AudioContext || window.webkitAudioContext;
    if (!AudioContext) return;

    try {
      audioContext = audioContext || new AudioContext();
      if (audioContext.state === "suspended") audioContext.resume();

      const currentVolume = volume(volumeKey);
      for (const tone of patterns[kind] || patterns.move) {
        playTone(tone, currentVolume);
      }
    } catch (_error) {
    }
  };

  window.ManaChessSound = {enabled, patterns, play, render, setEnabled, setVolume, volume};
})();
