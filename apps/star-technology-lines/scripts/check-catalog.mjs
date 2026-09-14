import { readFile } from 'node:fs/promises'
import { validateCatalog } from './catalog-schema.mjs'

const catalog = validateCatalog(
  JSON.parse(await readFile(new URL('../public/catalog.json', import.meta.url), 'utf8')),
)
const complete = catalog.recipes.filter((recipe) => recipe.unresolved.length === 0).length
const withOutputs = catalog.recipes.filter((recipe) => recipe.outputs.length > 0).length
const ready = catalog.recipes.filter(
  (recipe) =>
    recipe.family === 'gtceu' &&
    recipe.inputs.length &&
    recipe.outputs.length &&
    recipe.durationTicks != null &&
    recipe.eut != null &&
    recipe.inputs.every((stack) => stack.chance == null || stack.chance >= 1) &&
    recipe.outputs.every((stack) => stack.chance == null || stack.chance >= 1) &&
    recipe.unresolved.length === 0,
).length
const peek = catalog.recipes.find(
  (recipe) => recipe.gameId === 'start:peek_process' && recipe.machine === 'large_chemical_reactor',
)
if (
  !peek ||
  peek.durationTicks !== 250 ||
  peek.eut !== 30720 ||
  !peek.outputs.some((stack) => stack.id === 'gtceu:polyether_ether_ketone' && stack.amount === 2448)
) {
  throw new Error('Known PEEK recipe was not extracted correctly')
}
if (
  catalog.packVersion !== '1.20.1-THETA-1-HOTFIX-3' ||
  catalog.packMode !== 'default' ||
  catalog.sources[0]?.commit !== '26135f37ebad21800d7ffe61f29189d6f15254ab' ||
  ready < 2000
) {
  throw new Error('Catalog provenance or ready recipe coverage is incomplete')
}
console.log(
  `${catalog.packVersion}: ${catalog.recipes.length} declarations, ${withOutputs} with outputs, ${complete} fully parsed, ${ready} ready GT recipes`,
)
