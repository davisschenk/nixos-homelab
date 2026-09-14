import assert from 'node:assert/strict'
import test from 'node:test'
import { arrangeStages, canvasSize, stageHeight } from '../src/layout.ts'

const stage = (id, outputs = 1) => ({
  id,
  x: 400,
  y: 200,
  inputs: [{ id: `${id}-in` }],
  outputs: Array.from({ length: outputs }, (_, index) => ({ id: `${id}-out-${index}` })),
})

test('arranges branched flows in columns without overlapping unequal nodes', () => {
  const project = {
    stages: [stage('source', 8), stage('ore'), stage('dust'), stage('sieve'), stage('loose')],
    links: [
      { fromStage: 'source', toStage: 'ore' },
      { fromStage: 'ore', toStage: 'dust' },
      { fromStage: 'source', toStage: 'sieve' },
    ],
  }
  const arranged = arrangeStages(project)
  const byId = Object.fromEntries(arranged.stages.map((item) => [item.id, item]))
  assert.ok(byId.source.x < byId.ore.x && byId.ore.x < byId.dust.x)
  assert.equal(byId.sieve.x, byId.ore.x)
  for (const first of arranged.stages)
    for (const second of arranged.stages) {
      if (first.id === second.id || first.x !== second.x) continue
      assert.ok(
        first.y + stageHeight(first) + 50 <= second.y || second.y + stageHeight(second) + 50 <= first.y,
      )
    }
  assert.ok(canvasSize(arranged).height >= byId.source.y + stageHeight(byId.source))
})

test('cycles do not trap the layout pass', () => {
  const project = {
    stages: [stage('a'), stage('b')],
    links: [
      { fromStage: 'a', toStage: 'b' },
      { fromStage: 'b', toStage: 'a' },
    ],
  }
  const arranged = arrangeStages(project)
  assert.equal(arranged.stages.length, 2)
  assert.notEqual(arranged.stages[0].x, arranged.stages[1].x)
})
