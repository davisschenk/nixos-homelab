import assert from 'node:assert/strict'
import test from 'node:test'
import { mergeCatalog } from './merge-catalog.mjs'

const metadata = { generatedAt: '2026-01-01', packVersion: 'test', packMode: 'default' }
const source = (id) => ({ id, name: id, kind: 'json', url: '', commit: '', license: '', scope: '' })
const recipe = (key, sourceId) => ({
  key,
  sourceId,
  sourcePath: 'recipe.json',
  sourceLine: 1,
  gameId: key,
  family: 'gtceu',
  machine: 'macerator',
  inputs: [],
  outputs: [],
  catalysts: [],
  durationTicks: null,
  eut: null,
  circuit: null,
  unresolved: [],
})

test('merges independently sourced recipes and tag memberships', () => {
  const catalog = mergeCatalog(metadata, [
    {
      sources: [source('one')],
      recipes: [recipe('one:ore', 'one')],
      tags: { 'items|forge:ores': ['start:ore'] },
      fileCount: 1,
    },
    {
      sources: [source('two')],
      recipes: [recipe('two:ore', 'two')],
      tags: { 'items|forge:ores': ['start:ore'] },
      fileCount: 2,
    },
  ])
  assert.equal(catalog.recipes.length, 2)
  assert.equal(catalog.fileCount, 3)
  assert.deepEqual(catalog.tags['items|forge:ores'], ['start:ore'])
})

test('rejects duplicate identities and conflicting tag memberships', () => {
  assert.throws(
    () =>
      mergeCatalog(metadata, [
        { sources: [source('one')], recipes: [recipe('one:ore', 'one')] },
        { sources: [source('two')], recipes: [recipe('one:ore', 'two')] },
      ]),
    /Duplicate recipe key/,
  )
  assert.throws(
    () =>
      mergeCatalog(metadata, [
        { sources: [source('one')], tags: { 'items|forge:ores': ['start:ore'] } },
        { sources: [source('two')], tags: { 'items|forge:ores': ['other:ore'] } },
      ]),
    /Conflicting tag members/,
  )
})
