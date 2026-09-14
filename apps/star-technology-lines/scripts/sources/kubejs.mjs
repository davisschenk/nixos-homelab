import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import ts from 'typescript'

const METHODS = new Set([
  'itemInputs',
  'inputFluids',
  'itemOutputs',
  'outputFluids',
  'fluidOutputs',
  'notConsumable',
  'chancedOutput',
  'chancedInput',
  'chancedFluidOutput',
  'chancedFluidInput',
  'itemOutputsRanged',
  'duration',
  'EUt',
  'circuit',
  'id',
])
const voltage = JSON.parse(await readFile(new URL('./voltage-values.json', import.meta.url), 'utf8'))

function memberPath(node) {
  if (!node) return null
  if (ts.isIdentifier(node)) return node.text
  if (ts.isPropertyAccessExpression(node)) {
    const parent = memberPath(node.expression)
    return parent && `${parent}.${node.name.text}`
  }
  return null
}

async function jsFiles(directory, packMode) {
  const entries = await readdir(directory, { withFileTypes: true })
  const files = []
  for (const entry of entries) {
    const full = path.join(directory, entry.name)
    if (entry.isDirectory() && entry.name !== 'deprecated') {
      if (['hardmode', 'hard'].includes(entry.name) && packMode !== 'hard') continue
      if (entry.name === 'default' && packMode !== 'default') continue
      if (entry.name === 'abydos' && packMode !== 'abydos') continue
      files.push(...(await jsFiles(full, packMode)))
    } else if (entry.isFile() && entry.name.endsWith('.js')) files.push(full)
  }
  return files.sort()
}

function staticStatements(statements, source, constants, depth) {
  const local = new Map(constants)
  for (const statement of statements) {
    if (ts.isVariableStatement(statement)) {
      for (const declaration of statement.declarationList.declarations) {
        if (!ts.isIdentifier(declaration.name)) return undefined
        const value = staticValue(declaration.initializer, source, local, depth + 1)
        if (value === undefined) return undefined
        local.set(declaration.name.text, value)
      }
    } else if (ts.isIfStatement(statement)) {
      const condition = staticValue(statement.expression, source, local, depth + 1)
      if (condition === undefined) return undefined
      const branch = condition ? statement.thenStatement : statement.elseStatement
      if (branch) {
        const result = staticStatements(
          ts.isBlock(branch) ? branch.statements : [branch],
          source,
          local,
          depth + 1,
        )
        if (result !== undefined) return result
      }
    } else if (ts.isReturnStatement(statement)) {
      return staticValue(statement.expression, source, local, depth + 1)
    } else {
      return undefined
    }
  }
  return undefined
}

