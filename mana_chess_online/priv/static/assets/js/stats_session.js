// Local stats hook adapter. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const localStats = () => window.ManaChessLocalStats;
  const resultRecording = () => window.ManaChessResultRecording;

  const read = hook => localStats().read(hook.storageKey);

  const write = (hook, stats) => {
    localStats().write(hook.storageKey, stats);
  };

  const empty = () => localStats().empty();

  const render = hook => {
    localStats().render(hook.el, hook.storageKey);
  };

  const recordResult = hook => {
    hook.lastResultKey = resultRecording().record({
      localStats: localStats(),
      storageKey: hook.storageKey,
      resultKey: hook.el.dataset.resultKey,
      outcome: hook.el.dataset.resultOutcome,
      lastResultKey: hook.lastResultKey,
      onRecorded: event => hook.sendDesktopEvent(event.name, event.payload, event.key),
    });
  };

  window.ManaChessStatsSession = {
    empty,
    localStats,
    read,
    recordResult,
    render,
    resultRecording,
    write,
  };
})();
