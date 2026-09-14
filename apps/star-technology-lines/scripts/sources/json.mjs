import { readFile } from 'node:fs/promises'
import { validateCatalog } from '../catalog-schema.mjs'

export async function importJsonCatalog(path) {
  return validateCatalog(JSON.parse(await readFile(path, 'utf8')))
}
