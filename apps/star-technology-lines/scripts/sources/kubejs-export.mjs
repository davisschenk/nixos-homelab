import { readdir, readFile } from 'node:fs/promises'
import path from 'node:path'

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value)
const positive = (value) => typeof value === 'number' && Number.isFinite(value) && value > 0
const stack = (id, amount, unit, chance = null) => ({ id, amount, unit, chance })

function ingredient(value, unit, amount, unresolved, label) {
  if (Array.isArray(value)) {
    if (value.length === 1) return ingredient(value[0], unit, amount, unresolved, label)
    unresolved.push(`${label}: alternative ingredients require a choice`)
    return []
  }
  if (!isObject(value)) {
    unresolved.push(`${label}: unsupported ingredient`)
    return []
  }
  if (value.type === 'gtceu:sized') return ingredient(value.ingredient, unit, value.count, unresolved, label)
  if (value.type === 'gtceu:int_provider') {
    unresolved.push(`${label}: ranged amount requires review`)
    return []
  }
  if (value.nbt) unresolved.push(`${label}: NBT constraint requires review`)
  const id = unit === 'mB' ? (value.fluid ?? value.tag) : (value.item ?? value.tag)
  if (!id || !positive(amount)) {
    unresolved.push(`${label}: missing identity or amount`)
    return []
  }
  return [stack(value.tag ? `#${id}` : id, amount, unit)]
}

function capability(contents, capability, unit, ticks, duration, unresolved, label) {
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
    const parsed = ingredient(selected, unit, amount, unresolved, name)
    const chance = entry?.chance
    const maxChance = entry?.maxChance
    if (chance !== undefined && maxChance !== undefined && positive(maxChance)) {
      for (const item of parsed) item.chance = chance / maxChance
    } else if (chance !== undefined) {
      unresolved.push(`${name}: chance denominator is unknown`)
    }
    if (ticks && !positive(duration)) unresolved.push(`${name}: duration is needed for per-tick input`)
    if (ticks && positive(duration)) for (const item of parsed) item.amount *= duration
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

function gtRecipe(raw, sourcePath, id, sourceId) {
  const unresolved = []
  const durationTicks = positive(raw.duration) ? raw.duration : null
  const inputs = [
    ...capability(raw.inputs?.item, 'item', 'items', false, durationTicks, unresolved, 'inputs'),
    ...capability(raw.inputs?.fluid, 'fluid', 'mB', false, durationTicks, unresolved, 'inputs'),
    ...capability(raw.tickInputs?.item, 'item', 'items', true, durationTicks, unresolved, 'tickInputs'),
    ...capability(raw.tickInputs?.fluid, 'fluid', 'mB', true, durationTicks, unresolved, 'tickInputs'),
  ]
  const outputs = [
    ...capability(raw.outputs?.item, 'item', 'items', false, durationTicks, unresolved, 'outputs'),
    ...capability(raw.outputs?.fluid, 'fluid', 'mB', false, durationTicks, unresolved, 'outputs'),
    ...capability(raw.tickOutputs?.item, 'item', 'items', true, durationTicks, unresolved, 'tickOutputs'),
    ...capability(raw.tickOutputs?.fluid, 'fluid', 'mB', true, durationTicks, unresolved, 'tickOutputs'),
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
    catalysts: [],
    durationTicks,
    eut: energy(raw, unresolved),
    circuit: null,
    unresolved: [...new Set(unresolved)],
  }
}

function otherRecipe(raw, sourcePath, id, sourceId) {
  const unresolved = [`${raw.type ?? 'unknown'}: recipe type needs an adapter`]
  const result = raw.result ?? raw.output
  const outputs = result ? ingredient(result, 'items', result.count ?? 1, unresolved, 'result') : []
  return {
    key: `runtime:${id}`,
    sourceId,
    sourcePath,
    sourceLine: 1,
    gameId: id,
    family: raw.type ?? 'unknown',
    machine: String(raw.type ?? 'unknown')
      .split(':')
      .pop(),
    inputs: [],
    outputs,
    catalysts: [],
    durationTicks: null,
    eut: null,
    circuit: null,
    unresolved,
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

export async function importKubeJsExport(exportRoot, sourceId = 'star-technology-runtime') {
  const recipesRoot = path.join(exportRoot, 'recipes')
  const files = (await filesUnder(recipesRoot)).sort()
  if (!files.length) throw new Error(`No recipe JSON files found in ${recipesRoot}`)
  const recipes = []
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
      recipes.push(
        String(raw.type ?? '').startsWith('gtceu:')
          ? gtRecipe(raw, sourcePath, id, sourceId)
          : otherRecipe(raw, sourcePath, id, sourceId),
      )
    } catch (error) {
      diagnostics.push({ file: sourcePath, issue: String(error) })
    }
  }
  return { recipes, diagnostics, fileCount: files.length }
}
