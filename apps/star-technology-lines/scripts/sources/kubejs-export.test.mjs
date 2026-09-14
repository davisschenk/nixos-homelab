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
      JSON.stringify({ type: 'create:mixing', ingredients: [], results: [{ item: 'start:product' }] }),
    )
    const result = await importKubeJsExport(root)
    assert.equal(result.recipes.length, 2)
    assert.match(result.recipes[0].unresolved.join(' '), /alternative ingredients/)
    assert.match(result.recipes[1].unresolved.join(' '), /needs an adapter/)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
