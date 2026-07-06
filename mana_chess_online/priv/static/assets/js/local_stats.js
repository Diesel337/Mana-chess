// Source of the local match stats helper. Keep the priv/static copy in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const empty = () => ({played: 0, wins: 0, losses: 0, draws: 0, seen: []});

  const read = (storageKey) => {
    try {
      return JSON.parse(localStorage.getItem(storageKey)) || empty();
    } catch (_error) {
      return empty();
    }
  };

  const write = (storageKey, stats) => {
    localStorage.setItem(storageKey, JSON.stringify(stats));
  };

  const record = ({storageKey, resultKey, outcome, lastResultKey}) => {
    if (!resultKey || !outcome) return {lastResultKey: null, recorded: false};
    if (lastResultKey === resultKey) return {lastResultKey, recorded: false};

    const stats = read(storageKey);
    stats.seen = Array.isArray(stats.seen) ? stats.seen : [];

    if (stats.seen.includes(resultKey)) {
      return {lastResultKey: resultKey, recorded: false};
    }

    stats.played = (stats.played || 0) + 1;
    if (outcome === "win") stats.wins = (stats.wins || 0) + 1;
    if (outcome === "loss") stats.losses = (stats.losses || 0) + 1;
    if (outcome === "draw") stats.draws = (stats.draws || 0) + 1;

    stats.seen = [resultKey, ...stats.seen].slice(0, 40);
    write(storageKey, stats);

    return {lastResultKey: resultKey, outcome, recorded: true, resultKey};
  };

  const render = (root, storageKey) => {
    const stats = read(storageKey);

    for (const [name, value] of Object.entries({
      played: stats.played || 0,
      wins: stats.wins || 0,
      losses: stats.losses || 0,
      draws: stats.draws || 0
    })) {
      root.querySelectorAll(`[data-stat="${name}"]`).forEach((node) => {
        node.textContent = value;
      });
    }
  };

  window.ManaChessLocalStats = {empty, read, record, render, write};
})();
