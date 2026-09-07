// Build a move-data override table from Pokémon Showdown's `data/moves.ts` (MIT).
//
// Why this exists: PokéAPI is the app's move source, but its `move_meta` table stops at
// generation 7 — 92 of the 177 gen-8+ moves carry no meta row at all, so multi-hit, drain,
// ailment, flinch and crit-rate all decode as nil. Showdown keeps a complete, battle-verified
// table, so we mirror the *values* it exposes as plain data and leave its JS callbacks alone.
//
// The output is a plain override map keyed by PokéAPI move id (Showdown's `num`), reporting
// which fields it corrects and which moves still need hand-written engine work.
//
// Usage: node scripts/extract-showdown-moves.mjs [--out <path>]
// Requires Node 22.6+ (native TypeScript type stripping — the source is a .ts file).

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'

const MOVES_URL = 'https://raw.githubusercontent.com/smogon/pokemon-showdown/master/data/moves.ts'
const POKEAPI_GRAPHQL = 'https://graphql.pokeapi.co/v1beta2'
const CACHE_DIR = join(import.meta.dirname, '..', '.cache', 'showdown')

/** Showdown status codes → the PokéAPI ailment names `MoveSpec.ailment` already carries. */
const AILMENT_BY_STATUS = {
  psn: 'poison', tox: 'poison', brn: 'burn',
  frz: 'freeze', par: 'paralysis', slp: 'sleep',
}

/** Volatile statuses that map onto an ailment the engine implements. Everything else is engine work. */
const AILMENT_BY_VOLATILE = { confusion: 'confusion' }

/** Chance fields whose zero the engine already reads as "always" on a status move. */
const CHANCE_FIELDS = new Set(['ailmentChance', 'statChance', 'flinchChance'])

/** Showdown `critRatio` → the crit *stage* bump `MoveSpec.critRate` carries (ratio 1 is baseline). */
const critStageFromRatio = (ratio) => (typeof ratio === 'number' ? Math.max(0, ratio - 1) : undefined)

/** Showdown writes fractions as `[numerator, denominator]`; the engine stores whole percents. */
const percentOfFraction = (fraction) =>
  Array.isArray(fraction) && fraction[1] ? Math.round((fraction[0] / fraction[1]) * 100) : undefined

async function cached(name, fetcher) {
  const path = join(CACHE_DIR, name)
  try {
    return await readFile(path, 'utf8')
  } catch {
    const body = await fetcher()
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, body)
    return body
  }
}

async function loadShowdownMoves() {
  const path = join(CACHE_DIR, 'moves.ts')
  await cached('moves.ts', async () => {
    const response = await fetch(MOVES_URL)
    if (!response.ok) throw new Error(`showdown moves.ts: HTTP ${response.status}`)
    return await response.text()
  })
  // Node strips the type annotations on import, so the callbacks stay as (uncalled) functions.
  const { Moves } = await import(path)
  return Moves
}

async function loadPokeAPIMoves() {
  const query = `{
    move(order_by: {id: asc}) {
      id name power accuracy move_damage_class_id
      movemetum {
        crit_rate ailment_chance flinch_chance stat_chance drain healing
        min_hits max_hits movemetaailment { name }
      }
    }
  }`
  const body = await cached('pokeapi-moves.json', async () => {
    const response = await fetch(POKEAPI_GRAPHQL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ query }),
    })
    if (!response.ok) throw new Error(`pokeapi: HTTP ${response.status}`)
    return await response.text()
  })
  const parsed = JSON.parse(body)
  if (parsed.errors) throw new Error(`pokeapi: ${parsed.errors[0].message}`)
  return new Map(parsed.data.move.map((move) => [move.id, move]))
}

/**
 * `MoveSpec.drain` is one signed percent: positive heals a share of the damage dealt, negative
 * is recoil. Showdown splits the two into `drain` and `recoil`; no move carries both.
 */
function drainPercent(move) {
  const drain = percentOfFraction(move.drain)
  if (drain !== undefined) return drain
  const recoil = percentOfFraction(move.recoil)
  return recoil === undefined ? undefined : -recoil
}

/**
 * The engine-facing view of one Showdown entry — only fields that are plain data.
 * Anything Showdown expresses as a callback is reported separately as engine work.
 */
