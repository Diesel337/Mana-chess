// Board drag hook behavior. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const legalMoves = (hook, square) => (
    (square.dataset.legalMoves || "").trim().split(/\s+/).filter(Boolean)
  );

  const legalTarget = (_hook, drag, square) => (
    drag.legalMoves.includes(`${square.dataset.r},${square.dataset.c}`)
  );

  const showLegalPreview = (hook, square, moves = legalMoves(hook, square)) => {
    if (moves.length === 0) return;

    square.classList.add("mc-selected", "mc-client-selected");

    moves.forEach(move => {
      const [r, c] = move.split(",");
      const target = hook.el.querySelector(`.mc-square[data-r="${r}"][data-c="${c}"]`);
      if (target) target.classList.add("mc-valid", "mc-client-valid");
    });
  };

  const clearLegalPreview = hook => {
    hook.el.querySelectorAll(".mc-client-selected").forEach(square => {
      square.classList.remove("mc-selected", "mc-client-selected");
    });
    hook.el.querySelectorAll(".mc-client-valid").forEach(square => {
      square.classList.remove("mc-valid", "mc-client-valid");
    });
  };

  const flashBlockedSquare = square => {
    if (!square) return;
    square.classList.remove("mc-client-blocked");
    void square.offsetWidth;
    square.classList.add("mc-client-blocked");
    window.clearTimeout(square.blockedPreviewTimer);
    square.blockedPreviewTimer = window.setTimeout(() => {
      square.classList.remove("mc-client-blocked");
    }, 620);
  };

  const clearBlockedPreview = hook => {
    hook.el.querySelectorAll(".mc-client-blocked").forEach(square => {
      window.clearTimeout(square.blockedPreviewTimer);
      square.classList.remove("mc-client-blocked");
    });
  };

  const moveDragGhost = (ghost, x, y) => {
    ghost.style.transform = `translate3d(${x}px, ${y}px, 0) translate(-50%, -58%) scale(1.08)`;
  };

  const createDragGhost = (piece, x, y) => {
    const rect = piece.getBoundingClientRect();
    const ghost = piece.cloneNode(true);
    ghost.classList.add("mc-drag-ghost");
    ghost.style.width = `${rect.width}px`;
    ghost.style.height = `${rect.height}px`;
    document.body.appendChild(ghost);
    moveDragGhost(ghost, x, y);
    return ghost;
  };

  const clearDragVisuals = (hook, drag) => {
    hook.el.classList.remove("mc-dragging");
    if (!drag) return;
    drag.square && drag.square.classList.remove("mc-drag-source");
    drag.ghost && drag.ghost.remove();
  };

  const mounted = hook => {
    hook.drag = null;
    hook.suppressClick = false;

    hook.el.addEventListener("pointerdown", event => {
      const square = event.target.closest(".mc-square");
      const piece = square && square.querySelector(".mc-piece:not(:empty)");

      clearLegalPreview(hook);
      clearBlockedPreview(hook);
      if (!square || !piece) return;

      const moves = legalMoves(hook, square);
      if (moves.length === 0) {
        flashBlockedSquare(square);
        return;
      }

      showLegalPreview(hook, square, moves);

      hook.drag = {
        fromR: square.dataset.r,
        fromC: square.dataset.c,
        legalMoves: moves,
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        square,
        piece,
        ghost: null,
        moved: false,
      };

      square.setPointerCapture(event.pointerId);
    });

    hook.el.addEventListener("pointermove", event => {
      if (!hook.drag || hook.drag.pointerId !== event.pointerId) return;

      const delta = Math.abs(event.clientX - hook.drag.startX) + Math.abs(event.clientY - hook.drag.startY);

      if (delta > 8) {
        hook.drag.moved = true;
        hook.el.classList.add("mc-dragging");
        hook.drag.square.classList.add("mc-drag-source");
        if (!hook.drag.ghost) {
          hook.drag.ghost = createDragGhost(hook.drag.piece, event.clientX, event.clientY);
        }
      }

      if (hook.drag.ghost) moveDragGhost(hook.drag.ghost, event.clientX, event.clientY);
    });

    hook.el.addEventListener("pointerup", event => {
      if (!hook.drag || hook.drag.pointerId !== event.pointerId) return;

      const drag = hook.drag;
      hook.drag = null;
      clearDragVisuals(hook, drag);

      if (!drag.moved) return;
      hook.suppressClick = true;
      clearLegalPreview(hook);

      const target = document.elementFromPoint(event.clientX, event.clientY);
      const square = target && target.closest(".mc-square");

      if (!square) {
        flashBlockedSquare(drag.square);
        hook.pushEvent("drag_invalid", {
          from_r: drag.fromR,
          from_c: drag.fromC,
        });
        return;
      }

      if (!legalTarget(hook, drag, square)) {
        flashBlockedSquare(square);
      }

      hook.pushEvent("drag_move", {
        from_r: drag.fromR,
        from_c: drag.fromC,
        to_r: square.dataset.r,
        to_c: square.dataset.c,
      });
    });

    hook.el.addEventListener("pointercancel", _event => {
      const drag = hook.drag;
      hook.drag = null;
      clearDragVisuals(hook, drag);
      clearLegalPreview(hook);
      clearBlockedPreview(hook);
    });

    hook.el.addEventListener("click", event => {
      if (hook.suppressClick) {
        hook.suppressClick = false;
        event.preventDefault();
        event.stopPropagation();
      }
    }, true);
  };

  const updated = hook => {
    clearLegalPreview(hook);
    clearBlockedPreview(hook);
  };

  const destroyed = hook => {
    clearLegalPreview(hook);
    clearBlockedPreview(hook);
  };

  window.ManaChessBoardDrag = {destroyed, mounted, updated};
})();
