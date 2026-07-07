// Desktop/Steam bridge helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const bridge = () => {
    const target = window.ManaChessDesktop;
    return target && typeof target.sendEvent === "function" ? target : null;
  };

  const desktopInfo = () => {
    const target = window.ManaChessDesktop;
    return typeof target?.getInfo === "function" ? target.getInfo() : null;
  };

  const installMetadata = () => {
    const info = desktopInfo();
    if (new URLSearchParams(window.location.search).get("desktop") !== "1" && !info?.isDesktop) return;

    document.documentElement.dataset.desktop = "true";
    if (info?.channel) document.documentElement.dataset.desktopChannel = info.channel;
    if (info?.version) document.documentElement.dataset.desktopVersion = info.version;
  };

  const state = () => ({eventKeys: new Set(), viewKey: null});

  const eventPayload = (root, viewKey, soundState, payload = {}) => ({
    path: window.location.pathname,
    screen: soundState.gameId ? "game" : "lobby",
    view: viewKey,
    gameId: soundState.gameId,
    status: soundState.status,
    ...payload,
  });

  const rememberEvent = (desktopState, eventKey) => {
    if (!eventKey) return true;
    if (desktopState.eventKeys.has(eventKey)) return false;

    desktopState.eventKeys.add(eventKey);
    if (desktopState.eventKeys.size > 80) {
      desktopState.eventKeys = new Set([...desktopState.eventKeys].slice(-40));
    }
    return true;
  };

  const sendEvent = (desktopState, root, viewKey, soundState, name, payload = {}, key = "") => {
    const target = bridge();
    if (!target) return;

    const eventKey = key || `${name}:${payload.gameId || ""}:${payload.status || ""}:${payload.result || ""}`;
    if (!rememberEvent(desktopState, eventKey)) return;

    try {
      target.sendEvent(name, eventPayload(root, viewKey, soundState, payload));
    } catch (_error) {
    }
  };

  const emitView = (desktopState, root, viewKey, soundState) => {
    const screen = soundState.gameId ? "game" : "lobby";
    const key = `${screen}:${soundState.gameId || "lobby"}:${window.location.pathname}`;
    if (key === desktopState.viewKey) return;

    desktopState.viewKey = key;
    sendEvent(desktopState, root, viewKey, soundState, "screen.viewed", {screen}, `screen.viewed:${key}`);
  };

  const statusIsPlaying = (status = "") => (
    status === ":playing" || status.includes("starting") || status.includes("promotion")
  );

  const emitState = (desktopState, root, viewKey, current, previous) => {
    if (!current.gameId) return;

    if (!previous || current.gameId !== previous.gameId) {
      sendEvent(desktopState, root, viewKey, current, "match.opened", {}, `match.opened:${current.gameId}`);
    }

    if (!current.status || (previous && current.status === previous.status)) return;

    sendEvent(
      desktopState,
      root,
      viewKey,
      current,
      "match.status_changed",
      {previousStatus: previous?.status || ""},
      `match.status_changed:${current.gameId}:${current.status}`
    );

    if (statusIsPlaying(current.status) && !statusIsPlaying(previous?.status || "")) {
      sendEvent(desktopState, root, viewKey, current, "match.started", {}, `match.started:${current.gameId}`);
    }
  };

  const copyShareLink = (url) => {
    const target = window.ManaChessDesktop;
    return target && typeof target.copyShareLink === "function" ? target.copyShareLink(url) : null;
  };

  installMetadata();

  window.ManaChessDesktopBridge = {
    bridge,
    copyShareLink,
    emitState,
    emitView,
    eventPayload,
    installMetadata,
    sendEvent,
    state,
    statusIsPlaying,
  };
})();
