export const SCHEMA_VERSION = 1

export function validateCatalog(catalog) {
  if (
    !catalog ||
    catalog.schemaVersion !== SCHEMA_VERSION ||
    !Array.isArray(catalog.sources) ||
    !Array.isArray(catalog.recipes)
  ) {
    throw new Error('Unsupported recipe catalog')
  }
  if (
    catalog.tags !== undefined &&
    (typeof catalog.tags !== 'object' ||
      catalog.tags === null ||
      Array.isArray(catalog.tags) ||
      Object.values(catalog.tags).some(
        (members) => !Array.isArray(members) || members.some((member) => typeof member !== 'string'),
      ))
  )
    throw new Error('Invalid catalog tags')
  const sourceIds = new Set()
  for (const source of catalog.sources) {
    if (!source.id || sourceIds.has(source.id) || !source.name || !source.kind)
      throw new Error(`Invalid or duplicate source: ${source.id}`)
    sourceIds.add(source.id)
  }
  const keys = new Set()
  for (const recipe of catalog.recipes) {
    if (
      !recipe.key ||
      keys.has(recipe.key) ||
      !sourceIds.has(recipe.sourceId) ||
      !recipe.machine ||
      !recipe.family ||
      typeof recipe.sourcePath !== 'string' ||
      !Number.isInteger(recipe.sourceLine) ||
      recipe.sourceLine < 1 ||
      !Array.isArray(recipe.inputs) ||
      !Array.isArray(recipe.outputs) ||
      !Array.isArray(recipe.catalysts) ||
      !Array.isArray(recipe.unresolved) ||
      recipe.unresolved.some((issue) => typeof issue !== 'string') ||
      (recipe.durationTicks !== null && !Number.isFinite(recipe.durationTicks)) ||
      (recipe.eut !== null && !Number.isFinite(recipe.eut))
    ) {
      throw new Error(`Invalid or duplicate recipe: ${recipe.key}`)
    }
    keys.add(recipe.key)
    for (const stack of [...recipe.inputs, ...recipe.outputs, ...recipe.catalysts]) {
      if (
        typeof stack.id !== 'string' ||
        !stack.id ||
        typeof stack.amount !== 'number' ||
        !Number.isFinite(stack.amount) ||
        stack.amount <= 0 ||
        !['items', 'mB'].includes(stack.unit) ||
        (stack.chance !== null &&
          (typeof stack.chance !== 'number' || stack.chance < 0 || stack.chance > 1)) ||
        (stack.chanceBoost !== undefined &&
          (typeof stack.chanceBoost !== 'number' || !Number.isFinite(stack.chanceBoost))) ||
        (stack.nbt !== undefined && typeof stack.nbt !== 'string')
      ) {
        throw new Error(`Invalid stack in recipe: ${recipe.key}`)
      }
    }
  }
  return catalog
}