export function staticValue(node, source, constants, depth = 0) {
  if (!node || depth > 20) return undefined
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text
  if (ts.isNumericLiteral(node)) return Number(node.text)
  if (node.kind === ts.SyntaxKind.TrueKeyword) return true
  if (node.kind === ts.SyntaxKind.FalseKeyword) return false
  if (ts.isParenthesizedExpression(node)) return staticValue(node.expression, source, constants, depth + 1)
  if (ts.isPrefixUnaryExpression(node)) {
    const value = staticValue(node.operand, source, constants, depth + 1)
    if (node.operator === ts.SyntaxKind.ExclamationToken && value !== undefined) return !value
    if (typeof value === 'number') return node.operator === ts.SyntaxKind.MinusToken ? -value : value
  }
  if (ts.isIdentifier(node) && constants.has(node.text)) {
    const binding = constants.get(node.text)
    return binding && typeof binding.kind === 'number'
      ? staticValue(binding, source, constants, depth + 1)
      : binding
  }
  if (ts.isPropertyAccessExpression(node)) {
    const full = memberPath(node)
    if (full && constants.has(full)) {
      const binding = constants.get(full)
      return binding && typeof binding.kind === 'number'
        ? staticValue(binding, source, constants, depth + 1)
        : binding
    }
    const owner = memberPath(node.expression)
    if (owner === 'GTValues' && node.name.text in voltage.tiers) return voltage.tiers[node.name.text]
    if (owner === 'GTValues' && node.name.text in voltage.values) return voltage.values[node.name.text]
    const factory = /^event\.recipes\.([\w]+)\.([\w]+)$/.exec(memberPath(node) ?? '')
    if (factory) return { __factory: { family: factory[1], machine: factory[2] } }
    const value = staticValue(node.expression, source, constants, depth + 1)
    if (value && typeof value === 'object') return node.name.text in value ? value[node.name.text] : null
  }
  if (ts.isElementAccessExpression(node)) {
    const array = staticValue(node.expression, source, constants, depth + 1)
    const index = staticValue(node.argumentExpression, source, constants, depth + 1)
    if (Array.isArray(array) && typeof index === 'number') return array[index]
    if (array && typeof array === 'object' && (typeof index === 'string' || typeof index === 'number'))
      return array[index]
    if (typeof array === 'string' && typeof index === 'number') return array[index]
  }
  if (ts.isArrayLiteralExpression(node)) {
    const values = node.elements.map((element) => staticValue(element, source, constants, depth + 1))
    return values.some((value) => value === undefined) ? undefined : values.flat()
  }
  if (ts.isObjectLiteralExpression(node)) {
    const result = {}
    for (const property of node.properties) {
      if (!ts.isPropertyAssignment(property)) return undefined
      const key =
        ts.isIdentifier(property.name) || ts.isStringLiteral(property.name) ? property.name.text : undefined
      const value = staticValue(property.initializer, source, constants, depth + 1)
      if (!key) return undefined
      if (value !== undefined) result[key] = value
    }
    return result
  }
  if (ts.isTemplateExpression(node)) {
    let result = node.head.text
    for (const span of node.templateSpans) {
      const value = staticValue(span.expression, source, constants, depth + 1)
      if (value === undefined) return undefined
      result += String(value) + span.literal.text
    }
    return result
  }
  if (ts.isBinaryExpression(node)) {
    const left = staticValue(node.left, source, constants, depth + 1)
    if (node.operatorToken.kind === ts.SyntaxKind.BarBarToken) {
      return left || staticValue(node.right, source, constants, depth + 1)
    }
    if (node.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken) {
      return left && staticValue(node.right, source, constants, depth + 1)
    }
    if (node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken) {
      return left ?? staticValue(node.right, source, constants, depth + 1)
    }
    const right = staticValue(node.right, source, constants, depth + 1)
    if (left === undefined || right === undefined) return undefined
    if (node.operatorToken.kind === ts.SyntaxKind.PlusToken) return left + right
    if (node.operatorToken.kind === ts.SyntaxKind.EqualsEqualsEqualsToken) return left === right
    if (node.operatorToken.kind === ts.SyntaxKind.ExclamationEqualsEqualsToken) return left !== right
    if (node.operatorToken.kind === ts.SyntaxKind.EqualsEqualsToken) return left == right
    if (node.operatorToken.kind === ts.SyntaxKind.ExclamationEqualsToken) return left != right
    if (node.operatorToken.kind === ts.SyntaxKind.GreaterThanEqualsToken) return left >= right
    if (node.operatorToken.kind === ts.SyntaxKind.LessThanEqualsToken) return left <= right
    if (node.operatorToken.kind === ts.SyntaxKind.GreaterThanToken) return left > right
    if (node.operatorToken.kind === ts.SyntaxKind.LessThanToken) return left < right
    if (
      node.operatorToken.kind === ts.SyntaxKind.MinusToken &&
      typeof left === 'number' &&
      typeof right === 'number'
    )
      return left - right
    if (typeof left === 'number' && typeof right === 'number') {
      if (node.operatorToken.kind === ts.SyntaxKind.AsteriskToken) return left * right
      if (node.operatorToken.kind === ts.SyntaxKind.SlashToken) return left / right
      if (node.operatorToken.kind === ts.SyntaxKind.PercentToken) return left % right
    }
  }
  if (ts.isConditionalExpression(node)) {
    const condition = staticValue(node.condition, source, constants, depth + 1)
    if (typeof condition === 'boolean')
      return staticValue(condition ? node.whenTrue : node.whenFalse, source, constants, depth + 1)
  }
  if (ts.isCallExpression(node)) {
    const expression = node.expression.getText(source)
    if (expression === 'parseInt') {
      const value = staticValue(node.arguments[0], source, constants, depth + 1)
      if (typeof value === 'string') return Number.parseInt(value, 10)
    }
    if (['Math.pow', 'Math.floor', 'Math.ceil', 'Math.round', 'Math.max', 'Math.min'].includes(expression)) {
      const values = node.arguments.map((arg) => staticValue(arg, source, constants, depth + 1))
      if (values.every((value) => typeof value === 'number')) return Math[expression.slice(5)](...values)
    }
    if (expression === 'id' || expression === 'global.id') {
      const value = staticValue(node.arguments[0], source, constants, depth + 1)
      return typeof value === 'string' ? `start:${value.toLowerCase()}` : undefined
    }
    if (expression === 'Item.of' || expression === 'Fluid.of') {
      const id = staticValue(node.arguments[0], source, constants, depth + 1)
      const amount = staticValue(node.arguments[1], source, constants, depth + 1)
      const nbt =
        expression === 'Item.of' && node.arguments[1] && typeof amount !== 'number'
          ? amount
          : expression === 'Item.of' && node.arguments[2]
            ? staticValue(node.arguments[2], source, constants, depth + 1)
            : undefined
      if (node.arguments[1] && typeof amount !== 'number' && nbt === undefined) return undefined
      if (node.arguments[2] && nbt === undefined) return undefined
      if (typeof id === 'string')
        return {
          id,
          amount: typeof amount === 'number' ? amount : 1,
          unit: expression === 'Fluid.of' ? 'mB' : 'items',
          ...(nbt !== undefined ? { nbt: String(nbt) } : {}),
        }
    }
    const callable = memberPath(node.expression)
    if (callable && constants.has(callable)) {
      const fn = constants.get(callable)
      if (
        fn &&
        (ts.isArrowFunction(fn) || ts.isFunctionExpression(fn) || ts.isFunctionDeclaration(fn)) &&
        fn.parameters.every((param) => ts.isIdentifier(param.name))
      ) {
        const args = node.arguments.map((arg) => staticValue(arg, source, constants, depth + 1))
        if (args.every((arg) => arg !== undefined)) {
          const inner = new Map(constants)
          fn.parameters.forEach((param, index) => inner.set(param.name.text, args[index]))
          if (ts.isBlock(fn.body)) return staticStatements(fn.body.statements, source, inner, depth + 1)
          return staticValue(fn.body, source, inner, depth + 1)
        }
      }
    }
    if (ts.isPropertyAccessExpression(node.expression)) {
      const owner = staticValue(node.expression.expression, source, constants, depth + 1)
      const args = node.arguments.map((arg) => staticValue(arg, source, constants, depth + 1))
      if (typeof owner === 'string' && args.every((arg) => arg !== undefined)) {
        if (node.expression.name.text === 'toLowerCase') return owner.toLowerCase()
        if (node.expression.name.text === 'toUpperCase') return owner.toUpperCase()
        if (
          node.expression.name.text === 'replace' &&
          typeof args[0] === 'string' &&
          typeof args[1] === 'string'
        )
          return owner.replace(args[0], args[1])
        if (node.expression.name.text === 'split' && typeof args[0] === 'string') return owner.split(args[0])
      }
      if (
        Array.isArray(owner) &&
        node.expression.name.text === 'includes' &&
        args.length === 1 &&
        args[0] !== undefined
      )
        return owner.includes(args[0])
    }
  }
  return undefined
}

