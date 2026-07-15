const assert = require("node:assert/strict")
const {createSteamClient} = require("../src/steam-client.cjs")
const {authenticateSteamSession, resolveSteamAuthOrigin} = require("../src/steam-session.cjs")

const APP_ID = "111111"
const STEAM_ID = "76561198000000000"
const OWNER_STEAM_ID = "76561198000000001"
const AUTH_ORIGIN = "https://mana-chess-production.up.railway.app"
const TICKET_BYTES = Buffer.alloc(64, 0xab)

function fakeSteamworks(counters, options = {}) {
  return {
    restartAppIfNecessary(appId) {
      counters.restart += 1
      assert.equal(appId, Number(APP_ID))
      return options.restartRequired === true
    },
    init(appId) {
      counters.init += 1
      assert.equal(appId, Number(APP_ID))

      return {
        localplayer: {
          getSteamId: () => ({steamId64: BigInt(STEAM_ID)})
        },
        apps: {
          appOwner: () => ({steamId64: BigInt(OWNER_STEAM_ID)}),
          isSubscribedApp: requestedAppId => requestedAppId === Number(APP_ID)
        },
        auth: {
          async getAuthTicketForWebApi(identity, timeoutSeconds) {
            counters.ticket += 1
            assert.equal(identity, "mana-chess-desktop-v1")
            assert.equal(timeoutSeconds, 10)

            return {
              getBytes: () => TICKET_BYTES,
              cancel() {
                counters.cancel += 1
              }
            }
          }
        }
      }
    },
    electronEnableSteamOverlay() {
      counters.overlay += 1
    }
  }
}

function steamRuntime(options = {}) {
  const counters = {restart: 0, init: 0, ticket: 0, cancel: 0, overlay: 0}
  const runtime = createSteamClient({
    env: {
      SteamAppId: APP_ID,
      SteamGameId: APP_ID,
      MANA_CHESS_STEAM_SKIP_RESTART: "1"
    },
    steamworksLoader: () => fakeSteamworks(counters, options),
    enableOverlay: options.enableOverlay !== false
  })

  return {counters, runtime}
}

async function verifySuccessfulSession() {
  const {counters, runtime} = steamRuntime()
  const requests = []
  const result = await authenticateSteamSession({
    steamClient: runtime,
    authOrigin: AUTH_ORIGIN,
    gameOrigin: AUTH_ORIGIN,
    fetchImpl: async (url, options) => {
      requests.push({url, options})
      return {
        ok: true,
        status: 201,
        json: async () => ({
          ok: true,
          identity: {steam_id: STEAM_ID, owner_steam_id: OWNER_STEAM_ID}
        })
      }
    }
  })

  assert.deepEqual(runtime.publicInfo(), {
    detected: true,
    appId: APP_ID,
    gameId: APP_ID,
    overlayGameId: "",
    clientLaunch: false,
    steamEnv: false,
    steamPath: false,
    steamDeck: false,
    steamTenfoot: false,
    presentKeys: ["SteamAppId", "SteamGameId"],
    nativeReady: true,
    nativeDisabled: false,
    restartRequired: false,
    overlayReady: true,
    nativeError: "",
    steamId: STEAM_ID,
    ownerSteamId: OWNER_STEAM_ID,
    subscribed: true
  })
  assert.deepEqual(result, {
    ok: true,
    attempted: true,
    status: "authenticated",
    httpStatus: 201,
    error: "",
    steamId: STEAM_ID,
    ownerSteamId: OWNER_STEAM_ID
  })
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, `${AUTH_ORIGIN}/auth/steam`)
  assert.equal(requests[0].options.method, "POST")
  assert.equal(requests[0].options.credentials, "include")
  assert.equal(requests[0].options.redirect, "error")
  assert.equal(requests[0].options.headers["x-mana-chess-desktop"], "1")
  assert.deepEqual(JSON.parse(requests[0].options.body), {ticket: TICKET_BYTES.toString("hex")})
  assert.equal(counters.ticket, 1)
  assert.equal(counters.cancel, 1)
  assert.equal(JSON.stringify(result).includes(TICKET_BYTES.toString("hex")), false)
}

async function verifyTicketCancellationOnFailure() {
  const {counters, runtime} = steamRuntime({enableOverlay: false})
  const result = await authenticateSteamSession({
    steamClient: runtime,
    authOrigin: AUTH_ORIGIN,
    gameOrigin: AUTH_ORIGIN,
    fetchImpl: async () => {
      throw new Error("simulated network failure")
    }
  })

  assert.equal(result.ok, false)
  assert.equal(result.status, "failed")
  assert.equal(result.error, "request_failed")
  assert.equal(counters.ticket, 1)
  assert.equal(counters.cancel, 1)
}

async function verifyDisabledAndMismatchedOriginsSkipTickets() {
  let loaded = false
  const disabled = createSteamClient({
    env: {SteamAppId: APP_ID, MANA_CHESS_DISABLE_STEAM_NATIVE: "1"},
    steamworksLoader: () => {
      loaded = true
      return fakeSteamworks({})
    }
  })
  const disabledResult = await authenticateSteamSession({
    steamClient: disabled,
    authOrigin: AUTH_ORIGIN,
    gameOrigin: AUTH_ORIGIN,
    fetchImpl: async () => {
      throw new Error("fetch should not run")
    }
  })

  assert.equal(loaded, false)
  assert.equal(disabledResult.attempted, false)
  assert.equal(disabledResult.error, "native_disabled")

  const {counters, runtime} = steamRuntime({enableOverlay: false})
  const mismatchResult = await authenticateSteamSession({
    steamClient: runtime,
    authOrigin: AUTH_ORIGIN,
    gameOrigin: "https://staging.example",
    fetchImpl: async () => {
      throw new Error("fetch should not run")
    }
  })

  assert.equal(mismatchResult.attempted, false)
  assert.equal(mismatchResult.error, "origin_mismatch")
  assert.equal(counters.ticket, 0)
}

function verifyAuthOriginPinning() {
  assert.equal(resolveSteamAuthOrigin({
    env: {MANA_CHESS_STEAM_AUTH_ORIGIN: "https://evil.example"},
    defaultOrigin: AUTH_ORIGIN
  }), AUTH_ORIGIN)

  assert.equal(resolveSteamAuthOrigin({
    env: {
      MANA_CHESS_ALLOW_STEAM_AUTH_ORIGIN_OVERRIDE: "1",
      MANA_CHESS_STEAM_AUTH_ORIGIN: "http://127.0.0.1:4000/path"
    },
    defaultOrigin: AUTH_ORIGIN
  }), "http://127.0.0.1:4000")

  assert.equal(resolveSteamAuthOrigin({
    env: {
      MANA_CHESS_ALLOW_STEAM_AUTH_ORIGIN_OVERRIDE: "1",
      MANA_CHESS_STEAM_AUTH_ORIGIN: "http://evil.example"
    },
    defaultOrigin: AUTH_ORIGIN
  }), AUTH_ORIGIN)
}

async function main() {
  await verifySuccessfulSession()
  await verifyTicketCancellationOnFailure()
  await verifyDisabledAndMismatchedOriginsSkipTickets()
  verifyAuthOriginPinning()
  console.log("Steam session lifecycle verification passed.")
}

main().catch(error => {
  console.error(error)
  process.exit(1)
})
