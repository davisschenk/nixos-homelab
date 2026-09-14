import { readFile } from 'node:fs/promises'
import { validateCatalog } from './catalog-schema.mjs'

const catalog = validateCatalog(
  JSON.parse(await readFile(new URL('../public/catalog.json', import.meta.url), 'utf8')),
)
const rawCatalog = JSON.parse(
  await readFile(new URL(`../public/${catalog.rawCatalog}`, import.meta.url), 'utf8'),
)
const complete = catalog.recipes.filter((recipe) => recipe.unresolved.length === 0).length
const withOutputs = catalog.recipes.filter((recipe) => recipe.outputs.length > 0).length
const registered = catalog.recipes.filter((recipe) => recipe.availability === 'registered')
const declarations = catalog.recipes.filter((recipe) => recipe.availability === 'source-declaration')
const registeredKeys = new Set(registered.map((recipe) => recipe.key))
if (
  registeredKeys.size !== registered.length ||
  registered.some((recipe) => !Object.hasOwn(rawCatalog.recipes, recipe.key)) ||
  Object.keys(rawCatalog.recipes).some((key) => !registeredKeys.has(key))
)
  throw new Error('Raw export and normalized registered recipes differ')
const ready = catalog.recipes.filter(
  (recipe) =>
    recipe.family === 'gtceu' &&
    recipe.availability === 'registered' &&
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
  geodes.outputs[0]?.chanceBoost !== 0.075 ||
  !rawCatalog.recipes?.[gold.key] ||
  !rawCatalog.recipes?.[geodes.key]
)
  throw new Error('Known resource processing recipes were not extracted correctly')
if (
  catalog.packVersion !== '1.20.1-THETA-1-HOTFIX-3' ||
  catalog.packMode !== 'default' ||
  catalog.sources[0]?.commit !== '26135f37ebad21800d7ffe61f29189d6f15254ab' ||
  catalog.sources.find((source) => source.id === 'star-technology-runtime')?.recipeCount !==
    registered.length ||
  registered.length !== 74072 ||
  declarations.length < 5000 ||
  Object.keys(rawCatalog.recipes).length !== registered.length ||
  rawCatalog.packVersion !== catalog.packVersion ||
  ready < 30000 ||
  registered.filter((recipe) => recipe.family === 'minecraft:crafting_shaped').length < 10000 ||
  registered.filter((recipe) => recipe.family === 'exnihilosequentia:sifting').length < 90
) {
  throw new Error('Catalog provenance or ready recipe coverage is incomplete')
}
console.log(
  `${catalog.packVersion}: ${registered.length} registered recipes, ${declarations.length} source declarations, ${withOutputs} with outputs, ${complete} fully parsed, ${ready} ready GT recipes`,
)
