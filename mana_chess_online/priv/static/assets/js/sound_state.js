// Sound state helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const numberDatasetValue = value => Number.parseInt(value || "0", 10)

  const state = element => ({
    gameId: element.dataset.soundGameId || "",
    status: element.dataset.soundStatus || "",
    logCount: numberDatasetValue(element.dataset.soundLogCount),
    logKind: element.dataset.soundLogKind || "",
    chatCount: numberDatasetValue(element.dataset.soundChatCount),
    alert: element.dataset.soundAlert || "",
    alertKind: element.dataset.soundAlertKind || "",
    resultKey: element.dataset.resultKey || "",
    result: element.dataset.resultOutcome || "",
  })

  const resultSound = result => {
    if (result === "win") return "win"
    if (result === "loss") return "loss"
    return "draw"
  }

  const alertSound = alertKind => {
    if (alertKind === "check") return "check"
    if (alertKind === "reset") return "reset"
    return "alert"
  }

  const logSound = logKind => {
    if (logKind === "capture") return "capture"
    if (logKind === "alert") return "alert"
    return "move"
  }

  const changedSound = (current, previous, soundEnabled) => {
    if (!previous || !soundEnabled) return null

    if (current.result && current.resultKey && current.resultKey !== previous.resultKey) {
      return resultSound(current.result)
    }

    if (current.alert && current.alert !== previous.alert) {
      return alertSound(current.alertKind)
    }

    if (current.gameId && current.gameId === previous.gameId && current.logCount > previous.logCount) {
      return logSound(current.logKind)
    }

    if (current.gameId && current.gameId === previous.gameId && current.chatCount > previous.chatCount) {
      return "chat"
    }

    if (current.status && current.status !== previous.status) {
      return "state"
    }

    return null
  }

  window.ManaChessSoundState = {state, changedSound}
})()
