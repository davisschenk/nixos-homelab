import assert from 'node:assert/strict'
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { importKubeJs } from './kubejs.mjs'

test('extracts direct, looped, helper, and shaped recipes without running source code', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'starline-parser-'))
  try {
    const scripts = path.join(root, 'kubejs', 'server_scripts')
    await mkdir(scripts, { recursive: true })
    await writeFile(
      path.join(scripts, 'recipes.js'),
      `
ServerEvents.recipes((event) => {
  const id = global.id;
  ['alpha', 'beta'].forEach((name) => {
    event.recipes.gtceu.mixer(id(name))
      .itemInputs('2x gtceu:feed')
      .itemOutputs(\`gtceu:\${name}\`)
      .duration(40)
      .EUt(GTValues.VA[GTValues.MV]);
  });
  const makeDust = (name) => event.recipes.gtceu.macerator(id(name))
    .itemInputs('gtceu:stone').itemOutputs(\`gtceu:\${name}\`).duration(20).EUt(30);
  makeDust('dust');
  event.shaped('kubejs:widget', ['AA', ' B'], { A: 'minecraft:iron_ingot', B: 'minecraft:stick' });
});`,
    )
    const result = await importKubeJs(root, 'test')
    assert.equal(result.recipes.length, 4)
    assert.deepEqual(result.diagnostics, [])
    const alpha = result.recipes.find((recipe) => recipe.gameId === 'start:alpha')
    assert.equal(alpha.eut, 120)
    assert.equal(alpha.inputs[0].amount, 2)
    assert.equal(alpha.outputs[0].id, 'gtceu:alpha')
    assert.equal(result.recipes.find((recipe) => recipe.gameId === 'start:dust').machine, 'macerator')
    const shaped = result.recipes.find((recipe) => recipe.machine === 'shaped')
    assert.equal(shaped.inputs.find((stack) => stack.id === 'minecraft:iron_ingot').amount, 2)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('keeps default-mode recipes and captures layered and ranged outputs', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'starline-mode-'))
  try {
    const scripts = path.join(root, 'kubejs', 'server_scripts')
    await mkdir(path.join(scripts, 'common'), { recursive: true })
    await mkdir(path.join(scripts, 'hardmode'), { recursive: true })
    await writeFile(
      path.join(scripts, 'common', 'recipes.js'),
      `ServerEvents.recipes(event => {
        for (let i = 0; i <= 1; i++) {
          event.recipes.gtceu.riftion_accelerator(global.id('test_' + i))
            .inputFluids('gtceu:plasma 1000')
            .itemOutputsRanged('kubejs:fragment', 0, 32 * Math.pow(2, i))
            .duration(20).EUt(120)
        }
        event.recipes.gtceu.supreme_chemistry(global.id('layered'))
          .layeredRecipe(layers => layers.inputFluids('gtceu:extract 500').next().itemInputs('2x gtceu:dust'))
          .fluidOutputs('gtceu:product 250').duration(40).EUt(480)
      })`,
    )
    await writeFile(
      path.join(scripts, 'hardmode', 'excluded.js'),
      `ServerEvents.recipes(event => event.recipes.gtceu.mixer('hard').itemInputs('gtceu:a').itemOutputs('gtceu:b').duration(20).EUt(30))`,
    )
    const result = await importKubeJs(root, 'test', 'default')
    assert.equal(result.recipes.length, 3)
    const ranged = result.recipes.filter((recipe) => recipe.machine === 'riftion_accelerator')
    assert.deepEqual(
      ranged.map((recipe) => recipe.outputs[0].maxAmount),
      [32, 64],
    )
    assert.ok(ranged.every((recipe) => recipe.unresolved.some((issue) => issue.startsWith('Ranged output'))))
    const layered = result.recipes.find((recipe) => recipe.gameId === 'start:layered')
    assert.deepEqual(
      layered.inputs.map((stack) => stack.id),
      ['gtceu:dust', 'gtceu:extract'],
    )
    assert.equal(layered.outputs[0].id, 'gtceu:product')
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('resolves startup constants, source helpers, research builders, and family aliases', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'starline-source-'))
  try {
    const scripts = path.join(root, 'kubejs', 'server_scripts')
    const startup = path.join(root, 'kubejs', 'startup_scripts')
    await mkdir(scripts, { recursive: true })
    await mkdir(startup, { recursive: true })
    await writeFile(path.join(startup, 'voltage.js'), 'global.vha = { lv: GTValues.VHA[GTValues.LV] }')
    await writeFile(
      path.join(scripts, 'recipes.js'),
      `ServerEvents.recipes(event => {
        const crop = { name: 'minecraft:wheat' }
        function seed(value) { return value.seed || value.name }
        event.recipes.gtceu.greenhouse('start:wheat')
          .notConsumable(seed(crop)).itemOutputs('minecraft:wheat')
          .duration(200).EUt(global.vha['lv'])
        const create = event.recipes.create
        create.mixing(Fluid.of('gtceu:goo', 100), ['gtceu:iron_dust']).id('start:goo')
        const researchBuilder = global.researchBuilder
        researchBuilder('assembly_line', 'widget', ['2x gtceu:iron_ingot'],
          ['gtceu:water 100'], ['gtceu:widget'], 100, 64, 128,
          GTValues.VA[GTValues.HV], 'gtceu:research')
      })`,
    )
    const result = await importKubeJs(root, 'test')
    assert.equal(result.recipes.length, 4)
    const wheat = result.recipes.find((recipe) => recipe.gameId === 'start:wheat')
    assert.equal(wheat.eut, 15)
    assert.equal(wheat.catalysts[0].id, 'minecraft:wheat')
    const goo = result.recipes.find((recipe) => recipe.gameId === 'start:goo')
    assert.equal(goo.outputs[0].unit, 'mB')
    const widget = result.recipes.find((recipe) => recipe.gameId === 'start:widget')
    assert.equal(widget.inputs.length, 2)
    assert.equal(widget.eut, 480)
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})

