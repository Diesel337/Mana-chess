// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/mana_chess_online"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const Hooks = {
  LocalStats: {
    mounted() {
      this.lastResultKey = null
      this.storageKey = "mana-chess-local-stats"
      this.handleReset = event => {
        if (!event.target.closest("[data-stats-reset]")) return
        localStorage.removeItem(this.storageKey)
        this.lastResultKey = null
        this.renderStats()
      }
      this.el.addEventListener("click", this.handleReset)
      this.recordResult()
      this.renderStats()
    },

    updated() {
      this.recordResult()
      this.renderStats()
    },

    destroyed() {
      this.el.removeEventListener("click", this.handleReset)
    },

    readStats() {
      try {
        return JSON.parse(localStorage.getItem(this.storageKey)) || this.emptyStats()
      } catch (_error) {
        return this.emptyStats()
      }
    },

    writeStats(stats) {
      localStorage.setItem(this.storageKey, JSON.stringify(stats))
    },

    emptyStats() {
      return {played: 0, wins: 0, losses: 0, draws: 0, seen: []}
    },

    recordResult() {
      const key = this.el.dataset.resultKey
      const outcome = this.el.dataset.resultOutcome

      if (!key || !outcome) {
        this.lastResultKey = null
        return
      }

      if (this.lastResultKey === key) return

      const stats = this.readStats()
      stats.seen = Array.isArray(stats.seen) ? stats.seen : []

      if (stats.seen.includes(key)) {
        this.lastResultKey = key
        return
      }

      stats.played = (stats.played || 0) + 1

      if (outcome === "win") stats.wins = (stats.wins || 0) + 1
      if (outcome === "loss") stats.losses = (stats.losses || 0) + 1
      if (outcome === "draw") stats.draws = (stats.draws || 0) + 1

      stats.seen = [key, ...stats.seen].slice(0, 40)
      this.writeStats(stats)
      this.lastResultKey = key
    },

    renderStats() {
      const stats = this.readStats()

      for (const [name, value] of Object.entries({
        played: stats.played || 0,
        wins: stats.wins || 0,
        losses: stats.losses || 0,
        draws: stats.draws || 0,
      })) {
        this.el.querySelectorAll(`[data-stat="${name}"]`).forEach(node => {
          node.textContent = value
        })
      }
    },
  },

  BoardDrag: {
    mounted() {
      this.drag = null
      this.suppressClick = false

      this.el.addEventListener("pointerdown", event => {
        const square = event.target.closest(".mc-square")
        const piece = square && square.querySelector(".mc-piece:not(:empty)")

        if (!square || !piece) return

        this.drag = {
          fromR: square.dataset.r,
          fromC: square.dataset.c,
          pointerId: event.pointerId,
          startX: event.clientX,
          startY: event.clientY,
          square,
          piece,
          ghost: null,
          moved: false,
        }

        square.setPointerCapture(event.pointerId)
      })

      this.el.addEventListener("pointermove", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return

        const delta = Math.abs(event.clientX - this.drag.startX) + Math.abs(event.clientY - this.drag.startY)

        if (delta > 8) {
          this.drag.moved = true
          this.el.classList.add("mc-dragging")
          this.drag.square.classList.add("mc-drag-source")
          if (!this.drag.ghost) {
            this.drag.ghost = this.createDragGhost(this.drag.piece, event.clientX, event.clientY)
          }
        }

        if (this.drag.ghost) this.moveDragGhost(this.drag.ghost, event.clientX, event.clientY)
      })

      this.el.addEventListener("pointerup", event => {
        if (!this.drag || this.drag.pointerId !== event.pointerId) return

        const drag = this.drag
        this.drag = null
        this.clearDragVisuals(drag)

        if (!drag.moved) return
        this.suppressClick = true

        const target = document.elementFromPoint(event.clientX, event.clientY)
        const square = target && target.closest(".mc-square")

        if (!square) return

        this.pushEvent("drag_move", {
          from_r: drag.fromR,
          from_c: drag.fromC,
          to_r: square.dataset.r,
          to_c: square.dataset.c,
        })
      })

      this.el.addEventListener("pointercancel", _event => {
        const drag = this.drag
        this.drag = null
        this.clearDragVisuals(drag)
      })

      this.el.addEventListener("click", event => {
        if (this.suppressClick) {
          this.suppressClick = false
          event.preventDefault()
          event.stopPropagation()
        }
      }, true)
    },

    createDragGhost(piece, x, y) {
      const rect = piece.getBoundingClientRect()
      const ghost = piece.cloneNode(true)
      ghost.classList.add("mc-drag-ghost")
      ghost.style.width = `${rect.width}px`
      ghost.style.height = `${rect.height}px`
      document.body.appendChild(ghost)
      this.moveDragGhost(ghost, x, y)
      return ghost
    },

    moveDragGhost(ghost, x, y) {
      ghost.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -58%) scale(1.08)`
    },

    clearDragVisuals(drag) {
      this.el.classList.remove("mc-dragging")
      if (!drag) return
      drag.square && drag.square.classList.remove("mc-drag-source")
      drag.ghost && drag.ghost.remove()
    },
  },
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
