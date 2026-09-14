import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
const positive = (value) => typeof value === 'number' && Number.isFinite(value) && value > 0
const stack = (id, amount, unit, chance = null) => ({ id, amount, unit, chance })

function ingredient(value, unit, amount, unresolved, label, tags = {}, details = {}) {
  if (Array.isArray(value)) {
    if (value.length === 1) return ingredient(value[0], unit, amount, unresolved, label, tags, details)
    unresolved.push(`${label}: alternative ingredients require a choice`)
    return []
  }
  if (!isObject(value)) {
    unresolved.push(`${label}: unsupported ingredient`)
    return []
  }
  if (value.type === 'gtceu:sized')
    return ingredient(value.ingredient, unit, value.count, unresolved, label, tags, details)
  if (value.type === 'gtceu:circuit') {
    details.circuit = value.configuration
    return []
  }
  if (value.type === 'gtceu:int_provider') {
    unresolved.push(`${label}: ranged amount requires review`)
    return []
  }
  if (value.nbt && (typeof value.nbt !== 'object' || Object.keys(value.nbt).length))
    unresolved.push(`${label}: NBT constraint requires review`)
  const id = unit === 'mB' ? (value.fluid ?? value.tag) : (value.item ?? value.tag)
  if (typeof id !== 'string' || !id || !positive(amount)) {
    unresolved.push(`${label}: missing identity or amount`)
    return []
  }
  const members = value.tag ? tags[`${unit}|${id}`] : null
  return [stack(members?.length === 1 ? members[0] : value.tag ? `#${id}` : id, amount, unit)]
}

function capability(
  contents,
  capability,
  unit,
  ticks,
  duration,
  unresolved,
  label,
  tags,
  details,
  inputs = false,
) {
  if (contents === undefined) return []
  if (!Array.isArray(contents)) {
    unresolved.push(`${label}.${capability}: expected an array`)
    return []
  }
  return contents.flatMap((entry, index) => {
    const value = entry?.content
    const name = `${label}.${capability}[${index}]`
    const amount = unit === 'mB' ? value?.amount : 1
    const selected = unit === 'mB' && value?.value !== undefined ? value.value : value
    const parsed = ingredient(selected, unit, amount, unresolved, name, tags, details)
    const chance = entry?.chance
    const denominator = entry?.maxChance ?? 10000
    if (chance !== undefined && positive(denominator)) {
      if (chance >= 0 && chance <= denominator) for (const item of parsed) item.chance = chance / denominator
      else unresolved.push(`${name}: chance is outside its denominator`)
    } else if (chance !== undefined) {
      unresolved.push(`${name}: invalid chance denominator`)
    }
    if (Number.isFinite(entry?.tierChanceBoost) && entry.tierChanceBoost)
      for (const item of parsed) item.chanceBoost = entry.tierChanceBoost / denominator
    if (ticks && !positive(duration)) unresolved.push(`${name}: duration is needed for per-tick input`)
    if (ticks && positive(duration)) for (const item of parsed) item.amount *= duration
    if (inputs && chance === 0) {
      details.catalysts.push(...parsed.map((item) => ({ ...item, chance: null })))
      return []
    }
    return parsed
  })
}

function energy(recipe, unresolved) {
  const entries = recipe.tickInputs?.eu ?? []
  if (!Array.isArray(entries)) {
    unresolved.push('tickInputs.eu: expected an array')
    return null
  }
  if (entries.length === 0) return 0
  let total = 0
  for (const entry of entries) {
    const value = entry?.content
    const voltage = typeof value === 'number' ? value : value?.voltage
    const amperage = typeof value === 'number' ? 1 : (value?.amperage ?? 1)
    if (!Number.isFinite(voltage) || !positive(amperage)) {
      unresolved.push('tickInputs.eu: unsupported energy value')
      return null
    }
    total += voltage * amperage
  }
  return total
}

