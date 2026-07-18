// Local cosmetic mastery rules. Keep the priv/static copy in sync until the
// JS pipeline bundles these modules.
(() => {
  const catalog = window.ManaChessCosmeticCatalog
  if (!catalog) return

  const statsKey = "mana-chess-local-stats"
  const customRewardIds = ["board:custom", "piece:custom", "palette:custom"]
  const milestones = (catalog.mastery || []).map(milestone => Object.freeze({
    ...milestone,
    rewardIds: Object.freeze([...(milestone.rewardIds || [])]),
  }))

  const count = value => {
    const numeric = Number(value)
    return Number.isFinite(numeric) && numeric > 0 ? Math.floor(numeric) : 0
  }

  const normalizeStats = (stats = {}) => ({
    played: count(stats.played),
    wins: count(stats.wins),
    losses: count(stats.losses),
    draws: count(stats.draws),
  })

  const readStats = (storage = localStorage, key = statsKey) => {
    try {
      return normalizeStats(JSON.parse(storage.getItem(key) || "{}"))
    } catch (_error) {
      return normalizeStats()
    }
  }

  const asUnlockSet = unlocks => new Set(
    unlocks instanceof Set ? [...unlocks] : Array.isArray(unlocks) ? unlocks : []
  )

  const milestoneFor = id => milestones.find(milestone => (
    milestone.rewardIds.includes(id) || (milestone.pack && id === `pack:${milestone.pack}`)
  )) || null

  const current = (milestone, stats) => Math.min(
    normalizeStats(stats)[milestone.metric] || 0,
    milestone.target
  )

  const reached = (milestone, stats) => current(milestone, stats) >= milestone.target

  const rewardUnlocked = (milestone, unlocks) => {
    const set = asUnlockSet(unlocks)
    return milestone.rewardIds.every(id => set.has(id))
  }

  const progressLabel = (id, stats) => {
    const milestone = milestoneFor(id)
    if (!milestone) return "Bloqueado"

    const value = current(milestone, stats)
    const noun = milestone.metric === "wins"
      ? milestone.target === 1 ? "victoria" : "victorias"
      : milestone.target === 1 ? "partida" : "partidas"

    return `${value}/${milestone.target} ${noun}`
  }

  const requirementLabel = id => {
    const milestone = milestoneFor(id)
    if (!milestone) return "Recompensa bloqueada"

    if (milestone.metric === "wins") {
      return `Gana ${milestone.target} ${milestone.target === 1 ? "partida" : "partidas"}`
    }

    return `Completa ${milestone.target} ${milestone.target === 1 ? "partida" : "partidas"}`
  }

  const syncUnlocks = (stats, unlocks = []) => {
    const previous = asUnlockSet(unlocks)
    const next = new Set(previous)
    const unlockedMilestones = []

    if (customRewardIds.some(id => previous.has(id))) {
      customRewardIds.forEach(id => next.add(id))
    }

    milestones.forEach(milestone => {
      const wasUnlocked = rewardUnlocked(milestone, previous)
      if (reached(milestone, stats)) milestone.rewardIds.forEach(id => next.add(id))
      if (!wasUnlocked && rewardUnlocked(milestone, next)) unlockedMilestones.push(milestone.id)
    })

    const values = [...next]
    const changed = values.length !== previous.size || values.some(id => !previous.has(id))
    return {changed, unlockedMilestones, unlocks: values}
  }

  const summary = (stats, unlocks = []) => {
    const completed = milestones.filter(milestone => rewardUnlocked(milestone, unlocks)).length
    const total = milestones.length
    return {
      completed,
      total,
      percent: total === 0 ? 0 : Math.round((completed / total) * 100),
      label: `Maestria ${completed}/${total}`,
    }
  }

  window.ManaChessCosmeticProgression = Object.freeze({
    current,
    milestoneFor,
    milestones: Object.freeze(milestones),
    normalizeStats,
    progressLabel,
    readStats,
    requirementLabel,
    rewardUnlocked,
    summary,
    syncUnlocks,
  })
})()
