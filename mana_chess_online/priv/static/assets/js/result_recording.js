// Result recording helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const record = ({localStats, storageKey, resultKey, outcome, lastResultKey, onRecorded}) => {
    const result = localStats.record({
      storageKey,
      resultKey,
      outcome,
      lastResultKey,
    })

    if (result.recorded && onRecorded) {
      onRecorded({
        name: "match.finished",
        payload: {result: result.outcome, resultKey: result.resultKey},
        key: `match.finished:${result.resultKey}`,
      })
    }

    return result.lastResultKey
  }

  window.ManaChessResultRecording = {record}
})()