function gtRecipe(raw, sourcePath, id, sourceId, tags) {
  const unresolved = []
  const details = { catalysts: [], circuit: null }
  const durationTicks = positive(raw.duration) ? raw.duration : null
  const inputs = [
    ...capability(
      raw.inputs?.item,
      'item',
      'items',
      false,
      durationTicks,
      unresolved,
      'inputs',
      tags,
      details,
      true,
    ),
    ...capability(
      raw.inputs?.fluid,
      'fluid',
      'mB',
      false,
      durationTicks,
      unresolved,
      'inputs',
      tags,
      details,
      true,
    ),
    ...capability(
      raw.tickInputs?.item,
      'item',
      'items',
      true,
      durationTicks,
      unresolved,
      'tickInputs',
      tags,
      details,
      true,
    ),
    ...capability(
      raw.tickInputs?.fluid,
      'fluid',
      'mB',
      true,
      durationTicks,
      unresolved,
      'tickInputs',
      tags,
      details,
      true,
    ),
  ]
  const outputs = [
    ...capability(
      raw.outputs?.item,
      'item',
      'items',
      false,
      durationTicks,
      unresolved,
      'outputs',
      tags,
      details,
    ),
    ...capability(
      raw.outputs?.fluid,
      'fluid',
      'mB',
      false,
      durationTicks,
      unresolved,
      'outputs',
      tags,
      details,
    ),
    ...capability(
      raw.tickOutputs?.item,
      'item',
      'items',
      true,
      durationTicks,
      unresolved,
      'tickOutputs',
      tags,
      details,
    ),
    ...capability(
      raw.tickOutputs?.fluid,
      'fluid',
      'mB',
      true,
      durationTicks,
      unresolved,
      'tickOutputs',
      tags,
      details,
    ),
  ]
  for (const [group, value] of Object.entries({
    inputs: raw.inputs,
    outputs: raw.outputs,
    tickInputs: raw.tickInputs,
    tickOutputs: raw.tickOutputs,
  })) {
    for (const key of Object.keys(value ?? {})) {
      if (!['item', 'fluid', 'eu'].includes(key)) unresolved.push(`${group}.${key}: unsupported capability`)
      if (key === 'eu' && group !== 'tickInputs') unresolved.push(`${group}.eu: nonstandard energy flow`)
    }
  }
  if (raw.recipeConditions?.length) unresolved.push('Recipe has operating conditions')
  if (raw['kubejs:actions']?.length) unresolved.push('Recipe has ingredient actions')
  if (raw.data && Object.keys(raw.data).length) unresolved.push('Recipe has additional data')
  return {
    key: `runtime:${id}`,
    sourceId,
    sourcePath,
    sourceLine: 1,
    gameId: id,
    family: 'gtceu',
    machine: raw.type.slice('gtceu:'.length),
    inputs,
    outputs,
    catalysts: details.catalysts,
    durationTicks,
    eut: energy(raw, unresolved),
    circuit: details.circuit,
    unresolved: [...new Set(unresolved)],
  }
}

const itemStack = (value, tags, unresolved, label, count = 1) => {
  const selected = typeof value === 'string' ? { item: value } : value
  const unit = selected?.fluid ? 'mB' : 'items'
  const amount = selected?.amount ?? selected?.count ?? count
  const parsed = ingredient(selected, unit, amount, unresolved, label, tags)
  if (selected?.chance != null) {
    if (selected.chance >= 0 && selected.chance <= 1)
      for (const entry of parsed) entry.chance = selected.chance
    else unresolved.push(`${label}: weighted chance needs normalization`)
  }
  return parsed
}

const compactStacks = (stacks) => {
  const result = new Map()
  for (const item of stacks) {
    const key = `${item.id}|${item.unit}|${item.chance ?? ''}`
    const existing = result.get(key)
    if (existing) existing.amount += item.amount
    else result.set(key, { ...item })
  }
  return [...result.values()]
}