function readShowdownMove(move) {
  const secondary = move.secondary ?? (Array.isArray(move.secondaries) ? move.secondaries[0] : null)
  const read = {
    // `accuracy: true` means "never misses"; the engine spells that `nil`.
    accuracy: move.accuracy === true ? null : move.accuracy,
    power: move.basePower,
    critRate: critStageFromRatio(move.critRatio),
    // Recoil is a negative drain — one field carries both, matching `MoveSpec.drain`.
    drain: drainPercent(move),
    healing: percentOfFraction(move.heal),
  }

  if (typeof move.multihit === 'number') {
    read.minHits = move.multihit
    read.maxHits = move.multihit
  } else if (Array.isArray(move.multihit)) {
    read.minHits = move.multihit[0]
    read.maxHits = move.multihit[1]
  }

  // A primary status lands every time; a secondary one rolls its own chance.
  const primaryAilment = AILMENT_BY_STATUS[move.status] ?? AILMENT_BY_VOLATILE[move.volatileStatus]
  if (primaryAilment) {
    read.ailment = primaryAilment
    read.ailmentChance = 100
  } else if (secondary) {
    const ailment = AILMENT_BY_STATUS[secondary.status] ?? AILMENT_BY_VOLATILE[secondary.volatileStatus]
    if (ailment) {
      read.ailment = ailment
      read.ailmentChance = secondary.chance ?? 100
    }
    if (secondary.volatileStatus === 'flinch') read.flinchChance = secondary.chance ?? 100
    if (secondary.boosts) read.statChance = secondary.chance ?? 100
  }

  return Object.fromEntries(Object.entries(read).filter(([, value]) => value !== undefined))
}

/**
 * The categorical effects — the ones where every move in the category does the same thing and
 * only the name differs. The engine implements the effect once and asks this table which move
 * calls it, so a new Reflect-alike or a second snow move cannot go missing behind a hand-kept
 * id list. Anything expressed as a callback (variable power, fixed damage) is *not* here: those
 * are one formula per move and stay hand-written.
 */
function readEffects(move) {
  const effect = {}
  if (move.weather) effect.weather = move.weather
  if (move.terrain) effect.terrain = move.terrain
  if (move.sideCondition) {
    effect.sideCondition = move.sideCondition
    // Reflect lands on the user's side, Spikes on the target's — the name alone cannot say which.
    effect.sideConditionTarget = move.target === 'foeSide' ? 'foeSide' : 'allySide'
  }
  const volatile = move.volatileStatus ?? move.secondary?.volatileStatus
  if (volatile && volatile !== 'flinch' && !AILMENT_BY_VOLATILE[volatile]) effect.volatileStatus = volatile
  return effect
}

/** Why a move cannot be fixed by data alone — each reason is hand-written engine work. */
function engineWorkReasons(move) {
  const reasons = []
  if (move.basePowerCallback) reasons.push('variable power (basePowerCallback)')
  if (move.damageCallback) reasons.push('fixed damage (damageCallback)')
  if (move.ohko) reasons.push('one-hit KO')
  const volatile = move.volatileStatus ?? move.secondary?.volatileStatus
  if (volatile && volatile !== 'flinch' && !AILMENT_BY_VOLATILE[volatile]) {
    reasons.push(`volatile status '${volatile}'`)
  }
  if (move.weather) reasons.push(`weather '${move.weather}'`)
  if (move.terrain) reasons.push(`terrain '${move.terrain}'`)
  if (move.sideCondition) reasons.push(`side condition '${move.sideCondition}'`)
  return reasons
}

/**
 * Do the two sources already agree on this field, once each side's spelling of "nothing" is
 * normalised? Without this every status move reports a `power` change (PokéAPI leaves it null,
 * Showdown writes 0) and every never-miss move reports an `accuracy` change (both mean nil).
 */
function sameValue(field, apiValue, showdownValue, isStatusMove) {
  // `MoveSpec.from` already decodes a missing power as 0, so null and 0 are the same move.
  if (field === 'power') return (apiValue ?? 0) === (showdownValue ?? 0)
  // `MoveSpec.chancePercent` reads a zero or missing chance as "always" on a status move and
  // "never" on a damaging one. Without this every sleep/paralysis move reports a false change.
  if (CHANCE_FIELDS.has(field)) {
    const effective = (apiValue ?? 0) > 0 ? apiValue : (isStatusMove ? 100 : 0)
    return effective === showdownValue
  }
  // Both sources spell "never misses" as an absent value by the time it reaches the engine.
  if (apiValue === null || apiValue === undefined) return showdownValue === null
  // PokéAPI spells "no ailment" as the literal name `none`, not as an absent value.
  if (field === 'ailment' && apiValue === 'none') return false
  return apiValue === showdownValue
}

