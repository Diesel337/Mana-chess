// View navigation helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const viewJumpSelector = [
    '[phx-click="start_practice"]',
    '[phx-click="start_tutorial"]',
    '[phx-click="sit_anywhere"]',
    '[phx-click="create_private"]',
    '[phx-click="leave"]',
    '[phx-click="sit"]',
  ].join(", ");

  const viewKey = (root) => root.dataset.soundGameId || "lobby";

  const scrollToTop = (settleDelay = 80, finalDelay = 260) => {
    window.requestAnimationFrame(() => window.scrollTo(0, 0));
    window.setTimeout(() => window.scrollTo(0, 0), settleDelay);
    window.setTimeout(() => window.scrollTo(0, 0), finalDelay);
  };

  const shouldScrollForClick = (event) => Boolean(event.target.closest(viewJumpSelector));

  const keepInitialViewInFrame = (root) => {
    if (viewKey(root) !== "lobby") scrollToTop();
  };

  const keepViewInFrame = (root, previousViewKey) => {
    const current = viewKey(root);
    if (current !== previousViewKey) scrollToTop();
    return current;
  };

  const installViewJumpGuard = () => {
    let pendingJump = false;

    document.addEventListener("click", (event) => {
      if (!shouldScrollForClick(event)) return;
      pendingJump = true;
      scrollToTop(90, 300);
    }, true);

    new MutationObserver(() => {
      if (!pendingJump || !document.querySelector(".mc-play-area, .mc-menu")) return;
      pendingJump = false;
      scrollToTop(90, 300);
    }).observe(document.documentElement, {childList: true, subtree: true});
  };

  installViewJumpGuard();

  window.ManaChessNavigation = {
    installViewJumpGuard,
    keepInitialViewInFrame,
    keepViewInFrame,
    scrollToTop,
    shouldScrollForClick,
    viewKey,
  };
})();
