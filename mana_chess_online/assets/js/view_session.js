// Chat and view hook adapter. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const chat = () => window.ManaChessChat;
  const navigation = () => window.ManaChessNavigation;

  const renderChatTimes = hook => {
    chat().renderTimes(hook.el);
  };

  const chatScrollState = hook => chat().scrollState(hook.el);

  const keepChatAtLatest = hook => {
    hook.lastChatScrollState = chat().keepAtLatest(hook.el, hook.lastChatScrollState);
  };

  const scrollChatListsToEnd = hook => {
    chat().scrollListsToEnd(hook.el);
  };

  const viewKey = hook => navigation().viewKey(hook.el);

  const keepViewInFrame = hook => {
    hook.lastViewKey = navigation().keepViewInFrame(hook.el, hook.lastViewKey);
  };

  const keepInitialViewInFrame = hook => {
    navigation().keepInitialViewInFrame(hook.el);
  };

  const scrollViewToTop = () => {
    navigation().scrollToTop();
  };

  window.ManaChessViewSession = {
    chat,
    chatScrollState,
    keepChatAtLatest,
    keepInitialViewInFrame,
    keepViewInFrame,
    navigation,
    renderChatTimes,
    scrollChatListsToEnd,
    scrollViewToTop,
    viewKey,
  };
})();
