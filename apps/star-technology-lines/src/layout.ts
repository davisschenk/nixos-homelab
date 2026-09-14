import type { Project, Stage } from './model'

export const NODE_WIDTH = 300
export const stageHeight = (stage: Stage) => 168 + 36 * Math.max(1, stage.inputs.length, stage.outputs.length)

export const canvasSize = (project: Project) => ({
  width: Math.max(2300, ...project.stages.map((stage) => stage.x + NODE_WIDTH + 100)),
  height: Math.max(1500, ...project.stages.map((stage) => stage.y + stageHeight(stage) + 100)),
})

export const arrangeStages = (project: Project): Project => {
  const byId = new Map(project.stages.map((stage) => [stage.id, stage]))
  const order = new Map(project.stages.map((stage, index) => [stage.id, index]))
  const parents = new Map(project.stages.map((stage) => [stage.id, [] as string[]]))
  const children = new Map(project.stages.map((stage) => [stage.id, [] as string[]]))
  const indegree = new Map(project.stages.map((stage) => [stage.id, 0]))
  for (const link of project.links) {
    if (!byId.has(link.fromStage) || !byId.has(link.toStage)) continue
    parents.get(link.toStage)?.push(link.fromStage)
    children.get(link.fromStage)?.push(link.toStage)
    indegree.set(link.toStage, (indegree.get(link.toStage) ?? 0) + 1)
  }

  const queue = project.stages.filter((stage) => indegree.get(stage.id) === 0).map((stage) => stage.id)
  const depth = new Map(queue.map((id) => [id, 0]))
  for (let index = 0; index < queue.length; index++) {
    const id = queue[index]
    for (const child of children.get(id) ?? []) {
      depth.set(child, Math.max(depth.get(child) ?? 0, (depth.get(id) ?? 0) + 1))
      indegree.set(child, (indegree.get(child) ?? 0) - 1)
      if (indegree.get(child) === 0) queue.push(child)
    }
  }
  for (const stage of project.stages) {
    if (!depth.has(stage.id)) depth.set(stage.id, 1 + Math.max(0, ...depth.values()))
  }

  const columns = new Map<number, string[]>()
  for (const stage of project.stages) {
    const column = depth.get(stage.id) ?? 0
    columns.set(column, [...(columns.get(column) ?? []), stage.id])
  }
  const positions = new Map<string, { x: number; y: number }>()
  for (const column of [...columns.keys()].sort((a, b) => a - b)) {
    const ids = columns.get(column) ?? []
    ids.sort((a, b) => {
      const parentY = (id: string) => {
        const placed = (parents.get(id) ?? [])
          .map((parent) => positions.get(parent)?.y)
          .filter((y) => y != null)
        return placed.length ? placed.reduce((sum, y) => sum + y, 0) / placed.length : Infinity
      }
      return parentY(a) - parentY(b) || (order.get(a) ?? 0) - (order.get(b) ?? 0)
    })
    let y = 80
    for (const id of ids) {
      const stage = byId.get(id)!
      positions.set(id, { x: 80 + column * 410, y })
      y += stageHeight(stage) + 54
    }
  }
  return { ...project, stages: project.stages.map((stage) => ({ ...stage, ...positions.get(stage.id) })) }
}
