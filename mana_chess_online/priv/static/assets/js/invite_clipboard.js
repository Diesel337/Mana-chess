// Invite clipboard helper. Keep the assets/js and priv/static copies in sync
// until Mana Chess has a real JS bundling step.
(() => {
  const fallbackCopy = (text, callback) => {
    const field = document.createElement("textarea")
    field.value = text
    field.setAttribute("readonly", "")
    field.style.position = "fixed"
    field.style.top = "-1000px"
    field.style.opacity = "0"
    document.body.appendChild(field)
    field.select()

    try {
      document.execCommand("copy")
      callback()
    } finally {
      field.remove()
    }
  }

  const copy = (button, {copyShareLink, onCopied} = {}) => {
    const inviteUrl = new URL(button.dataset.copyInvite, window.location.origin).toString()
    const originalHtml = button.innerHTML
    const copiedLabel = button.dataset.copySuccess || "Copiado"
    const markCopied = () => {
      button.dataset.copied = "true"
      button.textContent = copiedLabel
      if (onCopied) onCopied()
      window.clearTimeout(button.copyInviteTimer)
      button.copyInviteTimer = window.setTimeout(() => {
        button.innerHTML = originalHtml
        delete button.dataset.copied
      }, 1400)
    }

    const desktopCopy = copyShareLink ? copyShareLink(inviteUrl) : null
    if (desktopCopy) {
      desktopCopy.then(markCopied).catch(() => {
        fallbackCopy(inviteUrl, markCopied)
      })
    } else if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(inviteUrl).then(markCopied).catch(() => {
        fallbackCopy(inviteUrl, markCopied)
      })
    } else {
      fallbackCopy(inviteUrl, markCopied)
    }
  }

  window.ManaChessInviteClipboard = {copy, fallbackCopy}
})()