test('includes only selected source branches and preserves NBT and chance review', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'starline-branch-'))
  try {
    const scripts = path.join(root, 'kubejs', 'server_scripts')
    await mkdir(scripts, { recursive: true })
    await writeFile(
      path.join(scripts, 'recipes.js'),
      `ServerEvents.recipes(event => {
        [{ name: 'a', chance: 5000 }, { name: 'b', chance: 18000 }].forEach(mat => {
          const guaranteed = Math.floor(mat.chance / 10000)
          if (guaranteed >= 1) {
            event.recipes.gtceu.autoclave(global.id(mat.name))
              .itemInputs('gtceu:dust').itemOutputs(guaranteed + 'x gtceu:fiber')
              .chancedOutput('gtceu:fiber', mat.chance - guaranteed * 10000, 0)
              .duration(100).EUt(30)
          } else {
            event.recipes.gtceu.autoclave(global.id(mat.name))
              .itemInputs('gtceu:dust').chancedOutput('gtceu:fiber', mat.chance, 1000)
              .duration(100).EUt(30)
          }
        })
        event.recipes.gtceu.assembler('start:nbt')
          .itemInputs('gtceu:dust')
          .itemOutputs(Item.of('kubejs:module', '{Custom:1b}'))
          .duration(100).EUt(30)
      })`,
    )
    const result = await importKubeJs(root, 'test')
    assert.equal(result.recipes.length, 3)
    assert.equal(result.recipes.find((recipe) => recipe.gameId === 'start:a').outputs[0].chance, 0.5)
    assert.equal(result.recipes.find((recipe) => recipe.gameId === 'start:a').outputs[0].chanceBoost, 0.1)
    assert.equal(result.recipes.find((recipe) => recipe.gameId === 'start:b').outputs[0].amount, 1)
    const nbt = result.recipes.find((recipe) => recipe.gameId === 'start:nbt')
    assert.equal(nbt.outputs[0].nbt, '{Custom:1b}')
    assert.ok(nbt.unresolved.some((issue) => issue.includes('NBT')))
  } finally {
    await rm(root, { recursive: true, force: true })
  }
})
