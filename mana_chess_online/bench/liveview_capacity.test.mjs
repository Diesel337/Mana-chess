import assert from "node:assert/strict"
import test from "node:test"

import {
  gameIdFromBoardId,
  latencySummary,
  parseArgs,
  roomType,
  roomTypeSummary
} from "./liveview_capacity.mjs"

test("parseArgs keeps private mode as the local default", () => {
  const config = parseArgs([])

  assert.equal(config.mode, "private")
  assert.equal(config.matches, 10)
  assert.equal(config.target.origin, "http://127.0.0.1:4000")
})

test("parseArgs accepts competitive mode and explicit controls", () => {
  const config = parseArgs([
    "--mode=competitive",
    "--matches",
    "25",
    "--ramp-per-second=5",
    "--no-moves"
  ])

  assert.equal(config.mode, "competitive")
  assert.equal(config.matches, 25)
  assert.equal(config.rampPerSecond, 5)
  assert.equal(config.exerciseMoves, false)
})

test("parseArgs rejects unknown modes and unacknowledged remote targets", () => {
  assert.throws(() => parseArgs(["--mode", "ranked"]), /mode must be private or competitive/)
  assert.throws(
    () => parseArgs(["--url", "https://mana-chess.example"]),
    /remote targets require --allow-remote/
  )
})

test("gameIdFromBoardId extracts only non-empty Mana Chess board ids", () => {
  assert.equal(gameIdFromBoardId("mc-board-game_1"), "game_1")
  assert.equal(gameIdFromBoardId("mc-board-match_abc123"), "match_abc123")
  assert.equal(gameIdFromBoardId("mc-board-"), null)
  assert.equal(gameIdFromBoardId("board-game_1"), null)
  assert.equal(gameIdFromBoardId(undefined), null)
})

test("roomType classifies fixed, dynamic, and private rooms", () => {
  assert.equal(roomType("game_1"), "fixed_public")
  assert.equal(roomType("game_4"), "fixed_public")
  assert.equal(roomType("game_5"), "unknown")
  assert.equal(roomType("match_abc123"), "dynamic_public")
  assert.equal(roomType("private_abc123"), "private")
  assert.equal(roomType(null), "unknown")
})

test("roomTypeSummary counts every accepted match", () => {
  assert.deepEqual(
    roomTypeSummary([
      {gameId: "game_1"},
      {gameId: "game_2"},
      {gameId: "match_one"},
      {gameId: "private_one"},
      {gameId: "practice_one"}
    ]),
    {private: 1, dynamic_public: 1, fixed_public: 2, unknown: 1}
  )
})

test("latencySummary reports nearest-rank percentiles", () => {
  assert.deepEqual(latencySummary([]), {
    count: 0,
    p50_ms: null,
    p95_ms: null,
    p99_ms: null,
    max_ms: null
  })

  assert.deepEqual(latencySummary([1, 2, 3, 4, 5]), {
    count: 5,
    p50_ms: 3,
    p95_ms: 5,
    p99_ms: 5,
    max_ms: 5
  })
})
