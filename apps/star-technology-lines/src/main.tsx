import React, { useEffect, useMemo, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import {
  createProject,
  createStage,
  isProject,
  loadWorkspace,
  newId,
  type Link,
  type Port,
  type Project,
  type Stage,
  type Workspace,
} from './model'
import {
  displayName,
  displayStack,
  inputAcceptsPort,
  inputMaterials,
  recipeIsCalculable,
  recipeIsReady,
  searchRecipes,
  sourceLink,
  stageFromRecipe,
  type Catalog,
  type CatalogRecipe,
} from './catalog'
import {
  analyzeLine,
  formatPerMinute,
  machinesForInput,
  minimumTier,
  netOutputs,
  outputTotals,
  outputChance,
  stageTiming,
  stackChance,
  VOLTAGE_TIERS,
  type StageAnalysis,
} from './planning'
import { arrangeStages, canvasSize, NODE_WIDTH, stageHeight } from './layout'
import './styles.css'

const PORT_OFFSET = 150
const PORT_STEP = 36

const SOURCE_MACHINES = new Set(['void_excavation', 'mechanical_sieve', 'large_sieve', 'rock_filtrator'])
const isSourceMachine = (stage: Stage) =>
  stage.recipeRef != null &&
  [...SOURCE_MACHINES].some(
    (machine) =>
      stage.recipeRef?.key.includes(`/${machine}/`) || stage.recipeRef?.key.includes(`:${machine}:`),
  )
const sourceMachineName = (machine: string) =>
  machine === 'void_excavation' ? 'Void Ore Extractor' : displayName(machine)
const sourceTitle = (recipe: CatalogRecipe) =>
  `${sourceMachineName(recipe.machine)} · ${displayName(recipe.gameId?.split('/').pop() ?? recipe.machine)}`
const isRawOre = (port: Port) => port.unit === 'items' && /:raw_[^/]+$/.test(port.materialId ?? '')

const nextTier = (sourceTier: string, recipeEut: number | null) => {
  const source = VOLTAGE_TIERS.indexOf(sourceTier)
  const minimum = VOLTAGE_TIERS.indexOf(minimumTier(recipeEut))
  return VOLTAGE_TIERS[Math.max(1, source, minimum)]
}

type Pending = { stageId: string; portId: string } | null
type Drag = { id: string; startX: number; startY: number; nodeX: number; nodeY: number } | null

function Icon({ name, size = 18 }: { name: string; size?: number }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth: 1.8,
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
  }
  const paths: Record<string, React.ReactNode> = {
    plus: <path d="M12 5v14M5 12h14" />,
    grid: (
      <>
        <rect x="3" y="3" width="7" height="7" rx="1" />
        <rect x="14" y="3" width="7" height="7" rx="1" />
        <rect x="3" y="14" width="7" height="7" rx="1" />
        <rect x="14" y="14" width="7" height="7" rx="1" />
      </>
    ),
    download: (
      <>
        <path d="M12 3v12m-4-4 4 4 4-4" />
        <path d="M4 17v3h16v-3" />
      </>
    ),
    upload: (
      <>
        <path d="M12 16V4m-4 4 4-4 4 4" />
        <path d="M4 17v3h16v-3" />
      </>
    ),
    trash: (
      <>
        <path d="M4 7h16M9 7V4h6v3m-9 0 1 13h10l1-13M10 11v5m4-5v5" />
      </>
    ),
    copy: (
      <>
        <rect x="8" y="8" width="12" height="12" rx="2" />
        <path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" />
      </>
    ),
    bolt: <path d="m13 2-9 11h7l-1 9 10-12h-7V2Z" />,
    clock: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 2" />
      </>
    ),
    link: (
      <>
        <path d="M10 13a5 5 0 0 0 7 .5l3-3a5 5 0 0 0-7-7l-2 2" />
        <path d="M14 11a5 5 0 0 0-7-.5l-3 3a5 5 0 0 0 7 7l2-2" />
      </>
    ),
    layers: (
      <>
        <path d="m12 2 9 5-9 5-9-5 9-5Z" />
        <path d="m3 12 9 5 9-5M3 17l9 5 9-5" />
      </>
    ),
    chevron: <path d="m9 6 6 6-6 6" />,
    close: <path d="M5 5l14 14M19 5 5 19" />,
  }
  return (
    <svg {...common} aria-hidden="true">
      {paths[name]}
    </svg>
  )
}

