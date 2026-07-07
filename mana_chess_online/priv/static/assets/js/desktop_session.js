// Desktop hook adapter. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const controller = hook => hook.desktopController();

  const state = hook => controller(hook).state();

  const bridge = hook => controller(hook).bridge();

  const payload = (hook, extra = {}) => (
    controller(hook).eventPayload(hook.el, hook.viewKey(), hook.soundState(), extra)
  );

  const sendEvent = (hook, name, extra = {}, key = "") => {
    controller(hook).sendEvent(
      hook.desktopState,
      hook.el,
      hook.viewKey(),
      hook.soundState(),
      name,
      extra,
      key
    );
  };

  const emitView = hook => {
    controller(hook).emitView(hook.desktopState, hook.el, hook.viewKey(), hook.soundState());
  };

  const emitState = (hook, current, previous) => {
    controller(hook).emitState(hook.desktopState, hook.el, hook.viewKey(), current, previous);
  };

  const statusIsPlaying = (hook, status) => controller(hook).statusIsPlaying(status);

  const copyShareLink = (hook, url) => controller(hook).copyShareLink(url);

  window.ManaChessDesktopSession = {
    bridge,
    copyShareLink,
    emitState,
    emitView,
    payload,
    sendEvent,
    state,
    statusIsPlaying,
  };
})();