function parseStack(value, unit) {
  if (value && typeof value === 'object' && typeof value.id === 'string')
    return {
      id: value.id,
      amount: value.amount,
      unit: value.unit,
      ...(value.nbt !== undefined ? { nbt: value.nbt } : {}),
    }
  if (typeof value !== 'string') return null
  const text = value.trim()
  const item = /^(?:(\d+)x\s+)?([^\s]+)$/.exec(text)
  const fluid = /^([^\s]+)(?:\s+(\d+))?$/.exec(text)
  const match = unit === 'items' ? item : fluid
  if (!match) return null
  return unit === 'items'
    ? { id: match[2], amount: Number(match[1] ?? 1), unit }
    : { id: match[1], amount: Number(match[2] ?? 1000), unit }
}

function recipeBase(node, source, aliases, constants) {
  if (!ts.isCallExpression(node)) return null
  const expression = node.expression
  if (ts.isPropertyAccessExpression(expression)) {
    const parent = expression.expression
    if (ts.isCallExpression(parent)) {
      const base = recipeBase(parent, source, aliases, constants)
      return (
        base && { ...base, methods: [...base.methods, { name: expression.name.text, args: node.arguments }] }
      )
    }
    const text = memberPath(expression)
    const match = /^event\.recipes\.([\w]+)\.([\w]+)$/.exec(text)
    if (match)
      return match[1] === 'gtceu'
        ? { family: match[1], machine: match[2], idNode: node.arguments[0], methods: [] }
        : {
            family: match[1],
            machine: match[2],
            idNode: null,
            methods: [{ name: 'baseArguments', args: node.arguments }],
          }
    if (ts.isIdentifier(parent) && aliases.has(parent.text)) {
      const alias = aliases.get(parent.text)
      if (!alias.machine)
        return {
          family: alias.family,
          machine: expression.name.text,
          idNode: null,
          methods: [{ name: 'baseArguments', args: node.arguments }],
        }
    }
    if (
      text === 'event.shaped' ||
      text === 'event.shapeless' ||
      text === 'event.smelting' ||
      text === 'event.blasting' ||
      text === 'event.custom'
    ) {
      return {
        family: 'kubejs',
        machine: text.slice(6),
        idNode: null,
        methods: [{ name: 'baseArguments', args: node.arguments }],
      }
    }
  }
  if (ts.isIdentifier(expression) && aliases.has(expression.text)) {
    const alias = aliases.get(expression.text)
    return { family: alias.family, machine: alias.machine, idNode: node.arguments[0], methods: [] }
  }
  if (ts.isIdentifier(expression)) {
    const value = staticValue(expression, source, constants)
    if (value?.__factory) return { ...value.__factory, idNode: node.arguments[0], methods: [] }
  }
  return null
}

