import voltageValues from '../scripts/sources/voltage-values.json' with { type: 'json' }
import type { CatalogRecipe, RecipeStack } from './catalog'
import type { Port, Project, Stage } from './model'

export const VOLTAGE_TIERS = Object.keys(voltageValues.tiers)
const VOLTAGES = voltageValues.values.V

const tierIndex = (tier: string) => VOLTAGE_TIERS.indexOf(tier)
const recipeTier = (eut: number) => VOLTAGES.findIndex((voltage) => eut <= voltage)

export const minimumTier = (eut: number | null) => {
  if (eut == null || eut < 0) return 'LV'
  return VOLTAGE_TIERS[Math.max(1, recipeTier(eut))] ?? 'LV'
}

export const recipeTiming = (durationTicks: number | null, eut: number | null, tier: string) => {
  if (durationTicks == null || durationTicks <= 0 || eut == null || eut < 0)
    return { durationSeconds: null, eut: null, overclocks: 0, runnable: false }
  const baseTier = recipeTier(eut)
  const selectedTier = tierIndex(tier)
  if (baseTier < 0 || selectedTier < baseTier)
    return { durationSeconds: null, eut: null, overclocks: 0, runnable: false }

  let ticks = durationTicks
  let power = eut
  let overclocks = 0
  const allowed = Math.max(0, selectedTier - baseTier - (baseTier === 0 ? 1 : 0))
  for (let i = 0; i < allowed; i++) {
    if (ticks / 2 < 1 || power * 4 > VOLTAGES[selectedTier]) break
    ticks /= 2
    power *= 4
    overclocks++
  }
  return { durationSeconds: Math.ceil(ticks) / 20, eut: power, overclocks, runnable: true }
}

export const stageTiming = (stage: Stage) => {
  if (!stage.recipeRef)
    return {
      durationSeconds: stage.duration,
      eut: stage.eut,
      overclocks: 0,
      runnable: stage.duration != null && stage.duration > 0,
    }
  return recipeTiming(stage.duration == null ? null : stage.duration * 20, stage.eut, stage.tier)
}

const chanceAtTier = (
  chance: number | undefined,
  boost: number | undefined,
  eut: number | null,
  tier: string,
) => {
  if (chance == null) return 1
  const baseTier = eut == null ? -1 : recipeTier(eut)
  const selectedTier = tierIndex(tier)
  const difference =
    baseTier < 0 || selectedTier < 0 ? 0 : Math.max(0, selectedTier - baseTier - (baseTier === 0 ? 1 : 0))
  return Math.max(0, Math.min(1, chance + (boost ?? 0) * difference))
}

export const outputChance = (port: Port, stage: Stage) =>
  chanceAtTier(port.chance, port.chanceBoost, stage.eut, stage.tier)

export const stackChance = (stack: RecipeStack, recipe: CatalogRecipe, tier: string) =>
  chanceAtTier(stack.chance ?? undefined, stack.chanceBoost, recipe.eut, tier)

export const machinesForInput = (
  recipe: CatalogRecipe,
  input: RecipeStack,
  incomingPerMinute: number,
  tier: string,
) => {
  const timing = recipeTiming(recipe.durationTicks, recipe.eut, tier)
  if (!timing.runnable || timing.durationSeconds == null || input.amount <= 0) return null
  return Math.max(1, Math.ceil((incomingPerMinute * timing.durationSeconds) / (input.amount * 60) - 1e-9))
}

export type StageAnalysis = {
  runsPerMinute: number
  capacityPerMinute: number
  timing: ReturnType<typeof stageTiming>
  outputs: Map<string, number>
  externalInputs: Map<string, number>
}

export type LineAnalysis = {
  stages: Map<string, StageAnalysis>
  available: Map<string, number>
  warnings: string[]
}

export const analyzeLine = (project: Project): LineAnalysis => {
  const stages = new Map<string, StageAnalysis>()
  const available = new Map<string, number>()
  const warnings: string[] = []
  const byId = new Map(project.stages.map((stage) => [stage.id, stage]))
  const indegree = new Map(project.stages.map((stage) => [stage.id, 0]))
  for (const link of project.links) {
    if (byId.has(link.fromStage) && byId.has(link.toStage))
      indegree.set(link.toStage, (indegree.get(link.toStage) ?? 0) + 1)
  }
  const queue = project.stages.filter((stage) => indegree.get(stage.id) === 0)

  for (let index = 0; index < queue.length; index++) {
    const stage = queue[index]
    const timing = stageTiming(stage)
    const capacityPerMinute =
      timing.runnable && timing.durationSeconds != null && timing.durationSeconds > 0
        ? (Math.max(1, stage.parallel) * 60) / timing.durationSeconds
        : 0
    let runsPerMinute = capacityPerMinute
    const externalInputs = new Map<string, number>()
    for (const input of stage.inputs) {
      const links = project.links.filter((link) => link.toStage === stage.id && link.toPort === input.id)
      if (links.length && input.amount > 0) {
        const supplied = links.reduce((sum, link) => sum + (available.get(link.fromPort) ?? 0), 0)
        runsPerMinute = Math.min(runsPerMinute, supplied / input.amount)
      }
    }
    for (const input of stage.inputs) {
      const links = project.links.filter((link) => link.toStage === stage.id && link.toPort === input.id)
      const demand = runsPerMinute * input.amount
      if (!links.length) {
        externalInputs.set(input.id, demand)
        continue
      }
      let remaining = demand
      for (const link of links) {
        const offered = available.get(link.fromPort) ?? 0
        const used = Math.min(offered, remaining)
        available.set(link.fromPort, Math.max(0, offered - used))
        remaining -= used
      }
    }
    const outputs = new Map<string, number>()
    for (const output of stage.outputs) {
      const rate = runsPerMinute * output.amount * outputChance(output, stage)
      outputs.set(output.id, rate)
      available.set(output.id, rate)
    }
    stages.set(stage.id, { runsPerMinute, capacityPerMinute, timing, outputs, externalInputs })
    for (const link of project.links.filter((link) => link.fromStage === stage.id)) {
      const remaining = (indegree.get(link.toStage) ?? 0) - 1
      indegree.set(link.toStage, remaining)
      if (remaining === 0) {
        const next = byId.get(link.toStage)
        if (next) queue.push(next)
      }
    }
  }
  if (stages.size !== project.stages.length)
    warnings.push('A cycle in this line prevents downstream rate calculations.')
  return { stages, available, warnings }
}

export const formatPerMinute = (rate: number, unit: Port['unit']) =>
  `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(rate)} ${unit}/min`

export const netOutputs = (project: Project, analysis: LineAnalysis) => {
  const totals = new Map<string, { name: string; unit: Port['unit']; rate: number }>()
  for (const stage of project.stages) {
    for (const output of stage.outputs) {
      const remaining = analysis.available.get(output.id) ?? 0
      if (remaining <= 1e-9) continue
      const key = `${output.materialId ?? output.name}|${output.unit}`
      const current = totals.get(key)
      totals.set(key, {
        name: output.name,
        unit: output.unit,
        rate: (current?.rate ?? 0) + remaining,
      })
    }
  }
  return [...totals.values()].sort((a, b) => b.rate - a.rate)
}
