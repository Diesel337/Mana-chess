// BoardDrag Phoenix hook facade. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  window.ManaChessBoardDragHook = {
    mounted() {
      window.ManaChessBoardDrag.mounted(this)
    },

    updated() {
      window.ManaChessBoardDrag.updated(this)
    },

    destroyed() {
      window.ManaChessBoardDrag.destroyed(this)
    },
  }
})()