function collectBindings(ast, globalBindings) {
  const constants = new Map(globalBindings)
  const aliases = new Map()
  const helpers = new Map()
  function visit(node) {
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) {
      const name = node.name.text
      const initializer = node.initializer
      if (ts.isArrowFunction(initializer) || ts.isFunctionExpression(initializer))
        helpers.set(name, initializer)
      const match = /^event\.recipes\.([\w]+)\.([\w]+)$/.exec(memberPath(initializer) ?? '')
      if (match) aliases.set(name, { family: match[1], machine: match[2] })
      else {
        const family = /^event\.recipes\.([\w]+)$/.exec(memberPath(initializer) ?? '')
        if (family) aliases.set(name, { family: family[1], machine: null })
      }
      if (!constants.has(name)) constants.set(name, initializer)
    }
    if (ts.isFunctionDeclaration(node) && node.name) {
      helpers.set(node.name.text, node)
      constants.set(node.name.text, node)
    }
    ts.forEachChild(node, visit)
  }
  visit(ast)
  return { constants, aliases, helpers }
}

function bindPattern(pattern, value, bindings) {
  if (ts.isIdentifier(pattern)) {
    bindings.set(pattern.text, value)
    return
  }
  if (ts.isObjectBindingPattern(pattern) && value && typeof value === 'object') {
    for (const element of pattern.elements) {
      const key =
        element.propertyName &&
        (ts.isIdentifier(element.propertyName) || ts.isStringLiteral(element.propertyName))
          ? element.propertyName.text
          : ts.isIdentifier(element.name)
            ? element.name.text
            : null
      if (key != null && key in value) bindPattern(element.name, value[key], bindings)
    }
  }
  if (ts.isArrayBindingPattern(pattern) && Array.isArray(value)) {
    pattern.elements.forEach((element, index) => {
      if (ts.isBindingElement(element)) bindPattern(element.name, value[index], bindings)
    })
  }
}

function numericIterations(node, ast, bindings) {
  if (!node.initializer || !node.condition || !node.incrementor) return null
  if (!ts.isVariableDeclarationList(node.initializer) || node.initializer.declarations.length !== 1)
    return null
  const declaration = node.initializer.declarations[0]
  if (!ts.isIdentifier(declaration.name) || !ts.isBinaryExpression(node.condition)) return null
  const name = declaration.name.text
  if (!ts.isIdentifier(node.condition.left) || node.condition.left.text !== name) return null
  const start = staticValue(declaration.initializer, ast, bindings)
  const end = staticValue(node.condition.right, ast, bindings)
  if (typeof start !== 'number' || typeof end !== 'number' || !Number.isFinite(start + end)) return null
  let step = null
  if (ts.isPostfixUnaryExpression(node.incrementor) && ts.isIdentifier(node.incrementor.operand)) {
    if (node.incrementor.operand.text !== name) return null
    step = node.incrementor.operator === ts.SyntaxKind.PlusPlusToken ? 1 : -1
  }
  if (ts.isBinaryExpression(node.incrementor) && ts.isIdentifier(node.incrementor.left)) {
    if (node.incrementor.left.text !== name) return null
    const amount = staticValue(node.incrementor.right, ast, bindings)
    if (typeof amount === 'number')
      step = node.incrementor.operatorToken.kind === ts.SyntaxKind.PlusEqualsToken ? amount : -amount
  }
  if (!step) return null
  const compare = (value) => {
    switch (node.condition.operatorToken.kind) {
      case ts.SyntaxKind.LessThanToken:
        return value < end
      case ts.SyntaxKind.LessThanEqualsToken:
        return value <= end
      case ts.SyntaxKind.GreaterThanToken:
        return value > end
      case ts.SyntaxKind.GreaterThanEqualsToken:
        return value >= end
      default:
        return false
    }
  }
  const values = []
  for (let value = start; compare(value) && values.length < 1000; value += step) values.push(value)
  if (values.length === 1000) return null
  return { name, values }
}

