const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const Hooks = {
  LocalStats: window.ManaChessLocalStatsHook,
  BoardDrag: window.ManaChessBoardDragHook
};

const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});

liveSocket.connect();
window.liveSocket = liveSocket;