/** Fields where PokéAPI and Showdown actually disagree, plus the ones PokéAPI never supplied. */
function diffAgainstPokeAPI(showdown, api) {
  const meta = api.movemetum
  const current = {
    // Raw, *not* normalised: PokéAPI's `0` for a never-miss move is the defect this table
    // corrects, and `MoveSpec.from` passes it straight through as a 0% hit chance.
    accuracy: api.accuracy,
    power: api.power,
    critRate: meta?.crit_rate,
    drain: meta?.drain,
    healing: meta?.healing,
    flinchChance: meta?.flinch_chance,
    statChance: meta?.stat_chance,
    minHits: meta?.min_hits,
    maxHits: meta?.max_hits,
    ailment: meta?.movemetaailment?.name,
    ailmentChance: meta?.ailment_chance,
  }

  const isStatusMove = api.move_damage_class_id === 1
  const changed = {}
  for (const [field, value] of Object.entries(showdown)) {
    if (!sameValue(field, current[field], value, isStatusMove)) changed[field] = value
  }
  return { changed, hadMeta: Boolean(meta) }
}

/** Swift literal for one field, or null where the source deliberately carries "no value". */
const swiftLiteral = (value) => (typeof value === 'string' ? `"${value}"` : String(value))

/**
 * Render the override map as a Swift source file. Generated rather than parsed at runtime so
 * the table costs nothing to load and a bad extraction breaks the build instead of a battle.
 */
function renderSwift(overrides, effects) {
  const entries = Object.entries(overrides)
    .map(([id, override]) => [Number(id), override])
    .sort((a, b) => a[0] - b[0])

  const effectLines = Object.entries(effects)
    .map(([id, effect]) => [Number(id), effect])
    .sort((a, b) => a[0] - b[0])
    .map(([id, { name, ...fields }]) => {
      const parts = Object.entries(fields).map(([field, value]) => `${field}: ${swiftLiteral(value)}`)
      return `        ${id}: .init(${parts.join(', ')}),  // ${name}`
    })

  const lines = entries.map(([id, { name, ...fields }]) => {
    const parts = []
    // Showdown's `accuracy: true` arrives here as null — the move never misses.
    if ('accuracy' in fields) {
      parts.push(fields.accuracy === null ? 'alwaysHits: true' : `accuracy: ${fields.accuracy}`)
      delete fields.accuracy
    }
    for (const [field, value] of Object.entries(fields)) parts.push(`${field}: ${swiftLiteral(value)}`)
    return `        ${id}: .init(${parts.join(', ')}),  // ${name}`
  })

  return `// Generated by scripts/extract-showdown-moves.mjs — do not edit by hand.
//
// Move values PokéAPI gets wrong or never supplies, mirrored from Pokémon Showdown's
// data/moves.ts (MIT). PokéAPI's \`move_meta\` table stops at generation 7, so most gen-8+
// moves decode with no multi-hit, drain, ailment, flinch or crit-rate at all, and it writes
// \`0\` rather than null for a move that never misses.
//
// Only plain data lives here. Moves Showdown expresses as callbacks (variable power, volatile
// statuses, weather) need engine support instead — see \`VariableDamage\` and the script's report.

/// One move's corrections. Every field is optional: an absent field keeps the PokéAPI value.
struct ShowdownMoveOverride: Sendable {
    /// The move never misses — the engine spells that \`MoveSpec.accuracy == nil\`.
    var alwaysHits = false
    var accuracy: Int?
    var power: Int?
    var critRate: Int?
    var drain: Int?
    var healing: Int?
    var minHits: Int?
    var maxHits: Int?
    var ailment: String?
    var ailmentChance: Int?
    var statChance: Int?
    var flinchChance: Int?
}

/// The categorical effect a move calls, if any. The engine implements each effect once and
/// looks up *which* move calls it here, instead of keeping its own list of ids.
struct ShowdownMoveEffect: Sendable {
    /// Showdown's own keys — the engine maps the ones it models and ignores the rest.
    var weather: String?
    var terrain: String?
    var sideCondition: String?
    /// Which side the condition lands on: \`allySide\` (Reflect) or \`foeSide\` (Spikes).
    var sideConditionTarget: String?
    var volatileStatus: String?
}

enum ShowdownMoveData {
    /// Keyed by PokéAPI move id (Showdown's \`num\`).
    static let overrides: [Int: ShowdownMoveOverride] = [
${lines.join('\n')}
    ]

    /// Keyed the same way. Present only for moves that call one of the categorical effects.
    static let effects: [Int: ShowdownMoveEffect] = [
${effectLines.join('\n')}
    ]
}

extension MoveSpec {
    /// This spec with Showdown's corrections applied. Called once per spec in \`MoveSpec.from\`,
    /// so a cached spec carries the corrected values and the wire never sees the PokéAPI gaps.
    func applyingShowdownOverrides() -> MoveSpec {
        guard let override = ShowdownMoveData.overrides[id] else { return self }
        var corrected = self
        if override.alwaysHits { corrected.accuracy = nil }
        if let accuracy = override.accuracy { corrected.accuracy = accuracy }
        if let power = override.power { corrected.power = power }
        if let critRate = override.critRate { corrected.critRate = critRate }
        if let drain = override.drain { corrected.drain = drain }
        if let healing = override.healing { corrected.healing = healing }
        if let minHits = override.minHits { corrected.minHits = minHits }
        if let maxHits = override.maxHits { corrected.maxHits = maxHits }
        if let ailment = override.ailment { corrected.ailment = ailment }
        if let ailmentChance = override.ailmentChance { corrected.ailmentChance = ailmentChance }
        if let statChance = override.statChance { corrected.statChance = statChance }
        if let flinchChance = override.flinchChance { corrected.flinchChance = flinchChance }
        return corrected
    }
}
`
}

