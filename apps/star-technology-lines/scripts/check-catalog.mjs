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
    recipe.unresolved.length === 0,
).length
const recipe = (id) => catalog.recipes.find((entry) => entry.gameId === id)
const mining = recipe('start:void_excavation/mining')
const gold = recipe('gtceu:macerator/macerate_raw_gold_ore_to_crushed_ore')
const sieve = recipe('start:mechanical_sieve/gravel_sieving')
const geodes = recipe('start:rock_filtrator/lv_geodes')
if (
  mining?.outputs.find((stack) => stack.id === 'minecraft:raw_gold')?.chance !== 0.4 ||
  mining.outputs.find((stack) => stack.id === 'minecraft:raw_gold')?.chanceBoost !== 0.075 ||
  gold?.inputs[0]?.id !== 'minecraft:raw_gold' ||
  gold.outputs[0]?.id !== 'gtceu:crushed_gold_ore' ||
  sieve?.catalysts[0]?.id !== 'exnihilosequentia:string_mesh' ||
  geodes?.circuit !== 0 ||
  geodes.outputs[0]?.chanceBoost !== 0.075
)
  throw new Error('Known resource processing recipes were not extracted correctly')
if (
  catalog.packVersion !== '1.20.1-THETA-1-HOTFIX-3' ||
  catalog.packMode !== 'default' ||
  catalog.sources[0]?.commit !== '26135f37ebad21800d7ffe61f29189d6f15254ab' ||
  ready < 30000
) {
  throw new Error('Catalog provenance or ready recipe coverage is incomplete')
}
console.log(
  `${catalog.packVersion}: ${catalog.recipes.length} declarations, ${withOutputs} with outputs, ${complete} fully parsed, ${ready} ready GT recipes`,
)