function parseRecipe(base, ast, constants, relativePath, line, sourceId) {
  const rawId = base.idNode ? staticValue(base.idNode, ast, constants) : undefined
  const gameId = typeof rawId === 'string' ? rawId : null
  const recipe = {
    key: `${sourceId}:${relativePath}:${line}:${base.machine}`,
    sourceId,
    sourcePath: relativePath,
    sourceLine: line,
    gameId,
    family: base.family,
    machine: base.machine,
    inputs: [],
    outputs: [],
    catalysts: [],
    durationTicks: null,
    eut: null,
    circuit: null,
    unresolved: [],
  }
  if (base.family === 'kubejs') {
    const args = base.methods.find((method) => method.name === 'baseArguments')?.args ?? []
    const output = staticValue(args[0], ast, constants)
    const stack = parseStack(output, 'items')
    if (stack) {
      recipe.outputs.push({ ...stack, chance: null })
      if (stack.nbt) recipe.unresolved.push('Output has NBT payload')
    } else recipe.unresolved.push(`output: ${args[0]?.getText(ast) ?? 'missing'}`)
    if (base.machine === 'shaped') {
      const pattern = staticValue(args[1], ast, constants)
      const key = staticValue(args[2], ast, constants)
      if (Array.isArray(pattern) && key && typeof key === 'object') {
        for (const [symbol, value] of Object.entries(key)) {
          const stack = parseStack(value, 'items')
          const count = pattern.join('').split(symbol).length - 1
          if (stack && count) recipe.inputs.push({ ...stack, amount: stack.amount * count, chance: null })
          else recipe.unresolved.push(`ingredient ${symbol}: ${String(value)}`)
        }
      } else recipe.unresolved.push('pattern or key not statically resolved')
    } else if (base.machine === 'shapeless') {
      const inputs = staticValue(args[1], ast, constants)
      if (Array.isArray(inputs)) {
        for (const value of inputs) {
          const stack = parseStack(value, 'items')
          if (stack) recipe.inputs.push({ ...stack, chance: null })
          else recipe.unresolved.push(`input: ${String(value)}`)
        }
      } else recipe.unresolved.push('ingredients not statically resolved')
    } else if (base.machine === 'smelting' || base.machine === 'blasting') {
      const input = parseStack(staticValue(args[1], ast, constants), 'items')
      if (input) recipe.inputs.push({ ...input, chance: null })
      else recipe.unresolved.push('input not statically resolved')
    } else recipe.unresolved.push('custom recipe payload not normalized')
  } else if (base.family !== 'gtceu') {
    const args = base.methods.find((method) => method.name === 'baseArguments')?.args ?? []
    const output = staticValue(args[0], ast, constants)
    for (const value of Array.isArray(output) ? output : [output]) {
      const parsed = parseStack(value, 'items')
      if (parsed) {
        recipe.outputs.push({ ...parsed, chance: null })
        if (parsed.nbt) recipe.unresolved.push('Output has NBT payload')
      } else recipe.unresolved.push(`output: ${args[0]?.getText(ast) ?? 'missing'}`)
    }
    const input = staticValue(args[1], ast, constants)
    for (const value of Array.isArray(input) ? input : [input]) {
      const parsed = parseStack(value, 'items')
      if (parsed) {
        recipe.inputs.push({ ...parsed, chance: null })
        if (parsed.nbt) recipe.unresolved.push('Input has NBT payload')
      } else recipe.unresolved.push(`input: ${args[1]?.getText(ast) ?? 'missing'}`)
    }
    recipe.unresolved.push(`${base.family}.${base.machine}: machine timing not modeled`)
  }
  const methods = [...base.methods]
  for (const method of base.methods) {
    if (method.name !== 'layeredRecipe') continue
    const callback = method.args[0]
    if (!callback || (!ts.isArrowFunction(callback) && !ts.isFunctionExpression(callback))) continue
    function collectLayer(node) {
      if (
        ts.isCallExpression(node) &&
        ts.isPropertyAccessExpression(node.expression) &&
        ['itemInputs', 'inputFluids'].includes(node.expression.name.text)
      ) {
        methods.push({ name: node.expression.name.text, args: node.arguments })
      }
      ts.forEachChild(node, collectLayer)
    }
    collectLayer(callback.body)
  }
  for (const method of methods) {
    if (!METHODS.has(method.name)) continue
    const values = method.args.map((arg) => staticValue(arg, ast, constants))
    if (values.some((value) => value === undefined)) {
      recipe.unresolved.push(`${method.name}: ${method.args.map((arg) => arg.getText(ast)).join(', ')}`)
      continue
    }
    const flat = values.flat()
    if (method.name === 'duration' && typeof flat[0] === 'number') recipe.durationTicks = flat[0]
    else if (method.name === 'EUt' && typeof flat[0] === 'number') recipe.eut = flat[0]
    else if (method.name === 'circuit' && typeof flat[0] === 'number') recipe.circuit = flat[0]
    else if (method.name === 'id' && typeof flat[0] === 'string') recipe.gameId = flat[0]
    else if (
      [
        'itemInputs',
        'inputFluids',
        'itemOutputs',
        'outputFluids',
        'fluidOutputs',
        'notConsumable',
        'chancedOutput',
        'chancedInput',
        'chancedFluidOutput',
        'chancedFluidInput',
        'itemOutputsRanged',
      ].includes(method.name)
    ) {
      const unit =
        method.name.includes('Fluid') ||
        method.name === 'inputFluids' ||
        method.name === 'outputFluids' ||
        method.name === 'fluidOutputs'
          ? 'mB'
          : 'items'
      const destination =
        method.name === 'notConsumable'
          ? recipe.catalysts
          : method.name.includes('Output') || method.name === 'outputFluids' || method.name === 'fluidOutputs'
            ? recipe.outputs
            : recipe.inputs
      if (method.name === 'itemOutputsRanged') {
        const stack = parseStack(flat[0], 'items')
        if (stack && typeof flat[1] === 'number' && typeof flat[2] === 'number') {
          destination.push({
            ...stack,
            amount: flat[2],
            minAmount: flat[1],
            maxAmount: flat[2],
            chance: null,
          })
          recipe.unresolved.push(`Ranged output ${stack.id}: ${flat[1]}–${flat[2]} items`)
        } else
          recipe.unresolved.push(
            `itemOutputsRanged: ${method.args.map((arg) => arg.getText(ast)).join(', ')}`,
          )
        continue
      }
      for (const value of flat) {
        const stack = parseStack(value, unit)
        if (stack)
          destination.push({
            ...stack,
            chance: method.name.startsWith('chanced') ? Number(flat[1]) / 10000 : null,
          })
        else recipe.unresolved.push(`${method.name}: ${String(value)}`)
        if (stack?.nbt) recipe.unresolved.push(`${method.name}: NBT payload`)
        if (method.name.startsWith('chanced')) break
      }
      if (method.name.startsWith('chanced') && flat[2])
        recipe.unresolved.push(`${method.name}: chance changes with machine tier`)
    }
  }
  if (base.idNode && !gameId) recipe.unresolved.push(`id: ${base.idNode.getText(ast)}`)
  if (!recipe.outputs.length) recipe.unresolved.push('No static output captured')
  if (base.family === 'gtceu' && recipe.durationTicks == null)
    recipe.unresolved.push('No static duration captured')
  if (base.family === 'gtceu' && recipe.eut == null) recipe.unresolved.push('No static EU/t captured')
  return recipe
}