async function main() {
  const outFlag = process.argv.indexOf('--out')
  const outPath = outFlag === -1
    ? join(import.meta.dirname, '..', '.cache', 'showdown-move-overrides.json')
    : process.argv[outFlag + 1]
  const swiftFlag = process.argv.indexOf('--swift')
  const swiftPath = swiftFlag === -1 ? null : process.argv[swiftFlag + 1]

  const [showdownMoves, apiMoves] = await Promise.all([loadShowdownMoves(), loadPokeAPIMoves()])

  const overrides = {}
  const effects = {}
  const engineWork = []
  let unmatched = 0
  let metaGapsFilled = 0
  const fieldCounts = {}

  for (const move of Object.values(showdownMoves)) {
    // Showdown carries Z-moves, Max moves and CAP fakemon that PokéAPI has no id for.
    const api = apiMoves.get(move.num)
    if (!move.num || move.num <= 0 || !api) { unmatched += 1; continue }

    const { changed, hadMeta } = diffAgainstPokeAPI(readShowdownMove(move), api)
    const effect = readEffects(move)
    if (Object.keys(effect).length) effects[move.num] = { name: move.name, ...effect }
    const reasons = engineWorkReasons(move)
    // `isNonstandard` marks moves no current game can produce (Z-moves, LGPE, CAP fakemon).
    // They reach the app only if PokéAPI hands one out, so they are not scoping work.
    if (reasons.length) {
      engineWork.push({ id: move.num, name: move.name, reasons, nonstandard: move.isNonstandard ?? null })
    }
    if (!Object.keys(changed).length) continue

    overrides[move.num] = { name: move.name, ...changed }
    if (!hadMeta) metaGapsFilled += 1
    for (const field of Object.keys(changed)) fieldCounts[field] = (fieldCounts[field] ?? 0) + 1
  }

  await mkdir(dirname(outPath), { recursive: true })
  await writeFile(outPath, `${JSON.stringify(overrides, null, 2)}\n`)
  const workPath = outPath.replace(/\.json$/, '-engine-work.json')
  await writeFile(workPath, `${JSON.stringify(engineWork, null, 2)}\n`)
  if (swiftPath) {
    await mkdir(dirname(swiftPath), { recursive: true })
    await writeFile(swiftPath, renderSwift(overrides, effects))
  }

  const byField = Object.entries(fieldCounts).sort((a, b) => b[1] - a[1])
  console.log(`showdown moves      ${Object.keys(showdownMoves).length}`)
  console.log(`no PokéAPI id       ${unmatched}`)
  console.log(`overrides written   ${Object.keys(overrides).length}  → ${outPath}`)
  console.log(`effects written     ${Object.keys(effects).length}`)
  console.log(`  of those, moves PokéAPI had no meta row for: ${metaGapsFilled}`)
  console.log('\ncorrected fields')
  for (const [field, count] of byField) console.log(`  ${field.padEnd(16)}${count}`)
  console.log(`\nstill needs engine work: ${engineWork.length}`)
  const reasonCounts = {}
  for (const { reasons } of engineWork) {
    for (const reason of reasons) {
      const kind = reason.replace(/'.*'/, '…')
      reasonCounts[kind] = (reasonCounts[kind] ?? 0) + 1
    }
  }
  for (const [reason, count] of Object.entries(reasonCounts).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${String(count).padStart(4)}  ${reason}`)
  }
}

await main()