function App() {
  const [workspace, setWorkspace] = useState<Workspace>(loadWorkspace)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [selectedLinkId, setSelectedLinkId] = useState<string | null>(null)
  const [selectedOutput, setSelectedOutput] = useState<Pending>(null)
  const [view, setView] = useState<'canvas' | 'totals'>('canvas')
  const [pending, setPending] = useState<Pending>(null)
  const [zoom, setZoom] = useState(1)
  const [notice, setNotice] = useState('')
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [catalogError, setCatalogError] = useState('')
  const [catalogOpen, setCatalogOpen] = useState(false)
  const [catalogQuery, setCatalogQuery] = useState('')
  const [includePartial, setIncludePartial] = useState(false)
  const [sourceKey, setSourceKey] = useState('')
  const fileRef = useRef<HTMLInputElement>(null)
  const viewportRef = useRef<HTMLDivElement>(null)
  const inspectorRef = useRef<HTMLElement>(null)
  const dragRef = useRef<Drag>(null)
  const project = workspace.projects.find((p) => p.id === workspace.activeId) ?? workspace.projects[0]
  const selectedStage = project.stages.find((s) => s.id === selectedId)
  const selectedLink = project.links.find((l) => l.id === selectedLinkId)
  const outputStage = project.stages.find((stage) => stage.id === selectedOutput?.stageId)
  const outputPort = outputStage?.outputs.find((port) => port.id === selectedOutput?.portId)
  const analysis = analyzeLine(project)
  const finalOutputs = netOutputs(project, analysis)
  const totals = outputTotals(project, analysis)
  const dimensions = canvasSize(project)
  const sourceRecipes = useMemo(
    () =>
      catalog?.recipes.filter(
        (recipe) => SOURCE_MACHINES.has(recipe.machine) && recipeIsCalculable(recipe),
      ) ?? [],
    [catalog],
  )
  const sourceRecipe =
    sourceRecipes.find((recipe) => recipe.key === sourceKey) ??
    sourceRecipes.find((recipe) => recipe.machine === 'void_excavation') ??
    sourceRecipes[0]
  const sourceStages = project.stages.filter(isSourceMachine)
  const outputRecipes = useMemo(() => {
    const index = new Map<string, CatalogRecipe[]>()
    if (!catalog) return index
    for (const recipe of catalog.recipes) {
      if (!recipeIsCalculable(recipe)) continue
      for (const input of recipe.inputs) {
        for (const material of inputMaterials(catalog, input)) {
          const key = `${material}|${input.unit}`
          const list = index.get(key) ?? []
          list.push(recipe)
          index.set(key, list)
        }
      }
    }
    for (const [key, list] of index)
      list.sort(
        (a, b) =>
          (/:raw_[^/]+\|items$/.test(key)
            ? Number(b.machine === 'macerator') - Number(a.machine === 'macerator')
            : 0) ||
          a.inputs.length - b.inputs.length ||
          (a.durationTicks ?? Infinity) - (b.durationTicks ?? Infinity) ||
          a.machine.localeCompare(b.machine),
      )
    return index
  }, [catalog])
  const recommendedOrePaths = sourceStages.flatMap((stage) =>
    stage.outputs.flatMap((port) => {
      if (!isRawOre(port) || (analysis.available.get(port.id) ?? 0) <= 1e-9) return []
      const recipe = outputRecipes
        .get(`${port.materialId}|${port.unit}`)
        ?.find((item) => item.machine === 'macerator')
      return recipe ? [{ stage, port, recipe }] : []
    }),
  )

  useEffect(() => {
    localStorage.setItem('starline-workspace-v1', JSON.stringify(workspace))
  }, [workspace])

  useEffect(() => {
    fetch(`${import.meta.env.BASE_URL}catalog.json`)
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json()
      })
      .then((data: Catalog) => {
        if (data.schemaVersion !== 1 || !Array.isArray(data.recipes) || !Array.isArray(data.sources))
          throw new Error('Unsupported catalog')
        setCatalog(data)
      })
      .catch((error) => setCatalogError(error instanceof Error ? error.message : 'Catalog unavailable'))
  }, [])

  useEffect(() => {
    if (!notice) return
    const timer = window.setTimeout(() => setNotice(''), 3500)
    return () => window.clearTimeout(timer)
  }, [notice])

  useEffect(() => {
    if (viewportRef.current) {
      viewportRef.current.scrollLeft = 80
      viewportRef.current.scrollTop = 170
    }
    setSelectedOutput(null)
  }, [workspace.activeId])

  const updateProject = (change: (current: Project) => Project) => {
    setWorkspace((current) => ({
      ...current,
      projects: current.projects.map((p) =>
        p.id === current.activeId ? { ...change(p), updatedAt: Date.now() } : p,
      ),
    }))
  }

  const updateStage = (id: string, change: (stage: Stage) => Stage) => {
    updateProject((p) => ({ ...p, stages: p.stages.map((s) => (s.id === id ? change(s) : s)) }))
  }

  const addStage = () => {
    const viewport = viewportRef.current
    const x = viewport
      ? Math.max(35, Math.round((viewport.scrollLeft + viewport.clientWidth / 2) / zoom - NODE_WIDTH / 2))
      : 400
    const y = viewport
      ? Math.max(35, Math.round((viewport.scrollTop + viewport.clientHeight / 2) / zoom - 100))
      : 240
    const stage = createStage(x, y)
    updateProject((p) => ({ ...p, stages: [...p.stages, stage] }))
    setSelectedId(stage.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
    setPending(null)
  }

  const addCatalogRecipe = (recipe: CatalogRecipe) => {
    const viewport = viewportRef.current
    const x = viewport
      ? Math.max(35, Math.round((viewport.scrollLeft + viewport.clientWidth / 2) / zoom - NODE_WIDTH / 2))
      : 400
    const y = viewport
      ? Math.max(35, Math.round((viewport.scrollTop + viewport.clientHeight / 2) / zoom - 100))
      : 240
    const stage = stageFromRecipe(recipe, x, y)
    updateProject((p) => ({ ...p, stages: [...p.stages, stage] }))
    setSelectedId(stage.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
    setCatalogOpen(false)
    setNotice(recipeIsReady(recipe) ? 'Recipe added to line' : 'Added with fields to review against source')
  }

  const makeSource = (x: number, y: number) => {
    if (!sourceRecipe) return null
    return {
      ...stageFromRecipe(sourceRecipe, x, y),
      name: sourceTitle(sourceRecipe),
      machine: sourceMachineName(sourceRecipe.machine),
      tier: minimumTier(sourceRecipe.eut),
      parallel: 1,
    }
  }

  const startSourceLine = () => {
    const source = makeSource(130, 220)
    if (!source) return
    const next = createProject(source.name)
    next.stages = [source]
    setWorkspace((current) => ({ projects: [...current.projects, next], activeId: next.id }))
    setSelectedId(source.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
    setPending(null)
  }

  const addSourceHere = () => {
    const source = makeSource(
      130,
      Math.max(220, ...sourceStages.map((stage) => stage.y + stageHeight(stage) + 80)),
    )
    if (!source) return
    updateProject((current) => ({ ...current, stages: [...current.stages, source] }))
    setSelectedId(source.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
  }

  const addFromOutput = (source: Stage, output: Port, recipe: CatalogRecipe | null) => {
    const incomingRate = analysis.available.get(output.id) ?? 0
    if (incomingRate <= 0) {
      setNotice('No unallocated output is available for another stage')
      return
    }
    const input = recipe?.inputs.find((stack) => catalog && inputAcceptsPort(catalog, stack, output))
    if (recipe && !input) return
    const tier = recipe ? nextTier(source.tier, recipe.eut) : source.tier
    const machines = recipe && input ? machinesForInput(recipe, input, incomingRate, tier) : 1
    const x = source.x + 410
    const y = source.y + 22 + source.outputs.indexOf(output) * 130
    const stage: Stage = recipe
      ? { ...stageFromRecipe(recipe, x, y), tier, parallel: machines ?? 1 }
      : {
          ...createStage(x, y),
          name: `Process ${output.name}`,
          machine: 'Choose a machine',
          tier,
          duration: null,
          eut: null,
          inputs: [
            {
              id: newId(),
              name: output.name,
              amount: 1,
              unit: output.unit,
              materialId: output.materialId,
            },
          ],
          outputs: [],
          notes: 'Add the in-game recipe values, then set the machine count to match the incoming rate.',
        }
    const target = recipe
      ? stage.inputs[recipe.inputs.indexOf(input!)]
      : stage.inputs.find((port) => port.materialId === output.materialId && port.unit === output.unit)
    if (!target) return
    const link: Link = {
      id: newId(),
      fromStage: source.id,
      fromPort: output.id,
      toStage: stage.id,
      toPort: target.id,
    }
    updateProject((current) => ({
      ...current,
      stages: [...current.stages, stage],
      links: [...current.links, link],
    }))
    setSelectedId(stage.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
    setNotice(
      recipe
        ? `Added ${stage.machine} · ${stage.parallel} machine${stage.parallel === 1 ? '' : 's'}`
        : 'Custom stage linked; enter its recipe values',
    )
  }

  const removeStage = (id: string) => {
    updateProject((p) => ({
      ...p,
      stages: p.stages.filter((s) => s.id !== id),
      links: p.links.filter((l) => l.fromStage !== id && l.toStage !== id),
    }))
    setSelectedId(null)
    setPending(null)
  }

  const duplicateStage = (stage: Stage) => {
    const clonePort = (port: Port) => ({ ...port, id: newId() })
    const clone: Stage = {
      ...stage,
      id: newId(),
      name: `${stage.name} copy`,
      x: stage.x + 80,
      y: stage.y + 80,
      inputs: stage.inputs.map(clonePort),
      outputs: stage.outputs.map(clonePort),
      recipeRef: stage.recipeRef ? { ...stage.recipeRef, modified: true } : undefined,
    }
    updateProject((p) => ({ ...p, stages: [...p.stages, clone] }))
    setSelectedId(clone.id)
    setSelectedOutput(null)
  }

  const handleInputPort = (stage: Stage, port: Port) => {
    if (!pending) {
      setNotice('Select an output port first')
      return
    }
    const source = project.stages.find((s) => s.id === pending.stageId)
    const sourcePort = source?.outputs.find((p) => p.id === pending.portId)
    if (!source || !sourcePort || source.id === stage.id) {
      setPending(null)
      return
    }
    if (sourcePort.unit !== port.unit) {
      setNotice('Connect items to items or fluids to fluids')
      return
    }
    if (
      sourcePort.materialId &&
      port.materialId &&
      sourcePort.materialId !== port.materialId &&
      (!catalog ||
        !inputAcceptsPort(
          catalog,
          { id: port.materialId, amount: port.amount, unit: port.unit, chance: null },
          sourcePort,
        ))
    ) {
      setNotice('These ports contain different materials')
      return
    }
    if (project.links.some((l) => l.fromPort === sourcePort.id && l.toPort === port.id)) {
      setPending(null)
      return
    }
    const link: Link = {
      id: newId(),
      fromStage: source.id,
      fromPort: sourcePort.id,
      toStage: stage.id,
      toPort: port.id,
    }
    updateProject((p) => ({ ...p, links: [...p.links, link] }))
    setPending(null)
    setNotice(`${sourcePort.name} connected to ${port.name}`)
  }

  const openOutput = (stage: Stage, port: Port) => {
    setSelectedOutput({ stageId: stage.id, portId: port.id })
    setSelectedId(null)
    setSelectedLinkId(null)
    setView('canvas')
    if (window.innerWidth <= 900)
      requestAnimationFrame(() =>
        inspectorRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' }),
      )
  }

  const autoArrange = () => {
    updateProject(arrangeStages)
    setNotice('Stages arranged by material flow')
    if (viewportRef.current) {
      viewportRef.current.scrollLeft = 0
      viewportRef.current.scrollTop = 0
    }
  }

  const startDrag = (event: React.PointerEvent<HTMLDivElement>, stage: Stage) => {
    if (event.button !== 0) return
    event.currentTarget.setPointerCapture(event.pointerId)
    dragRef.current = {
      id: stage.id,
      startX: event.clientX,
      startY: event.clientY,
      nodeX: stage.x,
      nodeY: stage.y,
    }
    setSelectedId(stage.id)
    setSelectedOutput(null)
    setSelectedLinkId(null)
  }

  const moveDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current
    if (!drag) return
    const x = Math.max(
      8,
      Math.min(
        dimensions.width - NODE_WIDTH - 8,
        Math.round(drag.nodeX + (event.clientX - drag.startX) / zoom),
      ),
    )
    const y = Math.max(
      8,
      Math.min(
        dimensions.height - stageHeight(project.stages.find((s) => s.id === drag.id)!) - 8,
        Math.round(drag.nodeY + (event.clientY - drag.startY) / zoom),
      ),
    )
    updateStage(drag.id, (s) => ({ ...s, x, y }))
  }

  const createLine = () => {
    const next = createProject(`New processing line ${workspace.projects.length + 1}`)
    setWorkspace((current) => ({ projects: [...current.projects, next], activeId: next.id }))
    setSelectedId(null)
    setSelectedLinkId(null)
    setPending(null)
  }

  const exportLine = () => {
    const file = new Blob([JSON.stringify(project, null, 2)], { type: 'application/json' })
    const url = URL.createObjectURL(file)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `${
      project.name
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-|-$/g, '') || 'starline'
    }.json`
    anchor.click()
    URL.revokeObjectURL(url)
    setNotice('Line exported as JSON')
  }

  const importLine = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return
    try {
      const data: unknown = JSON.parse(await file.text())
      if (!isProject(data)) throw new Error('Invalid line file')
      const imported = { ...data, id: newId(), updatedAt: Date.now() }
      setWorkspace((current) => ({ projects: [...current.projects, imported], activeId: imported.id }))
      setSelectedId(null)
      setSelectedLinkId(null)
      setPending(null)
      setNotice('Line imported')
    } catch {
      setNotice('Could not import: choose a Starline JSON export')
    }
    event.target.value = ''
  }

  const deleteProject = () => {
    if (workspace.projects.length === 1) {
      setNotice('Keep at least one line in your workspace')
      return
    }
    if (!window.confirm(`Delete “${project.name}”? This removes its local copy.`)) return
    setWorkspace((current) => {
      const projects = current.projects.filter((p) => p.id !== current.activeId)
      return { projects, activeId: projects[0].id }
    })
    setSelectedId(null)
    setSelectedLinkId(null)
  }

  const linkPath = (link: Link) => {
    const source = project.stages.find((s) => s.id === link.fromStage)
    const target = project.stages.find((s) => s.id === link.toStage)
    if (!source || !target) return null
    const outputIndex = source.outputs.findIndex((p) => p.id === link.fromPort)
    const inputIndex = target.inputs.findIndex((p) => p.id === link.toPort)
    if (outputIndex < 0 || inputIndex < 0) return null
    const x1 = source.x + NODE_WIDTH
    const y1 = source.y + PORT_OFFSET + outputIndex * PORT_STEP
    const x2 = target.x
    const y2 = target.y + PORT_OFFSET + inputIndex * PORT_STEP
    const bend = Math.max(70, Math.abs(x2 - x1) * 0.48)
    return `M ${x1} ${y1} C ${x1 + bend} ${y1}, ${x2 - bend} ${y2}, ${x2} ${y2}`
  }

  const totalEu = project.stages.reduce(
    (sum, stage) => sum + Math.max(0, stageTiming(stage).eut ?? 0) * Math.max(1, stage.parallel),
    0,
  )
  const linkSource = selectedLink && project.stages.find((s) => s.id === selectedLink.fromStage)
  const linkTarget = selectedLink && project.stages.find((s) => s.id === selectedLink.toStage)

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">
            <span>✳</span>
          </div>
          <div>
            <strong>STARLINE</strong>
            <small>PROCESSING PLANNER</small>
          </div>
        </div>
        <div className="sidebar-section-label">
          WORKSPACE <span>{workspace.projects.length}</span>
        </div>
        <button className="new-line" onClick={createLine}>
          <Icon name="plus" size={17} /> New line
        </button>
        <div className="project-list">
          {workspace.projects.map((item) => (
            <button
              key={item.id}
              className={`project-item ${item.id === project.id ? 'active' : ''}`}
              onClick={() => {
                setWorkspace((current) => ({ ...current, activeId: item.id }))
                setSelectedId(null)
                setSelectedLinkId(null)
                setPending(null)
              }}
            >
              <span className="project-icon">
                <Icon name="grid" size={16} />
              </span>
              <span className="project-copy">
                <strong>{item.name}</strong>
                <small>
                  {item.stages.length} stages · {item.links.length} links
                </small>
              </span>
              <Icon name="chevron" size={15} />
            </button>
          ))}
        </div>
        <div className="sidebar-bottom">
          <div className="sidebar-help">
            <span className="help-star">✦</span>
            <strong>Build your flow</strong>
            <p>Add machines, set recipe rates, then connect an output to an input.</p>
          </div>
          <div className="pack-label">
            <span className="status-dot" /> STAR TECHNOLOGY <span>·</span> COMMUNITY TOOL
          </div>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <select
            className="mobile-project-select"
            aria-label="Select processing line"
            value={project.id}
            onChange={(event) => {
              setWorkspace((current) => ({ ...current, activeId: event.target.value }))
              setSelectedId(null)
              setSelectedLinkId(null)
              setPending(null)
            }}
          >
            {workspace.projects.map((item) => (
              <option key={item.id} value={item.id}>
                {item.name}
              </option>
            ))}
          </select>
          <div className="breadcrumb">
            WORKSPACE <Icon name="chevron" size={13} /> <span>{project.name}</span>
          </div>
          <div className="top-actions">
            <span className="save-indicator">
              <span className="status-dot" /> Saved locally
            </span>
            <button className="button subtle" onClick={() => fileRef.current?.click()}>
              <Icon name="upload" size={16} /> Import JSON
            </button>
            <button className="button subtle" onClick={exportLine}>
              <Icon name="download" size={16} /> Export JSON
            </button>
            <input ref={fileRef} type="file" accept="application/json,.json" hidden onChange={importLine} />
          </div>
        </header>
        <div className="line-header">
          <div>
            <div className="eyebrow">
              <span>✦</span> LINE DESIGNER <span className="eyebrow-rule" />
            </div>
            <h1>{project.name}</h1>
            <p>{project.description || 'Map machines, materials, and throughput in one place.'}</p>
          </div>
          <div className="header-actions">
            <button
              className="button primary"
              onClick={startSourceLine}
              disabled={!sourceRecipe}
              aria-label="New source line"
            >
              <Icon name="bolt" size={16} /> New source line
            </button>
            <button className="button subtle" onClick={() => setCatalogOpen(true)}>
              <Icon name="grid" size={16} /> Recipe catalog
            </button>
            <button className="button primary" onClick={addStage}>
              <Icon name="plus" size={18} /> Add stage
            </button>
          </div>
        </div>
        <div className="stats-row">
          <div className="stat">
            <span className="stat-icon violet">
              <Icon name="layers" />
            </span>
            <div>
              <strong>{project.stages.length}</strong>
              <small>STAGES</small>
            </div>
          </div>
          <div className="stat">
            <span className="stat-icon blue">
              <Icon name="link" />
            </span>
            <div>
              <strong>{project.links.length}</strong>
              <small>CONNECTIONS</small>
            </div>
          </div>
          <div className="stat">
            <span className="stat-icon amber">
              <Icon name="bolt" />
            </span>
            <div>
              <strong>
                {totalEu.toLocaleString()} <em>EU/t</em>
              </strong>
              <small>CONFIGURED POWER</small>
            </div>
          </div>
          <div className="stat-tip">Rates include machine tier, chance, and available linked inputs.</div>
        </div>
        {sourceStages.length === 0 ? (
          <section className="extractor-banner">
            <div>
              <span className="eyebrow">START FROM A SOURCE</span>
              <h2>Choose your resource line</h2>
              <p>
                Start with void extraction, sieving, or geode filtration. Set voltage and machine count, then
                process each output.
              </p>
            </div>
            <div className="source-picker">
              <select
                aria-label="Source recipe"
                value={sourceRecipe?.key ?? ''}
                onChange={(event) => setSourceKey(event.target.value)}
              >
                {sourceRecipes.map((recipe) => (
                  <option key={recipe.key} value={recipe.key}>
                    {sourceTitle(recipe)}
                  </option>
                ))}
              </select>
              <button className="button primary" onClick={addSourceHere} disabled={!sourceRecipe}>
                <Icon name="plus" size={16} /> Add to this line
              </button>
            </div>
          </section>
        ) : (
          <section className="extractor-config" aria-label="Source machines">
            <div className="section-title">
              <div>
                <span className="eyebrow">SOURCE MACHINES</span>
                <h2>Resource generation</h2>
              </div>
              <div className="source-picker">
                {recommendedOrePaths.length > 0 && (
                  <button
                    className="button subtle"
                    onClick={() =>
                      recommendedOrePaths.forEach(({ stage, port, recipe }) =>
                        addFromOutput(stage, port, recipe),
                      )
                    }
                  >
                    <Icon name="bolt" size={15} /> Macerate {recommendedOrePaths.length} raw ores
                  </button>
                )}
                <select
                  aria-label="Additional source recipe"
                  value={sourceRecipe?.key ?? ''}
                  onChange={(event) => setSourceKey(event.target.value)}
                >
                  {sourceRecipes.map((recipe) => (
                    <option key={recipe.key} value={recipe.key}>
                      {sourceTitle(recipe)}
                    </option>
                  ))}
                </select>
                <button className="button subtle" onClick={addSourceHere} disabled={!sourceRecipe}>
                  <Icon name="plus" size={15} /> Add source
                </button>
              </div>
            </div>
            <div className="extractor-list">
              {sourceStages.map((source) => {
                const timing = analysis.stages.get(source.id)?.timing
                return (
                  <div className="extractor-controls" key={source.id}>
                    <strong>{source.name}</strong>
                    <label>
                      Voltage tier
                      <select
                        value={source.tier}
                        onChange={(event) =>
                          updateStage(source.id, (stage) => ({ ...stage, tier: event.target.value }))
                        }
                      >
                        {VOLTAGE_TIERS.slice(1).map((tier) => (
                          <option key={tier} value={tier}>
                            {tier}
                          </option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Machines
                      <input
                        type="number"
                        min="1"
                        max="100000"
                        step="1"
                        value={source.parallel}
                        onChange={(event) =>
                          updateStage(source.id, (stage) => ({
                            ...stage,
                            parallel: Math.max(1, Math.floor(Number(event.target.value) || 1)),
                          }))
                        }
                      />
                    </label>
                    <span className="extractor-speed">
                      {timing?.durationSeconds == null
                        ? 'Rate unavailable'
                        : `${timing.durationSeconds}s/cycle · ${timing.overclocks} overclocks`}
                    </span>
                  </div>
                )
              })}
            </div>
            <p className="calculation-note">
              Chance-based amounts are expected averages after tier bonuses. Unlinked inputs, such as drilling
              fluid or gravel, are assumed available.
            </p>
          </section>
        )}
        <section className="workspace-body">
          <div className="canvas-panel">
            <div className="canvas-toolbar">
              <div className="view-tabs" role="tablist" aria-label="Line views">
                <button
                  role="tab"
                  aria-selected={view === 'canvas'}
                  className={view === 'canvas' ? 'active' : ''}
                  onClick={() => setView('canvas')}
                >
                  Canvas
                </button>
                <button
                  role="tab"
                  aria-selected={view === 'totals'}
                  className={view === 'totals' ? 'active' : ''}
                  onClick={() => setView('totals')}
                >
                  Total output
                </button>
              </div>
              <div className="canvas-tools">
                {view === 'canvas' && (
                  <button
                    className="arrange-button"
                    onClick={autoArrange}
                    disabled={project.stages.length < 2}
                  >
                    Arrange
                  </button>
                )}
                {view === 'canvas' && (
                  <>
                    <button
                      onClick={() => setZoom((z) => Math.max(0.5, +(z - 0.1).toFixed(1)))}
                      aria-label="Zoom out"
                    >
                      −
                    </button>
                    <span>{Math.round(zoom * 100)}%</span>
                    <button
                      onClick={() => setZoom((z) => Math.min(1.5, +(z + 0.1).toFixed(1)))}
                      aria-label="Zoom in"
                    >
                      +
                    </button>
                    <button className="zoom-reset" onClick={() => setZoom(1)}>
                      Reset
                    </button>
                  </>
                )}
              </div>
            </div>
            {view === 'canvas' ? (
              <>
                <div
                  className="canvas-viewport"
                  ref={viewportRef}
                  onClick={(event) => {
                    if (event.target === event.currentTarget) {
                      setSelectedId(null)
                      setSelectedLinkId(null)
                      setSelectedOutput(null)
                      setPending(null)
                    }
                  }}
                >
                  <div
                    className="canvas-sizer"
                    style={{ width: dimensions.width * zoom, height: dimensions.height * zoom }}
                  >
                    <div
                      className="canvas-surface"
                      style={{
                        width: dimensions.width,
                        height: dimensions.height,
                        transform: `scale(${zoom})`,
                      }}
                      onClick={(event) => {
                        if (event.target === event.currentTarget) {
                          setSelectedId(null)
                          setSelectedLinkId(null)
                          setSelectedOutput(null)
                          setPending(null)
                        }
                      }}
                    >
                      <div className="canvas-watermark">
                        STARLINE <span>/</span> FLOW 01
                      </div>
                      <svg
                        className="connection-layer"
                        width={dimensions.width}
                        height={dimensions.height}
                        aria-label="Stage connections"
                      >
                        {project.links.map((link) => {
                          const path = linkPath(link)
                          return (
                            path && (
                              <g
                                key={link.id}
                                className={`connection ${link.id === selectedLinkId ? 'selected' : ''}`}
                                onClick={(event) => {
                                  event.stopPropagation()
                                  setSelectedLinkId(link.id)
                                  setSelectedId(null)
                                  setSelectedOutput(null)
                                }}
                              >
                                <path className="connection-hit" d={path} />
                                <path className="connection-line" d={path} />
                                <circle
                                  cx={Number(path.split(' ')[1])}
                                  cy={Number(path.split(' ')[2])}
                                  r="3"
                                />
                              </g>
                            )
                          )
                        })}
                      </svg>
                      {project.stages.map((stage, index) => (
                        <div
                          key={stage.id}
                          className={`stage-node ${selectedId === stage.id || selectedOutput?.stageId === stage.id ? 'selected' : ''}`}
                          style={{ left: stage.x, top: stage.y }}
                          onClick={(event) => {
                            event.stopPropagation()
                            setSelectedId(stage.id)
                            setSelectedOutput(null)
                            setSelectedLinkId(null)
                          }}
                        >
                          <div
                            className="node-head"
                            onPointerDown={(event) => startDrag(event, stage)}
                            onPointerMove={moveDrag}
                            onPointerUp={() => {
                              dragRef.current = null
                            }}
                            onPointerCancel={() => {
                              dragRef.current = null
                            }}
                          >
                            <span className="node-index">{String(index + 1).padStart(2, '0')}</span>
                            <div className="node-title">
                              <strong>{stage.name}</strong>
                              <small>{stage.machine}</small>
                            </div>
                            <span className="node-tier">{stage.tier}</span>
                          </div>
                          <div className="node-meta">
                            <span>
                              <Icon name="clock" size={13} />{' '}
                              {analysis.stages.get(stage.id)?.timing.durationSeconds == null
                                ? '?'
                                : `${analysis.stages.get(stage.id)?.timing.durationSeconds}s`}
                            </span>
                            <span>
                              <Icon name="bolt" size={13} />{' '}
                              {analysis.stages.get(stage.id)?.timing.eut ?? '?'} EU/t
                            </span>
                            <span>×{stage.parallel}</span>
                          </div>
                          <div className="port-labels">
                            <span>INPUTS</span>
                            <span>OUTPUTS</span>
                          </div>
                          <div className="port-rows">
                            {Array.from(
                              { length: Math.max(1, stage.inputs.length, stage.outputs.length) },
                              (_, portIndex) => (
                                <div className="port-row" key={portIndex}>
                                  <div className="port-cell input-cell">
                                    {stage.inputs[portIndex] && (
                                      <>
                                        <button
                                          className="port-dot input-dot"
                                          title={`Connect to ${stage.inputs[portIndex].name}`}
                                          onClick={(event) => {
                                            event.stopPropagation()
                                            handleInputPort(stage, stage.inputs[portIndex])
                                          }}
                                        />
                                        <div>
                                          <strong>{stage.inputs[portIndex].name}</strong>
                                          <small>
                                            {stage.inputs[portIndex].amount} {stage.inputs[portIndex].unit} /
                                            recipe
                                          </small>
                                        </div>
                                      </>
                                    )}
                                  </div>
                                  <div
                                    className={`port-cell output-cell ${selectedOutput?.portId === stage.outputs[portIndex]?.id ? 'active' : ''}`}
                                  >
                                    {stage.outputs[portIndex] && (
                                      <>
                                        <button
                                          className="output-choice"
                                          title={`Choose recipe for ${stage.outputs[portIndex].name}`}
                                          onClick={(event) => {
                                            event.stopPropagation()
                                            openOutput(stage, stage.outputs[portIndex])
                                          }}
                                        >
                                          <strong>{stage.outputs[portIndex].name}</strong>
                                          <small>
                                            {stage.outputs[portIndex].amount} {stage.outputs[portIndex].unit}{' '}
                                            / recipe
                                          </small>
                                        </button>
                                        <button
                                          className={`port-dot output-dot ${pending?.portId === stage.outputs[portIndex].id || selectedOutput?.portId === stage.outputs[portIndex].id ? 'pending' : ''}`}
                                          title={`Choose recipe for ${stage.outputs[portIndex].name}`}
                                          onClick={(event) => {
                                            event.stopPropagation()
                                            openOutput(stage, stage.outputs[portIndex])
                                          }}
                                        />
                                      </>
                                    )}
                                  </div>
                                </div>
                              ),
                            )}
                          </div>
                          <div className="node-footer">
                            <span>
                              <span className="tiny-spark">✦</span>{' '}
                              {stage.outputs[0]
                                ? formatPerMinute(
                                    analysis.stages.get(stage.id)?.outputs.get(stage.outputs[0].id) ?? 0,
                                    stage.outputs[0].unit,
                                  )
                                : 'No output'}
                            </span>
                            <Icon name="chevron" size={14} />
                          </div>
                        </div>
                      ))}
                      {project.stages.length === 0 && (
                        <div className="empty-canvas">
                          <span>✳</span>
                          <h2>Your line starts here</h2>
                          <p>Add a stage to define its machine, inputs, outputs, and production rate.</p>
                          <button className="button primary" onClick={addStage}>
                            <Icon name="plus" size={17} /> Add first stage
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </div>
                <div className="canvas-foot">
                  <span>
                    <span className="mouse-hint">↔</span> Drag node headers to move
                  </span>
                  <span>
                    Click an output to choose its next recipe <span className="foot-separator">·</span>{' '}
                    {project.stages.length} nodes on canvas
                  </span>
                </div>
              </>
            ) : (
              <TotalOutputView
                project={project}
                totals={totals}
                finalCount={finalOutputs.length}
                warnings={analysis.warnings}
              />
            )}
          </div>

          <aside className="inspector" ref={inspectorRef}>
            <div className="inspector-heading">
              <span>INSPECTOR</span>
              <span className="inspector-spark">✦</span>
            </div>
            {outputStage && outputPort ? (
              <OutputRecipeInspector
                key={outputPort.id}
                stage={outputStage}
                port={outputPort}
                produced={analysis.stages.get(outputStage.id)?.outputs.get(outputPort.id) ?? 0}
                available={analysis.available.get(outputPort.id) ?? 0}
                options={outputRecipes.get(`${outputPort.materialId}|${outputPort.unit}`) ?? []}
                catalog={catalog}
                catalogError={catalogError}
                onAdd={addFromOutput}
                onManualConnect={() => {
                  setPending({ stageId: outputStage.id, portId: outputPort.id })
                  setNotice('Select an input port to connect')
                }}
              />
            ) : selectedStage ? (
              <StageInspector
                stage={selectedStage}
                catalog={catalog}
                analysis={analysis.stages.get(selectedStage.id)}
                update={(change) =>
                  updateStage(selectedStage.id, (s) => {
                    const next = change(s)
                    return {
                      ...next,
                      recipeRef: next.recipeRef
                        ? {
                            ...next.recipeRef,
                            modified:
                              next.recipeRef.modified ||
                              next.machine !== s.machine ||
                              next.duration !== s.duration ||
                              next.eut !== s.eut ||
                              next.inputs !== s.inputs ||
                              next.outputs !== s.outputs,
                          }
                        : undefined,
                    }
                  })
                }
                duplicate={() => duplicateStage(selectedStage)}
                remove={() => removeStage(selectedStage.id)}
                removePort={(direction, id) =>
                  updateProject((p) => ({
                    ...p,
                    stages: p.stages.map((s) =>
                      s.id === selectedStage.id
                        ? {
                            ...s,
                            [direction]: s[direction].filter((port) => port.id !== id),
                            recipeRef: s.recipeRef ? { ...s.recipeRef, modified: true } : undefined,
                          }
                        : s,
                    ),
                    links: p.links.filter((link) =>
                      direction === 'inputs' ? link.toPort !== id : link.fromPort !== id,
                    ),
                  }))
                }
              />
            ) : selectedLink && linkSource && linkTarget ? (
              <div className="inspector-content">
                <div className="inspector-object-icon blue">
                  <Icon name="link" size={23} />
                </div>
                <h2>Connection</h2>
                <p className="inspector-intro">Material flow between two stages.</p>
                <div className="connection-detail">
                  <strong>{linkSource.name}</strong>
                  <small>{linkSource.outputs.find((p) => p.id === selectedLink.fromPort)?.name}</small>
                  <span>↓</span>
                  <strong>{linkTarget.name}</strong>
                  <small>{linkTarget.inputs.find((p) => p.id === selectedLink.toPort)?.name}</small>
                </div>
                <button
                  className="danger-button"
                  onClick={() => {
                    updateProject((p) => ({ ...p, links: p.links.filter((l) => l.id !== selectedLink.id) }))
                    setSelectedLinkId(null)
                  }}
                >
                  <Icon name="trash" size={16} /> Remove connection
                </button>
              </div>
            ) : (
              <div className="inspector-content">
                <div className="inspector-object-icon">
                  <Icon name="grid" size={23} />
                </div>
                <h2>Line settings</h2>
                <p className="inspector-intro">Give this line a name and describe what it produces.</p>
                <label className="field">
                  <span>LINE NAME</span>
                  <input
                    value={project.name}
                    onChange={(event) => updateProject((p) => ({ ...p, name: event.target.value }))}
                  />
                </label>
                <label className="field">
                  <span>DESCRIPTION</span>
                  <textarea
                    rows={4}
                    value={project.description}
                    placeholder="What does this line make?"
                    onChange={(event) => updateProject((p) => ({ ...p, description: event.target.value }))}
                  />
                </label>
                <div className="inspector-rule" />
                <div className="inspector-note">
                  <span>✧</span>
                  <p>
                    Select a stage to edit its recipe and throughput. Your changes are saved in this browser.
                  </p>
                </div>
                <button className="danger-button" onClick={deleteProject}>
                  <Icon name="trash" size={16} /> Delete this line
                </button>
              </div>
            )}
          </aside>
        </section>
      </main>
      {catalogOpen && (
        <CatalogDrawer
          catalog={catalog}
          error={catalogError}
          query={catalogQuery}
          setQuery={setCatalogQuery}
          includePartial={includePartial}
          setIncludePartial={setIncludePartial}
          onAdd={addCatalogRecipe}
          onClose={() => setCatalogOpen(false)}
        />
      )}
      {notice && (
        <div className="toast" role="status">
          {notice}
          <button onClick={() => setNotice('')} aria-label="Dismiss">
            <Icon name="close" size={14} />
          </button>
        </div>
      )}
    </div>
  )
}

function OutputRecipeInspector({
  stage,
  port,
  produced,
  available,
  options,
  catalog,
  catalogError,
  onAdd,
  onManualConnect,
}: {
  stage: Stage
  port: Port
  produced: number
  available: number
  options: CatalogRecipe[]
  catalog: Catalog | null
  catalogError: string
  onAdd: (stage: Stage, port: Port, recipe: CatalogRecipe | null) => void
  onManualConnect: () => void
}) {
  const [query, setQuery] = useState('')
  const [selectedKey, setSelectedKey] = useState('')
  const matching = options.filter((recipe) =>
    `${recipe.machine} ${recipe.outputs.map((output) => output.id).join(' ')}`
      .toLowerCase()
      .includes(query.toLowerCase()),
  )
  const selected = matching.find((recipe) => recipe.key === selectedKey) ?? matching[0]
  const input = selected?.inputs.find((stack) => catalog && inputAcceptsPort(catalog, stack, port))
  const tier = selected ? nextTier(stage.tier, selected.eut) : stage.tier
  const machines = selected && input ? machinesForInput(selected, input, available, tier) : null
  return (
    <div className="inspector-content output-inspector">
      <div className="inspector-object-icon">
        <Icon name="chevron" size={23} />
      </div>
      <h2>Process {port.name}</h2>
      <p className="inspector-intro">
        From {stage.name} ·{' '}
        {outputChance(port, stage) < 1
          ? `${Math.round(outputChance(port, stage) * 100)}% expected chance`
          : 'guaranteed'}
      </p>
      <div className="output-rate-card">
        <span>Produced</span>
        <strong>{formatPerMinute(produced, port.unit)}</strong>
        <span>Available for a new stage</span>
        <strong>{formatPerMinute(available, port.unit)}</strong>
      </div>
      <label className="field">
        <span>FIND A RECIPE · {options.length} MATCHES</span>
        <input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Machine or output…"
          aria-label="Search matching recipes"
        />
      </label>
      <div className="recipe-options" role="listbox" aria-label={`Recipes for ${port.name}`}>
        {matching.slice(0, 60).map((recipe) => (
          <button
            key={recipe.key}
            role="option"
            aria-selected={selected?.key === recipe.key}
            className={selected?.key === recipe.key ? 'active' : ''}
            onClick={() => setSelectedKey(recipe.key)}
          >
            <strong>{displayName(recipe.machine)}</strong>
            <small>
              {recipe.outputs
                .slice(0, 2)
                .map((output) => displayName(output.id))
                .join(' + ') || 'No output'}
            </small>
          </button>
        ))}
        {matching.length > 60 && <p>Showing 60 recipes. Narrow the search to see more.</p>}
        {matching.length === 0 && (
          <p>
            {catalog
              ? 'No matching calculable recipe found.'
              : catalogError
                ? `Catalog unavailable: ${catalogError}`
                : 'Loading recipes…'}
          </p>
        )}
      </div>
      {selected && input && (
        <div className="recipe-preview">
          <strong>
            {machines ?? '—'} {displayName(selected.machine)} at {tier}
          </strong>
          <small>Estimated machines to process the available input</small>
          {selected.outputs.slice(0, 4).map((output) => (
            <div key={output.id}>
              <span>{displayName(output.id)}</span>
              <b>
                {formatPerMinute(
                  (available / input.amount) * output.amount * stackChance(output, selected, tier),
                  output.unit,
                )}
              </b>
            </div>
          ))}
        </div>
      )}
      <button
        className="button primary output-add"
        disabled={!selected || !input || available <= 1e-9}
        onClick={() => selected && onAdd(stage, port, selected)}
      >
        Add selected recipe
      </button>
      <div className="output-secondary">
        <button onClick={() => onAdd(stage, port, null)} disabled={available <= 1e-9}>
          Add custom stage
        </button>
        <button onClick={onManualConnect}>Connect to existing input</button>
      </div>
    </div>
  )
}

function TotalOutputView({
  project,
  totals,
  finalCount,
  warnings,
}: {
  project: Project
  totals: ReturnType<typeof outputTotals>
  finalCount: number
  warnings: string[]
}) {
  const items = totals.filter((output) => output.unit === 'items')
  const fluids = totals.filter((output) => output.unit === 'mB')
  return (
    <div className="totals-view" role="tabpanel" aria-label="Total output">
      <div className="totals-heading">
        <span className="eyebrow">AFTER LINKED STAGES</span>
        <h2>Total output</h2>
        <p>
          Expected rates per minute across the whole line. Linked stages consume upstream output; unlinked
          inputs are assumed available.
        </p>
      </div>
      <div className="totals-summary">
        <div>
          <strong>{finalCount}</strong>
          <span>NET PRODUCTS</span>
        </div>
        <div>
          <strong>{project.stages.length}</strong>
          <span>STAGES</span>
        </div>
        <div>
          <strong>{project.stages.reduce((sum, stage) => sum + Math.max(1, stage.parallel), 0)}</strong>
          <span>MACHINES</span>
        </div>
      </div>
      {totals.length ? (
        [items, fluids].map(
          (group, index) =>
            group.length > 0 && (
              <section className="totals-group" key={index}>
                <h3>{index === 0 ? 'Items' : 'Fluids'}</h3>
                <div className="totals-table">
                  <div className="totals-table-head">
                    <span>OUTPUT</span>
                    <span>PRODUCED / MIN</span>
                    <span>USED IN LINE / MIN</span>
                    <span>NET / MIN</span>
                  </div>
                  {group.map((output) => (
                    <div className="totals-table-row" key={`${output.name}|${output.unit}`}>
                      <strong>{output.name}</strong>
                      <span>{formatPerMinute(output.produced, output.unit)}</span>
                      <span>{formatPerMinute(output.allocated, output.unit)}</span>
                      <b>{formatPerMinute(output.net, output.unit)}</b>
                    </div>
                  ))}
                </div>
              </section>
            ),
        )
      ) : (
        <p className="pathway-empty">Add a source stage to calculate its outputs.</p>
      )}
      {warnings.map((warning) => (
        <p className="calculation-note" key={warning}>
          {warning}
        </p>
      ))}
    </div>
  )
}

function CatalogDrawer({
  catalog,
  error,
  query,
  setQuery,
  includePartial,
  setIncludePartial,
  onAdd,
  onClose,
}: {
  catalog: Catalog | null
  error: string
  query: string
  setQuery: (value: string) => void
  includePartial: boolean
  setIncludePartial: (value: boolean) => void
  onAdd: (recipe: CatalogRecipe) => void
  onClose: () => void
}) {
  const [rawKey, setRawKey] = useState<string | null>(null)
  const [rawData, setRawData] = useState<unknown>(null)
  const [rawError, setRawError] = useState('')
  const rawCache = useRef<Record<string, unknown> | null>(null)
  const rawRequest = useRef('')
  const inspectExport = async (recipe: CatalogRecipe) => {
    if (rawKey === recipe.key) {
      rawRequest.current = ''
      setRawKey(null)
      return
    }
    if (!catalog?.rawCatalog) return
    rawRequest.current = recipe.key
    setRawKey(recipe.key)
    setRawData(null)
    setRawError('')
    try {
      if (!rawCache.current) {
        const response = await fetch(`${import.meta.env.BASE_URL}${catalog.rawCatalog}`)
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const archive = await response.json()
        if (archive.packVersion !== catalog.packVersion || !archive.recipes)
          throw new Error('Export version does not match the catalog')
        rawCache.current = archive.recipes
      }
      if (rawRequest.current === recipe.key) setRawData(rawCache.current?.[recipe.key] ?? null)
    } catch (error) {
      if (rawRequest.current === recipe.key)
        setRawError(error instanceof Error ? error.message : 'Export unavailable')
    }
  }
  const results = catalog ? searchRecipes(catalog, query, includePartial) : []
  const completeCount = catalog?.recipes.filter(recipeIsReady).length ?? 0
  return (
    <div
      className="catalog-overlay"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose()
      }}
    >
      <aside className="catalog-drawer" aria-label="Recipe catalog">
        <div className="catalog-top">
          <div>
            <span className="eyebrow">STAR TECHNOLOGY SOURCE</span>
            <h2>Recipe catalog</h2>
            <p>Search exported in-game recipes and add them to your line.</p>
          </div>
          <button className="catalog-close" onClick={onClose} aria-label="Close catalog">
            <Icon name="close" size={18} />
          </button>
        </div>
        <div className="catalog-controls">
          <input
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search output, input, machine, or ID..."
            aria-label="Search recipes"
          />
          <label>
            <input
              type="checkbox"
              checked={includePartial}
              onChange={(event) => setIncludePartial(event.target.checked)}
            />{' '}
            Show entries that need review
          </label>
        </div>
        <div className="catalog-summary">
          {catalog ? (
            <>
              <strong>{completeCount.toLocaleString()}</strong> ready recipes <span>·</span>{' '}
              {catalog.recipes.length.toLocaleString()} recipes <span>·</span> {catalog.sources.length} source
              {catalog.sources.length === 1 ? '' : 's'}
            </>
          ) : error ? (
            `Catalog unavailable: ${error}`
          ) : (
            'Loading catalog...'
          )}
        </div>
        <div className="catalog-list">
          {results.map((recipe) => (
            <div className="recipe-card" key={recipe.key}>
              <div className="recipe-card-top">
                <span className="recipe-family">{recipe.family.toUpperCase()}</span>
                <span className={recipeIsReady(recipe) ? 'recipe-ready' : 'recipe-review'}>
                  {recipe.availability === 'source-declaration'
                    ? 'SOURCE ONLY'
                    : recipeIsReady(recipe)
                      ? 'READY'
                      : 'REVIEW'}
                </span>
              </div>
              <strong>{displayName(recipe.outputs[0]?.id ?? recipe.gameId ?? recipe.machine)}</strong>
              <small className="recipe-machine">
                {displayName(recipe.machine)} ·{' '}
                {recipe.durationTicks == null ? 'Duration unknown' : `${recipe.durationTicks / 20}s`} ·{' '}
                {recipe.eut == null ? 'EU/t unknown' : `${recipe.eut.toLocaleString()} EU/t`}
              </small>
              <div className="recipe-materials">
                <span>IN</span>
                <p>
                  {recipe.inputs.length ? recipe.inputs.map(displayStack).join(' + ') : 'No static inputs'}
                </p>
                <span>OUT</span>
                <p>
                  {recipe.outputs.length ? recipe.outputs.map(displayStack).join(' + ') : 'No static outputs'}
                </p>
              </div>
              {!recipeIsCalculable(recipe) && (
                <p className="recipe-warning">
                  {recipe.availability === 'source-declaration'
                    ? 'Source declaration; compare with the registered export before using its rates.'
                    : 'Review timing and unresolved fields before planning throughput.'}
                </p>
              )}
              <div className="recipe-card-actions">
                {catalog && sourceLink(recipe, catalog) ? (
                  <a href={sourceLink(recipe, catalog)} target="_blank" rel="noreferrer">
                    View source ↗
                  </a>
                ) : (
                  <span>In-game export</span>
                )}
                {recipe.availability === 'registered' && catalog?.rawCatalog && (
                  <button className="recipe-inspect" onClick={() => inspectExport(recipe)}>
                    {rawKey === recipe.key ? 'Hide JSON' : 'Inspect JSON'}
                  </button>
                )}
                <button onClick={() => onAdd(recipe)}>
                  <Icon name="plus" size={14} /> Add to line
                </button>
              </div>
              {rawKey === recipe.key && (
                <pre className="recipe-raw">
                  {rawError || (rawData ? JSON.stringify(rawData, null, 2) : 'Loading exported recipe...')}
                </pre>
              )}
            </div>
          ))}
          {catalog && results.length === 0 && (
            <div className="catalog-empty">No matching recipes. Try a material or machine name.</div>
          )}
          {catalog && results.length === 80 && (
            <div className="catalog-more">
              Showing the first 80 matches. Narrow your search to find a specific recipe.
            </div>
          )}
        </div>
        <div className="catalog-foot">
          {catalog?.sources.map((source) => (
            <div key={source.id}>
              {source.name} ·{' '}
              {source.url && source.commit ? (
                <a href={`${source.url}/tree/${source.commit}`} target="_blank" rel="noreferrer">
                  {source.commit.slice(0, 8)}
                </a>
              ) : (
                <span>Local instance</span>
              )}
              <br />
              <span>{source.scope}</span>
            </div>
          ))}
        </div>
      </aside>
    </div>
  )
}

function StageInspector({
  stage,
  catalog,
  analysis,
  update,
  duplicate,
  remove,
  removePort,
}: {
  stage: Stage
  catalog: Catalog | null
  analysis?: StageAnalysis
  update: (change: (stage: Stage) => Stage) => void
  duplicate: () => void
  remove: () => void
  removePort: (direction: 'inputs' | 'outputs', id: string) => void
}) {
  const set = <K extends keyof Stage>(key: K, value: Stage[K]) => update((s) => ({ ...s, [key]: value }))
  const updatePort = (direction: 'inputs' | 'outputs', id: string, change: Partial<Port>) =>
    update((s) => ({
      ...s,
      [direction]: s[direction].map((port) =>
        port.id === id
          ? {
              ...port,
              ...change,
              materialId:
                change.name !== undefined || change.unit !== undefined ? undefined : port.materialId,
            }
          : port,
      ),
    }))
  const addPort = (direction: 'inputs' | 'outputs') =>
    update((s) => ({
      ...s,
      [direction]: [
        ...s[direction],
        {
          id: newId(),
          name: direction === 'inputs' ? 'New input' : 'New output',
          amount: 1,
          unit: 'items' as const,
        },
      ],
    }))
  return (
    <div className="inspector-content stage-inspector">
      <div className="inspector-object-icon">
        <Icon name="layers" size={23} />
      </div>
      <div className="inspector-title-row">
        <div>
          <h2>{stage.name || 'Unnamed stage'}</h2>
          <p className="inspector-intro">Configure the machine and recipe.</p>
        </div>
        <span className="tier-pill">{stage.tier}</span>
      </div>
      {stage.recipeRef && (
        <div className={`stage-source ${stage.recipeRef.reviewRequired ? 'review' : ''}`}>
          <span>
            {stage.recipeRef.modified
              ? 'Based on source recipe · edited'
              : stage.recipeRef.reviewRequired
                ? 'Recipe needs source review'
                : 'Recipe fields extracted from source'}
          </span>
          {catalog &&
            (sourceLink(stage.recipeRef, catalog) ? (
              <a href={sourceLink(stage.recipeRef, catalog)} target="_blank" rel="noreferrer">
                View source ↗
              </a>
            ) : (
              <span>In-game export</span>
            ))}
        </div>
      )}
      <label className="field">
        <span>STAGE NAME</span>
        <input value={stage.name} onChange={(event) => set('name', event.target.value)} />
      </label>
      <label className="field">
        <span>MACHINE</span>
        <input value={stage.machine} onChange={(event) => set('machine', event.target.value)} />
      </label>
      <div className="field-grid">
        <label className="field">
          <span>TIER</span>
          <select value={stage.tier} onChange={(event) => set('tier', event.target.value)}>
            {!VOLTAGE_TIERS.includes(stage.tier) && <option value={stage.tier}>{stage.tier}</option>}
            {VOLTAGE_TIERS.slice(1).map((tier) => (
              <option key={tier} value={tier}>
                {tier}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>PARALLEL</span>
          <input
            type="number"
            min="1"
            step="1"
            value={stage.parallel}
            onChange={(event) => set('parallel', Math.max(1, Number(event.target.value) || 1))}
          />
        </label>
      </div>
      <div className="field-grid">
        <label className="field">
          <span>{stage.recipeRef ? 'SOURCE DURATION · SEC' : 'DURATION · SEC'}</span>
          <input
            type="number"
            min="0.1"
            step="0.1"
            value={stage.duration ?? ''}
            onChange={(event) =>
              set(
                'duration',
                event.target.value === '' ? null : Math.max(0.1, Number(event.target.value) || 0.1),
              )
            }
          />
        </label>
        <label className="field">
          <span>{stage.recipeRef ? 'SOURCE POWER · EU/T' : 'POWER · EU/T'}</span>
          <input
            type="number"
            min="0"
            step="1"
            value={stage.eut ?? ''}
            onChange={(event) =>
              set('eut', event.target.value === '' ? null : Math.max(0, Number(event.target.value) || 0))
            }
          />
        </label>
      </div>
      <div className="inspector-rule" />
      <PortEditor
        title="Inputs"
        direction="inputs"
        ports={stage.inputs}
        onAdd={() => addPort('inputs')}
        onChange={(id, change) => updatePort('inputs', id, change)}
        onRemove={(id) => removePort('inputs', id)}
      />
      <PortEditor
        title="Outputs"
        direction="outputs"
        ports={stage.outputs}
        onAdd={() => addPort('outputs')}
        onChange={(id, change) => updatePort('outputs', id, change)}
        onRemove={(id) => removePort('outputs', id)}
      />
      <div className="inspector-rule" />
      <label className="field">
        <span>NOTES</span>
        <textarea
          rows={3}
          value={stage.notes}
          placeholder="Automation details, bottlenecks..."
          onChange={(event) => set('notes', event.target.value)}
        />
      </label>
      <div className="throughput-card">
        <small>FIRST OUTPUT · EXPECTED RATE</small>
        <strong>
          {stage.outputs[0]
            ? formatPerMinute(analysis?.outputs.get(stage.outputs[0].id) ?? 0, stage.outputs[0].unit)
            : 'Add an output'}
        </strong>
        <span>
          {analysis?.timing.durationSeconds == null
            ? 'Set a valid duration and voltage tier'
            : `${analysis.timing.durationSeconds}s cycle · ${Math.round(
                (analysis.runsPerMinute / Math.max(analysis.capacityPerMinute, 1e-9)) * 100,
              )}% utilized`}
        </span>
      </div>
      <div className="inspector-actions">
        <button onClick={duplicate}>
          <Icon name="copy" size={15} /> Duplicate
        </button>
        <button className="danger" onClick={remove}>
          <Icon name="trash" size={15} /> Delete
        </button>
      </div>
    </div>
  )
}

function PortEditor({
  title,
  direction,
  ports,
  onAdd,
  onChange,
  onRemove,
}: {
  title: string
  direction: 'inputs' | 'outputs'
  ports: Port[]
  onAdd: () => void
  onChange: (id: string, change: Partial<Port>) => void
  onRemove: (id: string) => void
}) {
  return (
    <section className="port-editor">
      <div className="port-editor-heading">
        <strong>
          {title} <span>{ports.length}</span>
        </strong>
        <button onClick={onAdd}>
          <Icon name="plus" size={14} /> Add
        </button>
      </div>
      {ports.map((port) => (
        <div className="port-editor-row" key={port.id}>
          <div className="port-editor-top">
            <span className={`editor-port-dot ${direction}`} />
            <input
              aria-label={`${title} name`}
              value={port.name}
              onChange={(event) => onChange(port.id, { name: event.target.value })}
            />
            <button title="Remove port" aria-label={`Remove ${port.name}`} onClick={() => onRemove(port.id)}>
              <Icon name="close" size={13} />
            </button>
          </div>
          <div className="port-editor-bottom">
            <input
              aria-label={`${port.name} amount`}
              type="number"
              min="0"
              step="any"
              value={port.amount}
              onChange={(event) =>
                onChange(port.id, { amount: Math.max(0, Number(event.target.value) || 0) })
              }
            />
            <select
              aria-label={`${port.name} unit`}
              value={port.unit}
              onChange={(event) => onChange(port.id, { unit: event.target.value as Port['unit'] })}
            >
              <option value="items">items</option>
              <option value="mB">mB</option>
            </select>
            <span>/ recipe</span>
          </div>
          {port.materialId && <div className="port-material-id">{port.materialId}</div>}
        </div>
      ))}
    </section>
  )
}

createRoot(document.getElementById('root')!).render(<App />)
