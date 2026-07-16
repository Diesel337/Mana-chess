import {mkdir, writeFile} from "node:fs/promises"
import {dirname, resolve} from "node:path"
import {performance} from "node:perf_hooks"

import {load} from "cheerio"
import WebSocket from "ws"

const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost", "::1", "[::1]"])
const USER_AGENT = "ManaChessCapacityBench/1.0"

const HELP = `Mana Chess LiveView capacity benchmark

Usage:
  node bench/liveview_capacity.mjs [options]

Options:
  --url URL                       Target origin (default http://127.0.0.1:4000)
  --matches N                     Private matches to create (default 10)
  --ramp-per-second N             Match setup starts per second (default 10)
  --hold-seconds N                Hold connected clients after ramp (default 15)
  --request-timeout-ms N          HTTP/WebSocket operation timeout (default 15000)
  --max-p95-ms N                  Maximum accepted join p95 (default 5000)
  --allow-remote                  Required for non-local targets
  --allow-capacity-rejections     Pass when the configured server cap rejects rooms
  --no-moves                      Skip one opening move per player
  --output PATH                   JSON report path
  --help                          Show this help
`

function parsePositiveInteger(value, name, maximum = Number.MAX_SAFE_INTEGER) {
  const parsed = Number.parseInt(value, 10)

  if (!Number.isInteger(parsed) || parsed <= 0 || parsed > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`)
  }

  return parsed
}

function parseArgs(argv) {
  const config = {
    url: "http://127.0.0.1:4000",
    matches: 10,
    rampPerSecond: 10,
    holdSeconds: 15,
    requestTimeoutMs: 15_000,
    maxP95Ms: 5_000,
    allowRemote: false,
    allowCapacityRejections: false,
    exerciseMoves: true,
    output: null
  }

  const takeValue = (index, argument) => {
    const separator = argument.indexOf("=")
    if (separator >= 0) return [argument.slice(separator + 1), index]
    if (index + 1 >= argv.length) throw new Error(`missing value for ${argument}`)
    return [argv[index + 1], index + 1]
  }

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]

    if (argument === "--help" || argument === "-h") {
      console.log(HELP)
      process.exit(0)
    } else if (argument === "--allow-remote") {
      config.allowRemote = true
    } else if (argument === "--allow-capacity-rejections") {
      config.allowCapacityRejections = true
    } else if (argument === "--no-moves") {
      config.exerciseMoves = false
    } else if (argument === "--url" || argument.startsWith("--url=")) {
      const [value, nextIndex] = takeValue(index, argument)
      config.url = value
      index = nextIndex
    } else if (argument === "--matches" || argument.startsWith("--matches=")) {
      const [value, nextIndex] = takeValue(index, argument)
      config.matches = parsePositiveInteger(value, "matches", 5_000)
      index = nextIndex
    } else if (
      argument === "--ramp-per-second" ||
      argument.startsWith("--ramp-per-second=")
    ) {
      const [value, nextIndex] = takeValue(index, argument)
      config.rampPerSecond = parsePositiveInteger(value, "ramp-per-second", 1_000)
      index = nextIndex
    } else if (argument === "--hold-seconds" || argument.startsWith("--hold-seconds=")) {
      const [value, nextIndex] = takeValue(index, argument)
      config.holdSeconds = parsePositiveInteger(value, "hold-seconds", 3_600)
      index = nextIndex
    } else if (
      argument === "--request-timeout-ms" ||
      argument.startsWith("--request-timeout-ms=")
    ) {
      const [value, nextIndex] = takeValue(index, argument)
      config.requestTimeoutMs = parsePositiveInteger(value, "request-timeout-ms", 120_000)
      index = nextIndex
    } else if (argument === "--max-p95-ms" || argument.startsWith("--max-p95-ms=")) {
      const [value, nextIndex] = takeValue(index, argument)
      config.maxP95Ms = parsePositiveInteger(value, "max-p95-ms", 120_000)
      index = nextIndex
    } else if (argument === "--output" || argument.startsWith("--output=")) {
      const [value, nextIndex] = takeValue(index, argument)
      config.output = value
      index = nextIndex
    } else {
      throw new Error(`unknown argument: ${argument}`)
    }
  }

  const target = new URL(config.url)
  target.pathname = "/"
  target.search = ""
  target.hash = ""
  config.target = target

  if (!LOCAL_HOSTS.has(target.hostname) && !config.allowRemote) {
    throw new Error("remote targets require --allow-remote")
  }

  return config
}

function sleep(milliseconds) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds))
}

function percentile(values, percentage) {
  if (values.length === 0) return null
  const ordered = [...values].sort((left, right) => left - right)
  const index = Math.min(Math.ceil((percentage / 100) * ordered.length) - 1, ordered.length - 1)
  return Number(ordered[Math.max(index, 0)].toFixed(2))
}

function latencySummary(values) {
  return {
    count: values.length,
    p50_ms: percentile(values, 50),
    p95_ms: percentile(values, 95),
    p99_ms: percentile(values, 99),
    max_ms: values.length === 0 ? null : Number(Math.max(...values).toFixed(2))
  }
}

function errorMessage(error) {
  const message = error instanceof Error ? error.message : String(error)
  const cause = error instanceof Error ? error.cause : null
  return cause ? `${message}: ${errorMessage(cause)}` : message
}

function cookieHeader(headers) {
  const setCookies =
    typeof headers.getSetCookie === "function"
      ? headers.getSetCookie()
      : [headers.get("set-cookie")].filter(Boolean)

  return setCookies.map((cookie) => cookie.split(";", 1)[0]).join("; ")
}

async function fetchLivePage(config, gameId, clientLabel) {
  const pageUrl = new URL(`/game/${encodeURIComponent(gameId)}`, config.target)
  const startedAt = performance.now()
  const response = await fetch(pageUrl, {
    headers: {accept: "text/html", "user-agent": USER_AGENT},
    redirect: "follow",
    signal: AbortSignal.timeout(config.requestTimeoutMs)
  })
  const httpMs = performance.now() - startedAt

  if (!response.ok) {
    throw new Error(`${clientLabel} GET ${pageUrl.pathname} returned ${response.status}`)
  }

  const html = await response.text()
  const $ = load(html)
  const root = $("[data-phx-session]").first()
  const csrfToken = $('meta[name="csrf-token"]').attr("content")
  const rootId = root.attr("id")
  const session = root.attr("data-phx-session")
  const staticToken = root.attr("data-phx-static") || null

  if (!csrfToken || !rootId || !session) {
    throw new Error(`${clientLabel} response did not contain a LiveView root`)
  }

  const trackedStatic = $("[data-phx-track-static]")
    .map((_index, element) => {
      const asset = $(element).attr("src") || $(element).attr("href")
      return asset ? new URL(asset, response.url).href : null
    })
    .get()
    .filter(Boolean)

  return {
    clientLabel,
    pageUrl: response.url,
    csrfToken,
    rootId,
    session,
    staticToken,
    trackedStatic,
    cookie: cookieHeader(response.headers),
    roomReady: $(`[id="mc-board-${gameId}"]`).length === 1,
    httpMs,
    pageBytes: Buffer.byteLength(html)
  }
}

class LiveViewClient {
  constructor(config, page) {
    this.config = config
    this.page = page
    this.topic = `lv:${page.rootId}`
    this.ref = 0
    this.joinRef = null
    this.pending = new Map()
    this.websocket = null
    this.heartbeatTimer = null
    this.isClosed = false
    this.joined = false
    this.seated = false
    this.stats = {
      httpMs: page.httpMs,
      pageBytes: page.pageBytes,
      websocketOpenMs: null,
      joinMs: null,
      eventMs: [],
      messages: 0,
      bytesReceived: 0,
      diffs: 0
    }

    this.closedPromise = new Promise((resolvePromise) => {
      this.resolveClosed = resolvePromise
    })
  }

  async connect() {
    const websocketUrl = new URL("/live/websocket", this.config.target)
    websocketUrl.protocol = websocketUrl.protocol === "https:" ? "wss:" : "ws:"
    websocketUrl.searchParams.set("_csrf_token", this.page.csrfToken)
    websocketUrl.searchParams.set("vsn", "2.0.0")

    const startedAt = performance.now()
    this.websocket = new WebSocket(websocketUrl, [], {
      followRedirects: true,
      handshakeTimeout: this.config.requestTimeoutMs,
      headers: {
        cookie: this.page.cookie,
        origin: this.config.target.origin,
        "user-agent": USER_AGENT
      },
      perMessageDeflate: false
    })

    this.websocket.on("message", (data) => this.handleMessage(data))
    this.websocket.on("close", (code, reason) => this.handleClose(code, reason))

    await new Promise((resolvePromise, rejectPromise) => {
      const timer = setTimeout(() => {
        rejectPromise(new Error(`${this.page.clientLabel} WebSocket open timed out`))
      }, this.config.requestTimeoutMs)

      this.websocket.once("open", () => {
        clearTimeout(timer)
        resolvePromise()
      })
      this.websocket.once("error", (error) => {
        clearTimeout(timer)
        rejectPromise(error)
      })
    })

    this.stats.websocketOpenMs = performance.now() - startedAt
    const joinStartedAt = performance.now()

    await this.push(
      "phx_join",
      {
        url: this.page.pageUrl,
        params: {
          _csrf_token: this.page.csrfToken,
          _mounts: 0,
          _mount_attempts: 0,
          _track_static: this.page.trackedStatic
        },
        session: this.page.session,
        static: this.page.staticToken,
        sticky: false
      },
      {joining: true}
    )

    this.stats.joinMs = performance.now() - joinStartedAt
    this.joined = true
    this.heartbeatTimer = setInterval(() => this.sendHeartbeat(), 20_000)
  }

  handleMessage(data) {
    const text = data.toString()
    this.stats.messages += 1
    this.stats.bytesReceived += Buffer.byteLength(text)

    let message

    try {
      message = JSON.parse(text)
    } catch (_error) {
      return
    }

    if (!Array.isArray(message) || message.length !== 5) return

    const [_joinRef, ref, _topic, event, payload] = message

    if (event === "diff") this.stats.diffs += 1

    if (event === "phx_reply" && ref && this.pending.has(ref)) {
      const pending = this.pending.get(ref)
      this.pending.delete(ref)
      clearTimeout(pending.timer)

      if (payload?.status === "ok") {
        pending.resolve(payload.response || {})
      } else {
        pending.reject(
          new Error(`${this.page.clientLabel} ${pending.event} failed: ${JSON.stringify(payload)}`)
        )
      }
    }
  }

  handleClose(code, reason) {
    this.isClosed = true
    this.joined = false
    clearInterval(this.heartbeatTimer)

    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer)
      pending.reject(
        new Error(
          `${this.page.clientLabel} WebSocket closed (${code} ${reason.toString()}) during ${pending.event}`
        )
      )
    }

    this.pending.clear()
    this.resolveClosed()
  }

  push(event, payload, {joining = false, timeoutMs = this.config.requestTimeoutMs} = {}) {
    if (!this.websocket || this.websocket.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error(`${this.page.clientLabel} WebSocket is not open`))
    }

    const ref = String(++this.ref)
    const joinRef = joining ? ref : this.joinRef
    if (joining) this.joinRef = ref

    return new Promise((resolvePromise, rejectPromise) => {
      const timer = setTimeout(() => {
        this.pending.delete(ref)
        rejectPromise(new Error(`${this.page.clientLabel} ${event} timed out`))
      }, timeoutMs)

      this.pending.set(ref, {event, resolve: resolvePromise, reject: rejectPromise, timer})
      this.websocket.send(JSON.stringify([joinRef, ref, this.topic, event, payload]))
    })
  }

  async sendEvent(event, value = {}) {
    const startedAt = performance.now()
    const reply = await this.push("event", {type: "click", event, value})
    this.stats.eventMs.push(performance.now() - startedAt)
    return reply
  }

  sendHeartbeat() {
    if (!this.websocket || this.websocket.readyState !== WebSocket.OPEN) return
    const ref = String(++this.ref)
    this.websocket.send(JSON.stringify([null, ref, "phoenix", "heartbeat", {}]))
  }

  async leaveGame() {
    if (!this.seated || this.isClosed) return
    await this.sendEvent("leave")
    this.seated = false
  }

  async close() {
    clearInterval(this.heartbeatTimer)
    if (!this.websocket || this.isClosed) return

    if (this.joined) {
      await this.push("phx_leave", {}, {timeoutMs: 2_000}).catch(() => {})
    }

    this.websocket.close(1000, "benchmark complete")
    await Promise.race([this.closedPromise, sleep(1_000)])

    if (!this.isClosed) this.websocket.terminate()
  }
}

async function setupMatch(config, runId, index) {
  const gameId = `private_load_${runId}_${String(index).padStart(4, "0")}`
  const firstPage = await fetchLivePage(config, gameId, `${gameId}:white`)

  if (!firstPage.roomReady) {
    return {accepted: false, gameId, clients: [], httpMs: [firstPage.httpMs]}
  }

  const secondPage = await fetchLivePage(config, gameId, `${gameId}:black`)

  if (!secondPage.roomReady) {
    throw new Error(`${gameId} disappeared before the second client joined`)
  }

  const white = new LiveViewClient(config, firstPage)
  const black = new LiveViewClient(config, secondPage)
  const clients = [white, black]

  try {
    await Promise.all(clients.map((client) => client.connect()))
    await white.sendEvent("sit", {game: gameId, color: "white"})
    white.seated = true
    await black.sendEvent("sit", {game: gameId, color: "black"})
    black.seated = true
    await white.sendEvent("start_game")
    await black.sendEvent("ready_to_start")

    if (config.exerciseMoves) {
      await sleep(50)
      await white.sendEvent("drag_move", {from_r: "6", from_c: "0", to_r: "5", to_c: "0"})
      await black.sendEvent("drag_move", {from_r: "1", from_c: "0", to_r: "2", to_c: "0"})
    }

    return {accepted: true, gameId, clients}
  } catch (error) {
    await Promise.allSettled(clients.map((client) => client.leaveGame()))
    await Promise.allSettled(clients.map((client) => client.close()))
    throw error
  }
}

async function mapWithConcurrency(items, concurrency, operation) {
  let nextIndex = 0

  const workers = Array.from({length: Math.min(concurrency, items.length)}, async () => {
    while (nextIndex < items.length) {
      const index = nextIndex
      nextIndex += 1
      await operation(items[index], index)
    }
  })

  await Promise.all(workers)
}

async function cleanupMatches(matches) {
  const cleanupErrors = []

  await mapWithConcurrency(matches, 20, async (match) => {
    for (const client of match.clients) {
      try {
        await client.leaveGame()
      } catch (error) {
        cleanupErrors.push(`${match.gameId}: ${errorMessage(error)}`)
      }
    }

    await Promise.allSettled(match.clients.map((client) => client.close()))
  })

  return cleanupErrors
}

async function probeHealth(config) {
  const startedAt = performance.now()

  try {
    const response = await fetch(new URL("/health", config.target), {
      headers: {accept: "application/json", "user-agent": USER_AGENT},
      signal: AbortSignal.timeout(Math.min(config.requestTimeoutMs, 5_000))
    })

    return {ok: response.ok, status: response.status, latencyMs: performance.now() - startedAt}
  } catch (error) {
    return {ok: false, status: null, latencyMs: performance.now() - startedAt, error: errorMessage(error)}
  }
}

function aggregateClients(matches) {
  return matches.flatMap((match) => match.clients)
}

async function writeReport(path, report) {
  const absolutePath = resolve(path)
  await mkdir(dirname(absolutePath), {recursive: true})
  await writeFile(absolutePath, `${JSON.stringify(report, null, 2)}\n`, "utf8")
  return absolutePath
}

async function main() {
  const config = parseArgs(process.argv.slice(2))
  const runId = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`
  const startedAt = performance.now()
  const setupResults = []
  const setupErrors = []
  const healthSamples = []
  let healthProbeRunning = false
  let healthTimer = null
  let acceptedMatches = []
  let rejectedMatches = []
  let cleanupErrors = []

  console.log("Mana Chess LiveView capacity benchmark")
  console.log(
    `target=${config.target.origin} matches=${config.matches} clients=${config.matches * 2} ramp_per_second=${config.rampPerSecond} hold_seconds=${config.holdSeconds}`
  )

  const sampleHealth = async () => {
    if (healthProbeRunning) return

    healthProbeRunning = true

    try {
      healthSamples.push(await probeHealth(config))
    } finally {
      healthProbeRunning = false
    }
  }

  try {
    const initialHealth = await probeHealth(config)
    healthSamples.push(initialHealth)

    if (!initialHealth.ok) {
      const reason = initialHealth.error || `HTTP ${initialHealth.status}`
      throw new Error(`target health preflight failed: ${reason}`)
    }

    healthTimer = setInterval(() => void sampleHealth(), 2_000)

    const setupPromises = []
    const launchIntervalMs = 1_000 / config.rampPerSecond
    let nextLaunchAt = performance.now()

    for (let index = 1; index <= config.matches; index += 1) {
      const delayMs = nextLaunchAt - performance.now()
      if (delayMs > 0) await sleep(delayMs)
      nextLaunchAt += launchIntervalMs

      setupPromises.push(
        setupMatch(config, runId, index)
          .then((result) => setupResults.push(result))
          .catch((error) => setupErrors.push({index, error: errorMessage(error)}))
      )
    }

    await Promise.all(setupPromises)
    acceptedMatches = setupResults.filter((result) => result.accepted)
    rejectedMatches = setupResults.filter((result) => !result.accepted)

    console.log(
      `ramp_complete accepted=${acceptedMatches.length} rejected=${rejectedMatches.length} errors=${setupErrors.length}`
    )

    await sleep(config.holdSeconds * 1_000)
  } finally {
    if (healthTimer) clearInterval(healthTimer)
    cleanupErrors = await cleanupMatches(acceptedMatches)

    while (healthProbeRunning) await sleep(25)
    await sampleHealth()
  }

  const clients = aggregateClients(acceptedMatches)
  const healthFailures = healthSamples.filter((sample) => !sample.ok)
  const joinLatencies = clients.map((client) => client.stats.joinMs).filter(Number.isFinite)
  const httpLatencies = clients.map((client) => client.stats.httpMs).filter(Number.isFinite)
  const openLatencies = clients
    .map((client) => client.stats.websocketOpenMs)
    .filter(Number.isFinite)
  const eventLatencies = clients.flatMap((client) => client.stats.eventMs)
  const joinSummary = latencySummary(joinLatencies)
  const capacityAccepted =
    acceptedMatches.length === config.matches ||
    (config.allowCapacityRejections && acceptedMatches.length > 0)
  const passed =
    setupErrors.length === 0 &&
    cleanupErrors.length === 0 &&
    healthFailures.length === 0 &&
    capacityAccepted &&
    joinSummary.p95_ms !== null &&
    joinSummary.p95_ms <= config.maxP95Ms

  const report = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    target: config.target.origin,
    config: {
      matches: config.matches,
      expected_clients: config.matches * 2,
      ramp_per_second: config.rampPerSecond,
      hold_seconds: config.holdSeconds,
      request_timeout_ms: config.requestTimeoutMs,
      max_p95_ms: config.maxP95Ms,
      allow_capacity_rejections: config.allowCapacityRejections,
      exercise_moves: config.exerciseMoves
    },
    result: passed ? "pass" : "fail",
    duration_ms: Number((performance.now() - startedAt).toFixed(2)),
    matches: {
      attempted: config.matches,
      accepted: acceptedMatches.length,
      rejected_by_capacity: rejectedMatches.length,
      setup_errors: setupErrors
    },
    clients: {
      connected: clients.length,
      messages_received: clients.reduce((total, client) => total + client.stats.messages, 0),
      bytes_received: clients.reduce((total, client) => total + client.stats.bytesReceived, 0),
      diffs_received: clients.reduce((total, client) => total + client.stats.diffs, 0)
    },
    latency: {
      http: latencySummary(httpLatencies),
      websocket_open: latencySummary(openLatencies),
      liveview_join: joinSummary,
      liveview_event: latencySummary(eventLatencies),
      health: latencySummary(healthSamples.map((sample) => sample.latencyMs))
    },
    health: {
      samples: healthSamples.length,
      failures: healthFailures
    },
    cleanup_errors: cleanupErrors
  }

  let reportPath = null
  if (config.output) reportPath = await writeReport(config.output, report)

  console.log(
    `connected=${report.clients.connected} join_p95_ms=${report.latency.liveview_join.p95_ms} event_p95_ms=${report.latency.liveview_event.p95_ms} health_p95_ms=${report.latency.health.p95_ms}`
  )
  console.log(
    `messages=${report.clients.messages_received} diffs=${report.clients.diffs_received} bytes=${report.clients.bytes_received} cleanup_errors=${cleanupErrors.length}`
  )
  if (reportPath) console.log(`report=${reportPath}`)
  console.log(`result=${report.result.toUpperCase()}`)

  if (!passed) process.exitCode = 1
}

main().catch((error) => {
  console.error(errorMessage(error))
  process.exitCode = 1
})
