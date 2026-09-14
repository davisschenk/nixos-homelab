export type Unit = 'items' | 'mB'

export type Port = {
  id: string
  name: string
  amount: number
  unit: Unit
  materialId?: string
}

export type Stage = {
  id: string
  name: string
  machine: string
  tier: string
  duration: number | null
  eut: number | null
  parallel: number
  x: number
  y: number
  inputs: Port[]
  outputs: Port[]
  notes: string
  recipeRef?: {
    key: string
    sourceId: string
    sourcePath: string
    sourceLine: number
    gameId: string | null
    unresolved: string[]
    reviewRequired: boolean
    modified?: boolean
  }
}

export type Link = {
  id: string
  fromStage: string
  fromPort: string
  toStage: string
  toPort: string
}

export type Project = {
  id: string
  name: string
  description: string
  stages: Stage[]
  links: Link[]
  updatedAt: number
}

export type Workspace = {
  projects: Project[]
  activeId: string
}

export const newId = () => crypto.randomUUID()

export const createStage = (x = 400, y = 240): Stage => ({
  id: newId(),
  name: 'New process',
  machine: 'Machine name',
  tier: 'LV',
  duration: 10,
  eut: 32,
  parallel: 1,
  x,
  y,
  inputs: [{ id: newId(), name: 'Input', amount: 1, unit: 'items' }],
  outputs: [{ id: newId(), name: 'Output', amount: 1, unit: 'items' }],
  notes: '',
})

export const createProject = (name = 'Untitled line'): Project => ({
  id: newId(),
  name,
  description: '',
  stages: [],
  links: [],
  updatedAt: Date.now(),
})

const exampleProject = (): Project => {
  const source = createStage(130, 280)
  Object.assign(source, {
    name: 'Prepare ore',
    machine: 'Macerator',
    tier: 'LV',
    duration: 12,
    eut: 16,
    inputs: [{ id: newId(), name: 'Raw ore', amount: 1, unit: 'items' }],
    outputs: [{ id: newId(), name: 'Crushed ore', amount: 2, unit: 'items' }],
    notes: 'Illustrative values. Replace these with the recipe in your pack version.',
  })
  const wash = createStage(540, 280)
  Object.assign(wash, {
    name: 'Wash crushed ore',
    machine: 'Ore Washer',
    tier: 'LV',
    duration: 16,
    eut: 24,
    inputs: [
      { id: newId(), name: 'Crushed ore', amount: 2, unit: 'items' },
      { id: newId(), name: 'Water', amount: 1000, unit: 'mB' },
    ],
    outputs: [{ id: newId(), name: 'Purified ore', amount: 2, unit: 'items' }],
    notes: '',
  })
  const finish = createStage(950, 280)
  Object.assign(finish, {
    name: 'Refine output',
    machine: 'Centrifuge',
    tier: 'MV',
    duration: 20,
    eut: 64,
    inputs: [{ id: newId(), name: 'Purified ore', amount: 2, unit: 'items' }],
    outputs: [{ id: newId(), name: 'Refined material', amount: 1, unit: 'items' }],
    notes: '',
  })
  return {
    id: newId(),
    name: 'Ore processing example',
    description: 'An editable example of a three-stage line. Recipe quantities are illustrative.',
    stages: [source, wash, finish],
    links: [
      {
        id: newId(),
        fromStage: source.id,
        fromPort: source.outputs[0].id,
        toStage: wash.id,
        toPort: wash.inputs[0].id,
      },
      {
        id: newId(),
        fromStage: wash.id,
        fromPort: wash.outputs[0].id,
        toStage: finish.id,
        toPort: finish.inputs[0].id,
      },
    ],
    updatedAt: Date.now(),
  }
}

export const defaultWorkspace = (): Workspace => {
  const project = exampleProject()
  return { projects: [project], activeId: project.id }
}

const isPort = (value: unknown): value is Port => {
  if (!value || typeof value !== 'object') return false
  const port = value as Record<string, unknown>
  return (
    typeof port.id === 'string' &&
    typeof port.name === 'string' &&
    typeof port.amount === 'number' &&
    Number.isFinite(port.amount) &&
    (port.unit === 'items' || port.unit === 'mB') &&
    (port.materialId === undefined || typeof port.materialId === 'string')
  )
}

export const isProject = (value: unknown): value is Project => {
  if (!value || typeof value !== 'object') return false
  const project = value as Record<string, unknown>
  if (
    typeof project.id !== 'string' ||
    typeof project.name !== 'string' ||
    typeof project.description !== 'string' ||
    !Array.isArray(project.stages) ||
    !Array.isArray(project.links)
  )
    return false
  return (
    project.stages.every((entry: unknown) => {
      if (!entry || typeof entry !== 'object') return false
      const stage = entry as Record<string, unknown>
      return (
        typeof stage.id === 'string' &&
        typeof stage.name === 'string' &&
        typeof stage.machine === 'string' &&
        typeof stage.tier === 'string' &&
        (typeof stage.duration === 'number' || stage.duration === null) &&
        (typeof stage.eut === 'number' || stage.eut === null) &&
        typeof stage.parallel === 'number' &&
        typeof stage.x === 'number' &&
        typeof stage.y === 'number' &&
        typeof stage.notes === 'string' &&
        Array.isArray(stage.inputs) &&
        stage.inputs.every(isPort) &&
        Array.isArray(stage.outputs) &&
        stage.outputs.every(isPort)
      )
    }) &&
    project.links.every((entry: unknown) => {
      if (!entry || typeof entry !== 'object') return false
      const link = entry as Record<string, unknown>
      return ['id', 'fromStage', 'fromPort', 'toStage', 'toPort'].every(
        (key) => typeof link[key] === 'string',
      )
    })
  )
}

export const loadWorkspace = (): Workspace => {
  try {
    const raw = localStorage.getItem('starline-workspace-v1')
    if (!raw) return defaultWorkspace()
    const data: unknown = JSON.parse(raw)
    if (!data || typeof data !== 'object') return defaultWorkspace()
    const workspace = data as Record<string, unknown>
    if (
      !Array.isArray(workspace.projects) ||
      !workspace.projects.length ||
      !workspace.projects.every(isProject) ||
      typeof workspace.activeId !== 'string'
    )
      return defaultWorkspace()
    const projects = workspace.projects as Project[]
    return {
      projects,
      activeId: projects.some((p) => p.id === workspace.activeId) ? workspace.activeId : projects[0].id,
    }
  } catch {
    return defaultWorkspace()
  }
}

export const formatRate = (port: Port, stage: Stage) => {
  if (stage.duration == null || stage.duration <= 0) return 'Rate unavailable'
  const perMinute = (port.amount * Math.max(1, stage.parallel) * 60) / stage.duration
  return `${new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 }).format(perMinute)} ${port.unit}/min`
}