function parseResearchBuilder(node, ast, constants, relativePath, sourceId) {
  const values = node.arguments.map((argument) => staticValue(argument, ast, constants))
  const [machine, recId, itemInputs, fluidInputs, itemOutputs, duration, cwuT, , eut, researched] = values
  if (typeof machine !== 'string' || typeof recId !== 'string') return []
  const line = ast.getLineAndCharacterOfPosition(node.getStart(ast)).line + 1
  const parseMany = (values, unit) =>
    (Array.isArray(values) ? values : [values])
      .map((value) => parseStack(value, unit))
      .filter(Boolean)
      .map((value) => ({ ...value, chance: null }))
  const inputs = [...parseMany(itemInputs, 'items'), ...parseMany(fluidInputs, 'mB')]
  const outputs = parseMany(itemOutputs, 'items')
  const unresolved = []
  const expectedCount = (value) => (Array.isArray(value) ? value.length : value ? 1 : 0)
  if (itemInputs === undefined || fluidInputs === undefined)
    unresolved.push('Research builder inputs not fully resolved')
  if (inputs.length !== expectedCount(itemInputs) + expectedCount(fluidInputs))
    unresolved.push('Research builder inputs not fully resolved')
  if (itemOutputs === undefined || outputs.length !== expectedCount(itemOutputs))
    unresolved.push('Research builder outputs not fully resolved')
  if (typeof duration !== 'number') unresolved.push('Research builder duration not resolved')
  if (typeof eut !== 'number') unresolved.push('Research builder EU/t not resolved')
  const main = {
    key: `${sourceId}:${relativePath}:${line}:research-builder`,
    sourceId,
    sourcePath: relativePath,
    sourceLine: line,
    gameId: `start:${recId.toLowerCase()}`,
    family: 'gtceu',
    machine,
    inputs,
    outputs,
    catalysts: [],
    durationTicks: typeof duration === 'number' ? duration : null,
    eut: typeof eut === 'number' ? eut : null,
    circuit: null,
    unresolved,
  }
  const dataItem =
    typeof cwuT === 'number'
      ? cwuT >= 320
        ? 'start_core:component_data_core'
        : cwuT >= 160
          ? 'start_core:data_dna_disk'
          : cwuT >= 32
            ? 'gtceu:data_module'
            : 'gtceu:data_orb'
      : null
  const research = {
    ...main,
    key: `${main.key}:research-station`,
    gameId: typeof researched === 'string' ? `start:1_x_${researched.replace(':', '_')}` : null,
    machine: 'research_station',
    inputs: [
      ...(dataItem ? parseMany(dataItem, 'items') : []),
      ...(typeof researched === 'string' ? parseMany(researched, 'items') : []),
    ],
    outputs: dataItem ? parseMany(dataItem, 'items') : [],
    durationTicks: null,
    unresolved: ['Research data item has NBT payload and CWU-based timing'],
  }
  return [main, research]
}

