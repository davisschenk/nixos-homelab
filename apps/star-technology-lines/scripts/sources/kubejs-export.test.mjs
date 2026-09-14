import assert from 'node:assert/strict'
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import test from 'node:test'
import { importKubeJsExport } from './kubejs-export.mjs'

test('imports finalized GT recipes with counts, fluids, energy, and chance', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'starline-export-'))
  try {
    const folder = path.join(root, 'recipes', 'start')
    await mkdir(folder, { recursive: true })
    await writeFile(
      path.join(folder, 'example.json'),
      JSON.stringify({
        type: 'gtceu:chemical_reactor',
        duration: 200,
        inputs: {
          item: [
            { content: { type: 'gtceu:sized', count: 3, ingredient: { item: 'minecraft:iron_ingot' } } },
          ],
          fluid: [{ content: { amount: 1000, value: [{ fluid: 'minecraft:water' }] } }],
        },
        outputs: {
          item: [{ content: { item: 'start:product' }, chance: 2500, maxChance: 10000 }],
        },
        tickInputs: { eu: [{ content: { voltage: 30, amperage: 2 } }] },
      }),
    )
    const result = await importKubeJsExport(root)
    assert.equal(result.fileCount, 1)
    assert.equal(result.diagnostics.length, 0)
    assert.deepEqual(result.recipes[0].inputs, [
      { id: 'minecraft:iron_ingot', amount: 3, unit: 'items', chance: null },
      { id: 'minecraft:water', amount: 1000, unit: 'mB', chance: null },
    ])
    assert.equal(result.recipes[0].outputs[0].chance, 0.25)
    assert.equal(result.recipes[0].eut, 60)
    assert.equal(result.recipes[0].durationTicks, 200)
    assert.deepEqual(result.recipes[0].unresolved, [])
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('keeps ambiguous ingredients and unknown recipe types for review', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'starline-export-'))
  try {
    const folder = path.join(root, 'recipes', 'start')
    await mkdir(folder, { recursive: true })
    await writeFile(
      path.join(folder, 'choice.json'),
      JSON.stringify({
        type: 'gtceu:assembler',
        duration: 80,
        inputs: {
          item: [{ content: [{ item: 'minecraft:iron_ingot' }, { item: 'minecraft:copper_ingot' }] }],
        },
        outputs: { item: [{ content: { item: 'start:product' } }] },
        tickInputs: { eu: [{ content: 32 }] },
      }),
    )
    await writeFile(
      path.join(folder, 'mixing.json'),
      JSON.stringify({ type: 'unknown:mixing', ingredients: [], result: { item: 'start:product' } }),
    )
    const result = await importKubeJsExport(root)
    assert.equal(result.recipes.length, 2)
    assert.match(result.recipes[0].unresolved.join(' '), /alternative ingredients/)
    assert.match(result.recipes[1].unresolved.join(' '), /needs an adapter/)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('normalizes crafting, Create processing, and sifting while retaining exact export data', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'starline-export-'))
  try {
    const folder = path.join(root, 'recipes', 'start')
    await mkdir(folder, { recursive: true })
    const cases = {
      shaped: {
        type: 'minecraft:crafting_shaped',
        pattern: ['aa', 'aa'],
        key: { a: { item: 'minecraft:iron_ingot' } },
        result: { item: 'start:plate', count: 2 },
      },
      crushing: {
        type: 'create:crushing',
        ingredients: [{ item: 'start:ore' }],
        results: [{ item: 'start:crushed' }, { item: 'start:bonus', chance: 0.25 }],
        processingTime: 400,
      },
      sifting: {
        type: 'exnihilosequentia:sifting',
        input: { item: 'minecraft:gravel' },
        result: { item: 'start:pebble' },
        rolls: [{ mesh: 'string', chance: 0.1 }],
      },
    }
    for (const [name, recipe] of Object.entries(cases))
      await writeFile(path.join(folder, `${name}.json`), JSON.stringify(recipe))
    const result = await importKubeJsExport(root)
    const byId = Object.fromEntries(result.recipes.map((recipe) => [recipe.gameId, recipe]))
    assert.deepEqual(byId['start:shaped'].inputs, [
      { id: 'minecraft:iron_ingot', amount: 4, unit: 'items', chance: null },
    ])
    assert.equal(byId['start:shaped'].outputs[0].amount, 2)
    assert.equal(byId['start:crushing'].durationTicks, 400)
    assert.equal(byId['start:crushing'].outputs[1].chance, 0.25)
    assert.equal(byId['start:sifting'].outputs[0].chance, 0.1)
    assert.deepEqual(result.rawRecipes['runtime:start:shaped'], cases.shaped)
    assert.equal(Object.keys(result.rawRecipes).length, 3)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('resolves exported ore tags and separates non-consumed meshes and circuits', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'starline-export-'))
  try {
    const recipes = path.join(root, 'recipes', 'start', 'rock_filtrator')
    const tags = path.join(root, 'tags', 'minecraft', 'item', 'forge', 'raw_materials')
    await mkdir(recipes, { recursive: true })
    await mkdir(tags, { recursive: true })
    await writeFile(
      path.join(tags, 'gold.json'),
      JSON.stringify(['minecraft:raw_gold', 'minecraft:raw_gold']),
    )
    await writeFile(
      path.join(recipes, 'geodes.json'),
      JSON.stringify({
        type: 'gtceu:rock_filtrator',
        duration: 1200,
        inputs: {
          item: [
            { content: { type: 'gtceu:sized', count: 4, ingredient: { tag: 'forge:raw_materials/gold' } } },
            { content: { item: 'exnihilosequentia:string_mesh' }, chance: 0, maxChance: 10000 },
            {
              content: {
                type: 'gtceu:sized',
                count: 1,
                ingredient: { type: 'gtceu:circuit', configuration: 2 },
              },
              chance: 0,
              maxChance: 10000,
            },
          ],
        },
        outputs: {
          item: [{ content: { item: 'kubejs:diamond_geode' }, chance: 3500, tierChanceBoost: 750 }],
        },
        tickInputs: { eu: [{ content: 15 }] },
      }),
    )
    const result = await importKubeJsExport(root)
    const recipe = result.recipes[0]
    assert.equal(recipe.inputs.length, 1)
    assert.equal(recipe.inputs[0].id, 'minecraft:raw_gold')
    assert.equal(recipe.catalysts[0].id, 'exnihilosequentia:string_mesh')
    assert.equal(recipe.circuit, 2)
    assert.equal(recipe.outputs[0].chance, 0.35)
    assert.equal(recipe.outputs[0].chanceBoost, 0.075)
    assert.deepEqual(recipe.unresolved, [])
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
