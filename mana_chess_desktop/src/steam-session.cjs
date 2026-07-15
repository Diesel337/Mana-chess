const DEFAULT_AUTH_TIMEOUT_MS = 25_000

async function authenticateSteamSession(options = {}) {
  const steamClient = options.steamClient
  const publicInfo = steamClient?.publicInfo?.() || {}

  if (!steamClient?.isReady?.()) {
    return authResult({
      status: "skipped",
      error: cleanErrorCode(publicInfo.nativeError) || "native_unavailable"
    })
  }

  const fetchRequest = requestFetcher(options)
  if (!fetchRequest) return authResult({status: "failed", error: "session_fetch_unavailable"})

  const endpoint = authEndpoint(options.authOrigin)
  if (!endpoint) return authResult({status: "failed", error: "invalid_auth_origin"})

  const gameOrigin = secureOrigin(options.gameOrigin, {allowLoopbackHttp: true})
  if (!gameOrigin || gameOrigin !== new URL(endpoint).origin) {
    return authResult({status: "skipped", error: "origin_mismatch"})
  }

  const timeoutMs = positiveTimeout(options.timeoutMs)
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)

  try {
    return await steamClient.withWebApiTicket(async ticket => {
      const response = await fetchRequest(endpoint, {
        method: "POST",
        headers: {
          accept: "application/json",
          "content-type": "application/json",
          "x-mana-chess-desktop": "1"
        },
        body: JSON.stringify({ticket}),
        cache: "no-store",
        credentials: "include",
        redirect: "error",
        signal: controller.signal
      })

      const body = await responseJson(response)
      const httpStatus = Number.isInteger(response?.status) ? response.status : 0

      if (response?.ok && body?.ok === true) {
        return authResult({
          ok: true,
          attempted: true,
          status: "authenticated",
          httpStatus,
          steamId: cleanSteamId(body?.identity?.steam_id),
          ownerSteamId: cleanSteamId(body?.identity?.owner_steam_id)
        })
      }

      return authResult({
        attempted: true,
        status: httpStatus >= 500 ? "unavailable" : "rejected",
        httpStatus,
        error: cleanErrorCode(body?.error) || `http_${httpStatus || "error"}`
      })
    })
  } catch (error) {
    return authResult({
      attempted: true,
      status: error?.name === "AbortError" ? "timeout" : "failed",
      error: error?.name === "AbortError" ? "request_timeout" : cleanErrorCode(error?.code) || "request_failed"
    })
  } finally {
    clearTimeout(timeout)
  }
}

function resolveSteamAuthOrigin(options = {}) {
  const env = options.env || process.env
  const defaultOrigin = secureOrigin(options.defaultOrigin)
  if (!defaultOrigin) throw new Error("A secure default Steam auth origin is required.")

  if (String(env.MANA_CHESS_ALLOW_STEAM_AUTH_ORIGIN_OVERRIDE || "").trim() !== "1") {
    return defaultOrigin
  }

  return secureOrigin(env.MANA_CHESS_STEAM_AUTH_ORIGIN, {allowLoopbackHttp: true}) || defaultOrigin
}

function requestFetcher(options) {
  if (typeof options.fetchImpl === "function") return options.fetchImpl
  if (typeof options.session?.fetch === "function") return options.session.fetch.bind(options.session)
  return null
}

function authEndpoint(origin) {
  const normalizedOrigin = secureOrigin(origin, {allowLoopbackHttp: true})
  return normalizedOrigin ? new URL("/auth/steam", normalizedOrigin).toString() : null
}

function secureOrigin(value, options = {}) {
  try {
    const url = new URL(String(value || ""))
    const loopback = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)

    if (url.protocol !== "https:" && !(options.allowLoopbackHttp && loopback && url.protocol === "http:")) {
      return null
    }

    return url.origin
  } catch (_error) {
    return null
  }
}

async function responseJson(response) {
  try {
    return await response.json()
  } catch (_error) {
    return {}
  }
}

function authResult(values = {}) {
  return {
    ok: values.ok === true,
    attempted: values.attempted === true,
    status: String(values.status || "failed"),
    httpStatus: Number.isInteger(values.httpStatus) ? values.httpStatus : 0,
    error: cleanErrorCode(values.error),
    steamId: cleanSteamId(values.steamId),
    ownerSteamId: cleanSteamId(values.ownerSteamId)
  }
}

function positiveTimeout(value) {
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 1_000 && parsed <= 60_000 ? parsed : DEFAULT_AUTH_TIMEOUT_MS
}

function cleanErrorCode(value) {
  const text = String(value || "").trim().toLowerCase()
  return /^[a-z0-9_]{1,64}$/.test(text) ? text : ""
}

function cleanSteamId(value) {
  const text = String(value || "").trim()
  return /^[0-9]{16,20}$/.test(text) ? text : ""
}

module.exports = {
  authenticateSteamSession,
  resolveSteamAuthOrigin
}