export async function importKubeJs(sourceRoot, sourceId, packMode = 'default') {
  const scriptsRoot = path.join(sourceRoot, 'kubejs', 'server_scripts')
  const files = await jsFiles(scriptsRoot, packMode)
  const startupFiles = await jsFiles(path.join(sourceRoot, 'kubejs', 'startup_scripts'), packMode).catch(
    (error) => {
      if (error.code === 'ENOENT') return []
      throw error
    },
  )
  const globalBindings = new Map()
  for (const file of [...startupFiles, ...files]) {
    const text = await readFile(file, 'utf8')
    const ast = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
    function collect(node) {
      if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.EqualsToken) {
        const name = memberPath(node.left)
        if (name?.startsWith('global.')) {
          const value = staticValue(node.right, ast, globalBindings)
          if (value !== undefined) globalBindings.set(name, value)
          else if (ts.isArrowFunction(node.right) || ts.isFunctionExpression(node.right))
            globalBindings.set(name, node.right)
        }
      }
      ts.forEachChild(node, collect)
    }
    collect(ast)
  }
  const recipes = []
  const diagnostics = []
  for (const file of files) {
    const text = await readFile(file, 'utf8')
    const relativePath = path.relative(sourceRoot, file).replaceAll(path.sep, '/')
    const ast = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
    const { constants, aliases, helpers } = collectBindings(ast, globalBindings)
    let count = 0
    function visit(node, bindings = constants, depth = 0, uncertain = false) {
      if (depth > 12) return
      if (ts.isFunctionDeclaration(node)) return
      if (
        ts.isBinaryExpression(node) &&
        memberPath(node.left) === 'global.researchBuilder' &&
        (ts.isArrowFunction(node.right) || ts.isFunctionExpression(node.right))
      )
        return
      if (ts.isIfStatement(node)) {
        const condition = staticValue(node.expression, ast, bindings)
        if (condition !== undefined) {
          const branch = condition ? node.thenStatement : node.elseStatement
          if (branch) visit(branch, bindings, depth + 1, uncertain)
        } else {
          visit(node.thenStatement, bindings, depth + 1, true)
          if (node.elseStatement) visit(node.elseStatement, bindings, depth + 1, true)
        }
        return
      }
      if (
        ts.isVariableDeclaration(node) &&
        node.initializer &&
        (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))
      )
        return
      if (ts.isVariableDeclaration(node) && !ts.isIdentifier(node.name) && node.initializer) {
        const value = staticValue(node.initializer, ast, bindings)
        if (value !== undefined) bindPattern(node.name, value, bindings)
      }
      if (
        ts.isForOfStatement(node) &&
        ts.isVariableDeclarationList(node.initializer) &&
        node.initializer.declarations.length === 1
      ) {
        const values = staticValue(node.expression, ast, bindings)
        const variable = node.initializer.declarations[0].name
        if (Array.isArray(values) && ts.isIdentifier(variable)) {
          for (const value of values)
            visit(node.statement, new Map([...bindings, [variable.text, value]]), depth + 1, uncertain)
          return
        }
      }
      if (ts.isForStatement(node)) {
        const iterations = numericIterations(node, ast, bindings)
        if (iterations) {
          for (const value of iterations.values)
            visit(node.statement, new Map([...bindings, [iterations.name, value]]), depth + 1, uncertain)
          return
        }
      }
      if (ts.isCallExpression(node)) {
        if (
          (ts.isIdentifier(node.expression) &&
            memberPath(bindings.get(node.expression.text)) === 'global.researchBuilder') ||
          memberPath(node.expression) === 'global.researchBuilder'
        ) {
          const parsed = parseResearchBuilder(node, ast, bindings, relativePath, sourceId)
          for (const recipe of parsed) {
            if (uncertain) recipe.unresolved.push('Conditional branch could not be resolved statically')
            recipe.key = `${recipe.key}:${count}`
            recipes.push(recipe)
            count++
          }
          return
        }
        if (ts.isPropertyAccessExpression(node.expression) && node.expression.name.text === 'forEach') {
          const values = staticValue(node.expression.expression, ast, bindings)
          const callback = node.arguments[0]
          if (
            Array.isArray(values) &&
            callback &&
            (ts.isArrowFunction(callback) || ts.isFunctionExpression(callback)) &&
            callback.parameters.length > 0 &&
            ts.isIdentifier(callback.parameters[0].name)
          ) {
            const param = callback.parameters[0].name.text
            for (const value of values)
              visit(callback.body, new Map([...bindings, [param, value]]), depth + 1, uncertain)
            return
          }
        }
        if (ts.isIdentifier(node.expression) && helpers.has(node.expression.text)) {
          const helper = helpers.get(node.expression.text)
          const args = node.arguments.map((arg) => staticValue(arg, ast, bindings))
          const inner = new Map(bindings)
          helper.parameters.forEach((param, index) => {
            if (ts.isIdentifier(param.name)) inner.set(param.name.text, args[index])
          })
          visit(helper.body, inner, depth + 1, uncertain)
          return
        }
        const parent = node.parent
        const extendsChain =
          (ts.isPropertyAccessExpression(parent) || ts.isElementAccessExpression(parent)) &&
          parent.expression === node
        if (!extendsChain) {
          const base = recipeBase(node, ast, aliases, bindings)
          if (base) {
            const line = ast.getLineAndCharacterOfPosition(node.getStart(ast)).line + 1
            const recipe = parseRecipe(base, ast, bindings, relativePath, line, sourceId)
            if (uncertain) recipe.unresolved.push('Conditional branch could not be resolved statically')
            recipe.key = `${recipe.key}:${count}`
            recipes.push(recipe)
            count++
          }
        }
      }
      ts.forEachChild(node, (child) => visit(child, bindings, depth, uncertain))
    }
    visit(ast)
    if (ast.parseDiagnostics.length)
      diagnostics.push({ file: relativePath, issue: 'JavaScript parse diagnostics' })
    const scanner = ts.createScanner(ts.ScriptTarget.Latest, true, ts.LanguageVariant.Standard, text)
    let activeText = ''
    for (let token = scanner.scan(); token !== ts.SyntaxKind.EndOfFileToken; token = scanner.scan())
      activeText += scanner.getTokenText()
    if (
      count === 0 &&
      !relativePath.includes('/utils/helpers/') &&
      /event\.recipes\.|event\.shaped\(|event\.shapeless\(/.test(activeText)
    )
      diagnostics.push({ file: relativePath, issue: 'Recipe declarations not captured' })
  }
  return { recipes, diagnostics, fileCount: files.length }
}
