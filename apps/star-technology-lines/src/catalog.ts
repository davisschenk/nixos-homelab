import { createStage, newId, type Port, type Stage } from './model'

export type RecipeStack = {
  id: string
  amount: number
  unit: 'items' | 'mB'
  chance: number | null
  minAmount?: number
  maxAmount?: number
  nbt?: string
}
export type CatalogRecipe = {
  key: string
  sourceId: string
  sourcePath: string
  sourceLine: number
  gameId: string | null
  family: string
  machine: string
  inputs: RecipeStack[]
  outputs: RecipeStack[]
  catalysts: RecipeStack[]
  durationTicks: number | null
  eut: number | null
  circuit: number | null
  unresolved: string[]
}
export type CatalogSource = {
  id: string
  name: string
  kind: string
  url: string
  commit: string
  license: string
  scope: string
}
export type Catalog = {
  schemaVersion: number
  generatedAt: string
  packVersion: string
  packMode: string
  sources: CatalogSource[]
  recipes: CatalogRecipe[]
  diagnostics: { file: string; issue: string }[]
  fileCount: number
}

export const displayName = (id: string) =>
  id
    .replace(/^#?[^:]+:/, '')
    .replaceAll('_', ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
export const displayStack = (stack: RecipeStack) =>
  `${stack.minAmount == null ? stack.amount : `${stack.minAmount}–${stack.maxAmount}`} ${stack.unit} ${displayName(stack.id)}`
export const recipeIsReady = (recipe: CatalogRecipe) =>
  recipe.family === 'gtceu' &&
  recipe.inputs.length > 0 &&
  recipe.outputs.length > 0 &&
  recipe.durationTicks != null &&
  recipe.eut != null &&
  recipe.inputs.every((stack) => stack.chance == null || stack.chance >= 1) &&
  recipe.outputs.every((stack) => stack.chance == null || stack.chance >= 1) &&
  recipe.unresolved.length === 0

export const sourceLink = (
  recipe: Pick<CatalogRecipe, 'sourceId' | 'sourcePath' | 'sourceLine'>,
  catalog: Catalog,
) => {
  const source = catalog.sources.find((item) => item.id === recipe.sourceId)
  return source?.url && source.commit
    ? `${source.url}/blob/${source.commit}/${recipe.sourcePath}#L${recipe.sourceLine}`
    : ''
}

export const stageFromRecipe = (recipe: CatalogRecipe, x: number, y: number): Stage => {
  const stage = createStage(x, y)
  const makePort = (stack: RecipeStack): Port => ({
    id: newId(),
    name: displayName(stack.id),
    amount: stack.amount,
    unit: stack.unit,
    materialId: stack.id,
  })
  return {
    ...stage,
    name: recipe.outputs.length
      ? displayName(recipe.outputs[0].id)
      : displayName(recipe.gameId ?? recipe.machine),
    machine: displayName(recipe.machine),
    tier: '—',
    duration: recipe.durationTicks == null ? null : recipe.durationTicks / 20,
    eut: recipe.eut,
    inputs: recipe.inputs.map(makePort),
    outputs: recipe.outputs.map(makePort),
    notes: [
      `Imported from ${recipe.sourcePath}:${recipe.sourceLine}.`,
      recipe.catalysts.length
        ? `Catalysts: ${recipe.catalysts.map((stack) => `${stack.amount} ${stack.unit} ${stack.id}`).join(', ')}.`
        : '',
      recipe.outputs.some((stack) => stack.minAmount != null)
        ? `Ranged outputs: ${recipe.outputs
            .filter((stack) => stack.minAmount != null)
            .map((stack) => `${stack.id} ${stack.minAmount}–${stack.maxAmount}`)
            .join(', ')}. The stage amount is the maximum, not an expected rate.`
        : '',
      [...recipe.inputs, ...recipe.outputs].some((stack) => stack.chance != null && stack.chance < 1)
        ? 'Chance-based stacks are shown at their full amount. Verify expected yield before using rates.'
        : '',
      recipe.circuit != null ? `Circuit: ${recipe.circuit}.` : '',
      !recipeIsReady(recipe)
        ? `Review source before use: ${recipe.unresolved.join('; ') || 'chance-based or incomplete recipe'}`
        : '',
    ]
      .filter(Boolean)
      .join('\n'),
    recipeRef: {
      key: recipe.key,
      sourceId: recipe.sourceId,
      sourcePath: recipe.sourcePath,
      sourceLine: recipe.sourceLine,
      gameId: recipe.gameId,
      unresolved: recipe.unresolved,
      reviewRequired: !recipeIsReady(recipe),
    },
  }
}

export const searchRecipes = (catalog: Catalog, query: string, includePartial: boolean, limit = 80) => {
  const terms = query.trim().toLowerCase().split(/\s+/).filter(Boolean)
  const matches = catalog.recipes.filter(
    (recipe) =>
      (includePartial || recipeIsReady(recipe)) &&
      terms.every((term) =>
        [
          recipe.machine,
          recipe.gameId ?? '',
          recipe.sourcePath,
          ...recipe.inputs.map((stack) => stack.id),
          ...recipe.outputs.map((stack) => stack.id),
        ].some((value) => value.toLowerCase().includes(term)),
      ),
  )
  matches.sort((a, b) => {
    const aOutput = a.outputs[0]?.id.toLowerCase() ?? ''
    const bOutput = b.outputs[0]?.id.toLowerCase() ?? ''
    const first = terms[0] ?? ''
    return Number(bOutput.includes(first)) - Number(aOutput.includes(first)) || aOutput.localeCompare(bOutput)
  })
  return matches.slice(0, limit)
}
