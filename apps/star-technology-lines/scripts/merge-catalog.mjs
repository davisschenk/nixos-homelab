import { SCHEMA_VERSION, validateCatalog } from './catalog-schema.mjs'

export function mergeCatalog(metadata, contributions) {
  const catalog = {
    schemaVersion: SCHEMA_VERSION,
    ...metadata,
    sources: [],
    recipes: [],
    tags: {},
    diagnostics: [],
    fileCount: 0,
  }
  const sourceIds = new Set()
  const recipeKeys = new Set()
  for (const contribution of contributions) {
    for (const source of contribution.sources ?? []) {
      if (sourceIds.has(source.id)) throw new Error(`Duplicate source ID: ${source.id}`)
      sourceIds.add(source.id)
      catalog.sources.push(source)
    }
    for (const recipe of contribution.recipes ?? []) {
      if (recipeKeys.has(recipe.key)) throw new Error(`Duplicate recipe key: ${recipe.key}`)
      recipeKeys.add(recipe.key)
      catalog.recipes.push(recipe)
    }
    for (const [tag, members] of Object.entries(contribution.tags ?? {})) {
      const previous = catalog.tags[tag]
      if (previous && JSON.stringify(previous) !== JSON.stringify(members))
        throw new Error(`Conflicting tag members: ${tag}`)
      catalog.tags[tag] = members
    }
    catalog.diagnostics.push(...(contribution.diagnostics ?? []))
    catalog.fileCount += contribution.fileCount ?? 0
  }
  return validateCatalog(catalog)
}