function otherRecipe(raw, sourcePath, id, sourceId, tags) {
  const type = raw.type ?? 'unknown'
  const unresolved = []
  let inputs = []
  let outputs = []
  let durationTicks = null
  if (type === 'minecraft:crafting_shaped') {
    const symbols = [...(raw.pattern ?? []).join('')].filter((symbol) => symbol !== ' ')
    inputs = symbols.flatMap((symbol, index) =>
      itemStack(raw.key?.[symbol], tags, unresolved, `pattern[${index}]`),
    )
    outputs = itemStack(raw.result, tags, unresolved, 'result')
  } else if (type === 'minecraft:stonecutting') {
    inputs = itemStack(raw.ingredient, tags, unresolved, 'ingredient')
    outputs = itemStack(raw.result, tags, unresolved, 'result', raw.count ?? 1)
  } else if (
    type === 'minecraft:crafting_shapeless' ||
    (type.startsWith('minecraft:') && 'ingredient' in raw)
  ) {
    inputs = (raw.ingredients ?? [raw.ingredient]).flatMap((item, index) =>
      itemStack(item, tags, unresolved, `ingredients[${index}]`),
    )
    outputs = itemStack(raw.result, tags, unresolved, 'result', raw.count ?? 1)
    durationTicks = raw.cookingtime ?? null
  } else if (type.startsWith('create:') || type.startsWith('vintage:')) {
    inputs = (raw.ingredients ?? (raw.ingredient ? [raw.ingredient] : [])).flatMap((item, index) =>
      itemStack(item, tags, unresolved, `ingredients[${index}]`),
    )
    outputs = (raw.results ?? (raw.result ? [raw.result] : [])).flatMap((item, index) =>
      itemStack(item, tags, unresolved, `results[${index}]`),
    )
    durationTicks = raw.processingTime ?? null
    if (raw.heatRequirement) unresolved.push(`Heat requirement: ${raw.heatRequirement}`)
    if (raw.sequence) unresolved.push('Sequenced assembly needs step-level review')
  } else if (type === 'exnihilosequentia:sifting') {
    inputs = itemStack(raw.input, tags, unresolved, 'input')
    outputs = itemStack(raw.result, tags, unresolved, 'result')
    if (outputs[0] && raw.rolls?.length === 1) outputs[0].chance = raw.rolls[0].chance
    if (raw.rolls?.length !== 1) unresolved.push('Mesh-specific rolls need selection')
  } else {
    unresolved.push(`${type}: recipe type needs an adapter`)
    const result = raw.result ?? raw.output
    if (result) outputs = itemStack(result, tags, unresolved, 'result')
  }
  if (raw.nbt || raw['kubejs:actions']) unresolved.push('Recipe has additional data')
  return {
    key: `runtime:${id}`,
    sourceId,
    sourcePath,
    sourceLine: 1,
    gameId: id,
    family: type,
    machine: String(type).split(':').pop(),
    inputs: compactStacks(inputs),
    outputs: compactStacks(outputs),
    catalysts: [],
    durationTicks,
    eut: type.startsWith('create:') || type.startsWith('vintage:') ? 0 : null,
    circuit: null,
    unresolved: [...new Set(unresolved)],
  }
}

async function filesUnder(root, relative = '') {
  const entries = await readdir(path.join(root, relative), { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const child = path.posix.join(relative, entry.name)
    if (entry.isDirectory()) files.push(...(await filesUnder(root, child)))
    else if (entry.isFile() && child.endsWith('.json')) files.push(child)
  }
  return files
}

async function exportTags(exportRoot) {
  const tags = {}
  for (const [folder, unit] of [
    ['item', 'items'],
    ['fluid', 'mB'],
  ]) {
    const root = path.join(exportRoot, 'tags', 'minecraft', folder)
    let files
    try {
      files = await filesUnder(root)
    } catch (error) {
      if (error.code === 'ENOENT') continue
      throw error
    }
    for (const relative of files) {
      const [namespace, ...parts] = relative.slice(0, -5).split('/')
      const members = JSON.parse(await readFile(path.join(root, relative), 'utf8'))
      if (Array.isArray(members))
        tags[`${unit}|${namespace}:${parts.join('/')}`] = [
          ...new Set(members.filter((item) => typeof item === 'string')),
        ]
    }
  }
  return tags
}

export async function importKubeJsExport(exportRoot, sourceId = 'star-technology-runtime') {
  const recipesRoot = path.join(exportRoot, 'recipes')
  const files = (await filesUnder(recipesRoot)).sort()
  if (!files.length) throw new Error(`No recipe JSON files found in ${recipesRoot}`)
  const tags = await exportTags(exportRoot)
  const recipes = []
  const rawRecipes = {}
  const diagnostics = []
  for (const relative of files) {
    const sourcePath = path.posix.join('recipes', relative)
    const segments = relative.slice(0, -5).split('/')
    const id = `${segments.shift()}:${segments.join('/')}`
    if (!id.includes(':') || id.endsWith(':')) {
      diagnostics.push({ file: sourcePath, issue: 'Cannot derive recipe ID from path' })
      continue
    }
    try {
      const raw = JSON.parse(await readFile(path.join(recipesRoot, relative), 'utf8'))
      rawRecipes[`runtime:${id}`] = raw
      recipes.push(
        String(raw.type ?? '').startsWith('gtceu:')
          ? gtRecipe(raw, sourcePath, id, sourceId, tags)
          : otherRecipe(raw, sourcePath, id, sourceId, tags),
      )
    } catch (error) {
      diagnostics.push({ file: sourcePath, issue: String(error) })
    }
  }
  return { recipes, diagnostics, fileCount: files.length, tags, rawRecipes }
}
