// Sound hook adapter. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const sound = () => window.ManaChessSound;
  const soundState = () => window.ManaChessSoundState;

  const enabled = hook => sound().enabled(hook.soundKey);

  const setEnabled = (hook, value) => {
    sound().setEnabled(hook.soundKey, value);
  };

  const volume = hook => sound().volume(hook.soundVolumeKey);

  const setVolume = (hook, value) => {
    sound().setVolume(hook.soundVolumeKey, value);
  };

  const renderToggle = hook => {
    sound().render(hook.el, {
      soundKey: hook.soundKey,
      volumeKey: hook.soundVolumeKey,
    });
  };

  const state = hook => soundState().state(hook.el);

  const play = (hook, kind) => {
    sound().play(kind, {
      soundKey: hook.soundKey,
      volumeKey: hook.soundVolumeKey,
    });
  };

  const playChanged = hook => {
    const current = state(hook);
    const previous = hook.lastSoundState;
    hook.lastSoundState = current;
    hook.emitDesktopState(current, previous);

    const changedSound = soundState().changedSound(current, previous, enabled(hook));
    if (changedSound) play(hook, changedSound);
  };

  window.ManaChessSoundSession = {
    enabled,
    play,
    playChanged,
    renderToggle,
    setEnabled,
    setVolume,
    state,
    volume,
  };
})();
