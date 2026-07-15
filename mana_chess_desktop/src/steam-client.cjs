const STEAM_ENV_NAMES = [
  "MANA_CHESS_STEAM_APP_ID",
  "SteamAppId",
  "SteamGameId",
  "SteamOverlayGameId",
  "STEAM_APP_ID",
  "STEAM_APPID",
  "STEAM_GAME_ID",
  "STEAM_GAMEID",
  "STEAM_OVERLAY_GAME_ID",
  "SteamClientLaunch",
  "SteamEnv",
  "SteamPath",
  "SteamDeck",
  "SteamTenfoot"
]

const DEFAULT_TICKET_IDENTITY = "mana-chess-desktop-v1"
const MAX_APP_ID = 4_294_967_295
const MIN_TICKET_BYTES = 32
const MAX_TICKET_BYTES = 4_096

class SteamClientError extends Error {
  constructor(code) {
    super(code)
    this.name = "SteamClientError"
    this.code = code
  }
}

function createSteamClient(options = {}) {
  const env = options.env || process.env
  const launchContext = steamLaunchContext(env)
  const appId = numericAppId(launchContext.appId)
  const ticketIdentity = cleanTicketIdentity(readEnv(env, ["MANA_CHESS_STEAM_TICKET_IDENTITY"]))
  const nativeDisabled = readEnv(env, ["MANA_CHESS_DISABLE_STEAM_NATIVE"]) === "1"
  const skipRestart = readEnv(env, ["MANA_CHESS_STEAM_SKIP_RESTART"]) === "1"
  const loadSteamworks = options.steamworksLoader || (() => require("steamworks.js"))
  const state = {
    nativeReady: false,
    nativeDisabled,
    restartRequired: false,
    overlayReady: false,
    nativeError: "",
    steamId: "",
    ownerSteamId: "",
    subscribed: null
  }

  let client = null

  if (nativeDisabled) {
    state.nativeError = "native_disabled"
  } else if (!appId) {
    state.nativeError = "app_id_missing"
  } else {
    try {
      const steamworks = loadSteamworks()

      if (!skipRestart && steamworks.restartAppIfNecessary(appId)) {
        state.restartRequired = true
      } else {
        client = steamworks.init(appId)
        state.nativeReady = true
        state.steamId = playerSteamId(client?.localplayer?.getSteamId?.())
        state.ownerSteamId = playerSteamId(client?.apps?.appOwner?.()) || state.steamId
        state.subscribed = nativeBoolean(() => client.apps.isSubscribedApp(appId))

        if (options.enableOverlay !== false) {
          try {
            steamworks.electronEnableSteamOverlay()
            state.overlayReady = true
          } catch (_error) {
            state.nativeError = "overlay_unavailable"
          }
        }
      }
    } catch (_error) {
      client = null
      state.nativeReady = false
      state.nativeError = "native_init_failed"
    }
  }

  function publicInfo() {
    return {
      ...launchContext,
      appId: launchContext.appId || (appId ? String(appId) : ""),
      nativeReady: state.nativeReady,
      nativeDisabled: state.nativeDisabled,
      restartRequired: state.restartRequired,
      overlayReady: state.overlayReady,
      nativeError: state.nativeError,
      steamId: state.steamId,
      ownerSteamId: state.ownerSteamId,
      subscribed: state.subscribed
    }
  }

  async function withWebApiTicket(callback) {
    if (!state.nativeReady || !client) throw new SteamClientError("native_unavailable")
    if (typeof callback !== "function") throw new SteamClientError("ticket_callback_required")

    let ticket

    try {
      ticket = await client.auth.getAuthTicketForWebApi(ticketIdentity, 10)
    } catch (_error) {
      throw new SteamClientError("ticket_unavailable")
    }

    try {
      const bytes = ticketBytes(ticket)
      return await callback(bytes.toString("hex"))
    } finally {
      try {
        ticket?.cancel?.()
      } catch (_error) {
        // Ticket cancellation is best-effort after the one authenticated request.
      }
    }
  }

  return Object.freeze({
    isReady: () => state.nativeReady,
    publicInfo,
    withWebApiTicket
  })
}

function steamLaunchContext(env = process.env) {
  const appId = cleanAppId(readEnv(env, [
    "MANA_CHESS_STEAM_APP_ID",
    "SteamAppId",
    "STEAM_APP_ID",
    "STEAM_APPID"
  ]))
  const gameId = cleanAppId(readEnv(env, ["SteamGameId", "STEAM_GAME_ID", "STEAM_GAMEID"]))
  const overlayGameId = cleanAppId(readEnv(env, ["SteamOverlayGameId", "STEAM_OVERLAY_GAME_ID"]))
  const presentKeys = presentSteamEnvKeys(env)

  return {
    detected: Boolean(appId || gameId || overlayGameId || presentKeys.length > 0),
    appId,
    gameId,
    overlayGameId,
    clientLaunch: Boolean(readEnv(env, ["SteamClientLaunch"])),
    steamEnv: Boolean(readEnv(env, ["SteamEnv"])),
    steamPath: Boolean(readEnv(env, ["SteamPath"])),
    steamDeck: Boolean(readEnv(env, ["SteamDeck"])),
    steamTenfoot: Boolean(readEnv(env, ["SteamTenfoot"])),
    presentKeys
  }
}

function presentSteamEnvKeys(env = process.env) {
  return STEAM_ENV_NAMES.filter(name => readEnv(env, [name]))
}

function readEnv(env = process.env, names = []) {
  for (const name of names) {
    if (Object.prototype.hasOwnProperty.call(env, name)) return String(env[name] || "").trim()

    const normalizedName = String(name || "").toLowerCase()
    const actualName = Object.keys(env).find(key => key.toLowerCase() === normalizedName)
    if (actualName) return String(env[actualName] || "").trim()
  }

  return ""
}

function cleanAppId(value) {
  const text = String(value || "").trim()
  const parsed = numericAppId(text)
  return parsed ? String(parsed) : ""
}

function numericAppId(value) {
  const text = String(value || "").trim()
  if (!/^[0-9]{1,10}$/.test(text)) return null

  const parsed = Number(text)
  return Number.isSafeInteger(parsed) && parsed > 0 && parsed <= MAX_APP_ID ? parsed : null
}

function cleanTicketIdentity(value) {
  const text = String(value || DEFAULT_TICKET_IDENTITY).trim()

  if (text.length > 0 && text.length <= 128 && !/[\u0000-\u001f\u007f]/.test(text)) {
    return text
  }

  return DEFAULT_TICKET_IDENTITY
}

function playerSteamId(player) {
  const value = player?.steamId64
  const text = typeof value === "bigint" ? value.toString() : String(value || "").trim()
  return /^[0-9]{16,20}$/.test(text) ? text : ""
}

function nativeBoolean(callback) {
  try {
    return Boolean(callback())
  } catch (_error) {
    return null
  }
}

function ticketBytes(ticket) {
  let bytes

  try {
    bytes = ticket?.getBytes?.()
  } catch (_error) {
    throw new SteamClientError("ticket_unavailable")
  }

  const buffer = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes || [])

  if (buffer.length < MIN_TICKET_BYTES || buffer.length > MAX_TICKET_BYTES) {
    throw new SteamClientError("ticket_unavailable")
  }

  return buffer
}

module.exports = {
  SteamClientError,
  createSteamClient,
  steamLaunchContext
}
