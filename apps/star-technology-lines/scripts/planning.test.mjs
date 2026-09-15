import assert from 'node:assert/strict'
import test from 'node:test'
import { analyzeLine, outputTotals } from '../src/planning.ts'

test('total output separates produced, allocated, and net rates for items and fluids', () => {
  const source = {
    id: 'source',
    duration: 60,
    eut: 16,
    parallel: 1,
    tier: 'LV',
    inputs: [],
    outputs: [
      { id: 'ore', name: 'Raw ore', materialId: 'test:ore', amount: 2, unit: 'items' },
      { id: 'water', name: 'Water', materialId: 'test:water', amount: 100, unit: 'mB' },
    ],
  }
  const processor = {
    id: 'processor',
    duration: 60,
    eut: 16,
    parallel: 1,
    tier: 'LV',
    inputs: [{ id: 'ore-in', name: 'Raw ore', materialId: 'test:ore', amount: 1, unit: 'items' }],
    outputs: [{ id: 'dust', name: 'Dust', materialId: 'test:dust', amount: 1, unit: 'items' }],
  }
  const project = {
    stages: [source, processor],
    links: [{ fromStage: 'source', fromPort: 'ore', toStage: 'processor', toPort: 'ore-in' }],
  }
  const totals = outputTotals(project, analyzeLine(project))
  const processorAnalysis = analyzeLine(project).stages.get('processor')
  assert.equal(processorAnalysis.isBottleneck, true)
  assert.equal(processorAnalysis.inputPotentialPerMinute, 2)
  assert.equal(processorAnalysis.capacityPerMinute, 1)
  assert.equal(processorAnalysis.requiredParallel, 2)
  assert.deepEqual(
    totals.find((output) => output.name === 'Raw ore'),
    {
      name: 'Raw ore',
      unit: 'items',
      produced: 2,
      allocated: 1,
      net: 1,
    },
  )
  assert.deepEqual(
    totals.find((output) => output.name === 'Dust'),
    {
      name: 'Dust',
      unit: 'items',
      produced: 1,
      allocated: 0,
      net: 1,
    },
  )
  assert.equal(totals.find((output) => output.name === 'Water')?.net, 100)
})

test('a machine that can consume its linked supply is not marked as a bottleneck', () => {
  const source = {
    id: 'source',
    duration: 60,
    eut: 16,
    parallel: 1,
    tier: 'LV',
    inputs: [],
    outputs: [{ id: 'ore', name: 'Ore', amount: 2, unit: 'items' }],
  }
  const processor = {
    id: 'processor',
    duration: 60,
    eut: 16,
    parallel: 2,
    tier: 'LV',
    inputs: [{ id: 'ore-in', name: 'Ore', amount: 1, unit: 'items' }],
    outputs: [],
  }
  const analysis = analyzeLine({
    stages: [source, processor],
    links: [{ fromStage: 'source', fromPort: 'ore', toStage: 'processor', toPort: 'ore-in' }],
  }).stages.get('processor')
  assert.equal(analysis.isBottleneck, false)
  assert.equal(analysis.requiredParallel, null)
})
