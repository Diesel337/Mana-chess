const DEFAULT_AUTH_TIMEOUT_MS = 25_000
const STEAM_PROTOCOL_VERSION = 1

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

  const endpoints = authEndpoints(options.authOrigin)
  if (!endpoints) return authResult({status: "failed", error: "invalid_auth_origin"})

  const gameOrigin = secureOrigin(options.gameOrigin, {allowLoopbackHttp: true})
  if (!gameOrigin || gameOrigin !== new URL(endpoints.session).origin) {
    return authResult({status: "skipped", error: "origin_mismatch"})
  }

  const timeoutMs = positiveTimeout(options.timeoutMs)
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  let phase = "configuration"
  let bootstrapContext = {}

  try {
    const configurationResponse = await fetchRequest(endpoints.configuration, {
      method: "GET",
      headers: {
        accept: "application/json",
        "x-mana-chess-desktop": "1"
      },
      cache: "no-store",
      credentials: "include",
      redirect: "error",
      signal: controller.signal
    })
    const configurationBody = await responseJson(configurationResponse)
    const configurationStatus = responseStatus(configurationResponse)

    if (!configurationResponse?.ok) {
      return authResult({
        phase,
        status: configurationStatus >= 500 ? "unavailable" : "rejected",
        httpStatus: configurationStatus,
        error: cleanErrorCode(configurationBody?.error) || `configuration_http_${configurationStatus || "error"}`
      })
    }

    const bootstrap = steamBootstrap(configurationBody)
    if (!bootstrap) return authResult({phase, status: "failed", error: "invalid_steam_configuration"})

    bootstrapContext = {
      protocolVersion: bootstrap.protocolVersion,
      backendConfigured: bootstrap.configured,
      backendAppId: bootstrap.appId,
      launchRequired: bootstrap.launchRequired
    }

    if (bootstrap.protocolVersion !== STEAM_PROTOCOL_VERSION) {
      return authResult({...bootstrapContext, phase, status: "failed", error: "unsupported_steam_protocol"})
    }

    if (!bootstrap.configured) {
      return authResult({...bootstrapContext, phase, status: "unavailable", error: "steam_auth_not_configured"})
    }

    if (!bootstrap.appId || bootstrap.appId !== cleanAppId(publicInfo.appId)) {
      return authResult({...bootstrapContext, phase, status: "rejected", error: "steam_app_id_mismatch"})
    }

    if (!bootstrap.ticketIdentity) {
      return authResult({...bootstrapContext, phase, status: "failed", error: "invalid_ticket_identity"})
    }

    phase = "ticket"

    return await steamClient.withWebApiTicket(bootstrap.ticketIdentity, async ticket => {
      phase = "session"
      const response = await fetchRequest(endpoints.session, {
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
      const httpStatus = responseStatus(response)

      if (response?.ok && body?.ok === true) {
        return authResult({
          ...bootstrapContext,
          ok: true,
          attempted: true,
          phase: "complete",
          status: "authenticated",
          httpStatus,
          steamId: cleanSteamId(body?.identity?.steam_id),
          ownerSteamId: cleanSteamId(body?.identity?.owner_steam_id)
        })
      }

      return authResult({
        ...bootstrapContext,
        attempted: true,
        phase,
        status: httpStatus >= 500 ? "unavailable" : "rejected",
        httpStatus,
        error: cleanErrorCode(body?.error) || `http_${httpStatus || "error"}`
      })
    })
  } catch (error) {
    return authResult({
      ...bootstrapContext,
      attempted: phase !== "configuration",
      phase,
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

function authEndpoints(origin) {
  const normalizedOrigin = secureOrigin(origin, {allowLoopbackHttp: true})
  if (!normalizedOrigin) return null

  return {
    configuration: new URL("/auth/steam/config", normalizedOrigin).toString(),
    session: new URL("/auth/steam", normalizedOrigin).toString()
  }
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
    phase: cleanPhase(values.phase),
    protocolVersion: Number.isInteger(values.protocolVersion) ? values.protocolVersion : 0,
    backendConfigured: optionalBoolean(values.backendConfigured),
    backendAppId: cleanAppId(values.backendAppId),
    launchRequired: optionalBoolean(values.launchRequired),
    steamId: cleanSteamId(values.steamId),
    ownerSteamId: cleanSteamId(values.ownerSteamId)
  }
}

function steamBootstrap(body) {
  const steam = body?.steam
  if (body?.ok !== true || !steam || typeof steam !== "object") return null

  return {
    protocolVersion: Number.isInteger(steam.protocol_version) ? steam.protocol_version : 0,
    configured: steam.configured === true,
    appId: cleanAppId(steam.app_id),
    ticketIdentity: cleanTicketIdentity(steam.ticket_identity),
    launchRequired: body.launch_required === true
  }
}

function responseStatus(response) {
  return Number.isInteger(response?.status) ? response.status : 0
}

function positiveTimeout(value) {
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 1_000 && parsed <= 60_000 ? parsed : DEFAULT_AUTH_TIMEOUT_MS
}

function cleanErrorCode(value) {
  const text = String(value || "").trim().toLowerCase()
  return /^[a-z0-9_]{1,64}$/.test(text) ? text : ""
}

function cleanPhase(value) {
  const phase = String(value || "").trim().toLowerCase()
  return ["configuration", "ticket", "session", "complete"].includes(phase) ? phase : ""
}

function cleanAppId(value) {
  const text = String(value || "").trim()
  if (!/^[0-9]{1,10}$/.test(text)) return ""

  const parsed = Number(text)
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= 4_294_967_295 ? String(parsed) : ""
}

function cleanTicketIdentity(value) {
  const text = String(value || "").trim()
  return text.length > 0 && text.length <= 128 && !/[\u0000-\u001f\u007f]/.test(text) ? text : ""
}

function optionalBoolean(value) {
  return typeof value === "boolean" ? value : null
}

function cleanSteamId(value) {
  const text = String(value || "").trim()
  return /^[0-9]{16,20}$/.test(text) ? text : ""
}

module.exports = {
  authenticateSteamSession,
  resolveSteamAuthOrigin
}
