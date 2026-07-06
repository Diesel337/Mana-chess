// Chat UI helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const renderTimes = (root) => {
    root.querySelectorAll("[data-chat-time]").forEach((node) => {
      if (node.dataset.chatTimeRendered === node.dataset.chatTime) return;

      const seconds = Number.parseInt(node.dataset.chatTime || "", 10);
      if (Number.isNaN(seconds)) return;

      node.textContent = new Date(seconds * 1000).toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        hour12: false,
      });
      node.dataset.chatTimeRendered = node.dataset.chatTime;
    });
  };

  const scrollState = (root) => ({
    gameId: root.dataset.soundGameId || "",
    chatCount: Number.parseInt(root.dataset.soundChatCount || "0", 10),
  });

  const scrollListsToEnd = (root) => {
    const scroll = () => {
      root.querySelectorAll("[data-chat-list]").forEach((list) => {
        list.scrollTop = list.scrollHeight;
      });
    };

    window.requestAnimationFrame(scroll);
    window.setTimeout(scroll, 80);
  };

  const keepAtLatest = (root, previous) => {
    const current = scrollState(root);

    if (!current.gameId) return current;
    if (previous && current.gameId === previous.gameId && current.chatCount <= previous.chatCount) {
      return current;
    }

    scrollListsToEnd(root);
    return current;
  };

  window.ManaChessChat = {keepAtLatest, renderTimes, scrollListsToEnd, scrollState};
})();
