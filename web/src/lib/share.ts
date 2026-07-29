export const SHARE_COLLECTION = 'computer.mew.rina.share'
export const SHARE_SCHEMA_VERSION = 1

const MAX_TITLE_LENGTH = 200
const MAX_TEXT_LENGTH = 1_000_000
const MAX_MESSAGES = 1_000
const MAX_BLOCKS_PER_MESSAGE = 200
const MAX_ARTEFACTS = 100
const MAX_RELATIONSHIPS = 500
const MAX_ATTRIBUTES = 100

const messageRoles = new Set(['user', 'assistant', 'system', 'tool'])
const artefactKinds = new Set(['document', 'code', 'web', 'inlineWeb'])
const relationshipPredicates = new Set([
  'relatedTo',
  'derivedFrom',
  'revisionOf',
  'references',
  'supportedBy',
])

export type ShareKind = 'conversation' | 'artefact'

export type ShareBlock = {
  id?: string
  kind: string
  payload: string
  attributes: Record<string, string>
  isComplete: boolean
}

export type ShareMessage = {
  id?: string
  role: 'user' | 'assistant' | 'system' | 'tool'
  blocks: ShareBlock[]
  createdAt?: string
}

export type ShareArtefact = {
  id?: string
  title: string
  kind: 'document' | 'code' | 'web' | 'inlineWeb'
  source: string
  renderedContent?: string
  metadata: Record<string, string>
}

export type ShareRelationship = {
  source: string
  predicate:
    | 'relatedTo'
    | 'derivedFrom'
    | 'revisionOf'
    | 'references'
    | 'supportedBy'
  target: string
  attributes: Record<string, string>
}

export type ShareSnapshot = {
  schemaVersion: typeof SHARE_SCHEMA_VERSION
  title: string
  createdAt: string
  kind: ShareKind
  messages: ShareMessage[]
  artefacts: ShareArtefact[]
  relationships: ShareRelationship[]
}

export type ShareReference = {
  repo: string
  collection: typeof SHARE_COLLECTION
  rkey: string
}

export type ShareParseErrorCode =
  | 'invalidReference'
  | 'invalidRecord'
  | 'unsupportedVersion'
  | 'invalidField'
  | 'tooLarge'

export class ShareParseError extends Error {
  readonly code: ShareParseErrorCode

  constructor(code: ShareParseErrorCode, message: string) {
    super(message)
    this.name = 'ShareParseError'
    this.code = code
  }
}

export function parseAtUri(input: string): ShareReference {
  if (!input.startsWith('at://')) {
    throw new ShareParseError(
      'invalidReference',
      'Share references must use the at:// scheme',
    )
  }

  const value = input.slice('at://'.length)
  if (value.includes('?') || value.includes('#')) {
    throw new ShareParseError(
      'invalidReference',
      'queries and fragments are not supported in share references',
    )
  }

  const [repo, collection, rkey, ...extra] = value.split('/')
  if (!repo || !repo.startsWith('did:')) {
    throw new ShareParseError(
      'invalidReference',
      'share references must use a durable DID repository',
    )
  }
  if (!collection || !rkey || extra.length > 0) {
    throw new ShareParseError(
      'invalidReference',
      'share references must include one collection and record key',
    )
  }
  if (collection !== SHARE_COLLECTION) {
    throw new ShareParseError(
      'invalidReference',
      `Unsupported collection: ${collection}`,
    )
  }
  if (!/^[A-Za-z0-9._~-]{1,512}$/.test(rkey)) {
    throw new ShareParseError('invalidReference', 'record key is invalid')
  }

  return {
    repo,
    collection,
    rkey,
  }
}

export function parseShareRecord(input: unknown): ShareSnapshot {
  const record = asRecord(input, 'record')
  const type = optionalString(record.$type, '$type')
  if (type !== undefined && type !== SHARE_COLLECTION) {
    throw new ShareParseError(
      'invalidRecord',
      `Unsupported share record type: ${type}`,
    )
  }

  const version = record.schemaVersion
  if (typeof version !== 'number' || !Number.isInteger(version)) {
    throw new ShareParseError(
      'invalidField',
      'schemaVersion must be an integer',
    )
  }
  if (version !== SHARE_SCHEMA_VERSION) {
    throw new ShareParseError(
      'unsupportedVersion',
      `Unsupported share schema version: ${version}`,
    )
  }

  const title = requiredString(record.title, 'title', MAX_TITLE_LENGTH)
  const createdAt = requiredDate(record.createdAt, 'createdAt')
  const snapshot = asRecord(record.snapshot, 'snapshot')
  const kind = requiredEnum(snapshot.kind, 'snapshot.kind', [
    'conversation',
    'artefact',
  ]) as ShareKind

  return {
    schemaVersion: SHARE_SCHEMA_VERSION,
    title,
    createdAt,
    kind,
    messages: parseMessages(snapshot.messages),
    artefacts: parseArtefacts(snapshot.artefacts),
    relationships: parseRelationships(snapshot.relationships),
  }
}

function parseMessages(input: unknown): ShareMessage[] {
  const values = optionalArray(input, 'snapshot.messages')
  if (values.length > MAX_MESSAGES) {
    throw new ShareParseError(
      'tooLarge',
      `snapshot.messages exceeds the limit of ${MAX_MESSAGES} items`,
    )
  }

  return values.map((value, index) => {
    const message = asRecord(value, `snapshot.messages[${index}]`)
    const role = requiredEnum(message.role, `snapshot.messages[${index}].role`, [
      ...messageRoles,
    ]) as ShareMessage['role']
    const blocks = optionalArray(
      message.blocks,
      `snapshot.messages[${index}].blocks`,
    )
    if (blocks.length > MAX_BLOCKS_PER_MESSAGE) {
      throw new ShareParseError(
        'tooLarge',
        `message ${index} has too many blocks`,
      )
    }

    const parsed: ShareMessage = {
      role,
      blocks: blocks.map((block, blockIndex) =>
        parseBlock(block, `snapshot.messages[${index}].blocks[${blockIndex}]`),
      ),
    }
    const id = optionalString(message.id, `snapshot.messages[${index}].id`)
    const createdAt = optionalDate(
      message.createdAt,
      `snapshot.messages[${index}].createdAt`,
    )
    if (id !== undefined) parsed.id = id
    if (createdAt !== undefined) parsed.createdAt = createdAt
    return parsed
  })
}

function parseBlock(input: unknown, path: string): ShareBlock {
  const block = asRecord(input, path)
  const parsed: ShareBlock = {
    kind: requiredString(block.kind, `${path}.kind`, 100),
    payload: requiredString(block.payload, `${path}.payload`, MAX_TEXT_LENGTH),
    attributes: parseAttributes(block.attributes, `${path}.attributes`),
    isComplete: optionalBoolean(block.isComplete, `${path}.isComplete`) ?? true,
  }
  const id = optionalString(block.id, `${path}.id`)
  if (id !== undefined) parsed.id = id
  return parsed
}

function parseArtefacts(input: unknown): ShareArtefact[] {
  const values = optionalArray(input, 'snapshot.artefacts')
  if (values.length > MAX_ARTEFACTS) {
    throw new ShareParseError(
      'tooLarge',
      `snapshot.artefacts exceeds the limit of ${MAX_ARTEFACTS} items`,
    )
  }

  return values.map((value, index) => {
    const artefact = asRecord(value, `snapshot.artefacts[${index}]`)
    const parsed: ShareArtefact = {
      title: requiredString(
        artefact.title,
        `snapshot.artefacts[${index}].title`,
        MAX_TITLE_LENGTH,
      ),
      kind: requiredEnum(
        artefact.kind,
        `snapshot.artefacts[${index}].kind`,
        [...artefactKinds],
      ) as ShareArtefact['kind'],
      source: requiredString(
        artefact.source,
        `snapshot.artefacts[${index}].source`,
        MAX_TEXT_LENGTH,
      ),
      metadata: parseAttributes(
        artefact.metadata,
        `snapshot.artefacts[${index}].metadata`,
      ),
    }
    const id = optionalString(artefact.id, `snapshot.artefacts[${index}].id`)
    const renderedContent = optionalString(
      artefact.renderedContent,
      `snapshot.artefacts[${index}].renderedContent`,
      MAX_TEXT_LENGTH,
    )
    if (id !== undefined) parsed.id = id
    if (renderedContent !== undefined) parsed.renderedContent = renderedContent
    return parsed
  })
}

function parseRelationships(input: unknown): ShareRelationship[] {
  const values = optionalArray(input, 'snapshot.relationships')
  if (values.length > MAX_RELATIONSHIPS) {
    throw new ShareParseError(
      'tooLarge',
      `snapshot.relationships exceeds the limit of ${MAX_RELATIONSHIPS} items`,
    )
  }

  return values.map((value, index) => {
    const relationship = asRecord(value, `snapshot.relationships[${index}]`)
    return {
      source: requiredString(
        relationship.source,
        `snapshot.relationships[${index}].source`,
        512,
      ),
      predicate: requiredEnum(
        relationship.predicate,
        `snapshot.relationships[${index}].predicate`,
        [...relationshipPredicates],
      ) as ShareRelationship['predicate'],
      target: requiredString(
        relationship.target,
        `snapshot.relationships[${index}].target`,
        512,
      ),
      attributes: parseAttributes(
        relationship.attributes,
        `snapshot.relationships[${index}].attributes`,
      ),
    }
  })
}

function asRecord(input: unknown, path: string): Record<string, unknown> {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    throw new ShareParseError('invalidRecord', `${path} must be an object`)
  }
  return input as Record<string, unknown>
}

function optionalArray(input: unknown, path: string): unknown[] {
  if (input === undefined) return []
  if (!Array.isArray(input)) {
    throw new ShareParseError('invalidField', `${path} must be an array`)
  }
  return input
}

function requiredString(
  input: unknown,
  path: string,
  maximumLength: number,
): string {
  if (typeof input !== 'string') {
    throw new ShareParseError('invalidField', `${path} must be a string`)
  }
  if (input.length > maximumLength) {
    throw new ShareParseError(
      'tooLarge',
      `${path} is too long (maximum ${maximumLength} characters)`,
    )
  }
  if (input.trim().length === 0) {
    throw new ShareParseError('invalidField', `${path} must not be empty`)
  }
  return input
}

function optionalString(
  input: unknown,
  path: string,
  maximumLength = 512,
): string | undefined {
  if (input === undefined) return undefined
  return requiredString(input, path, maximumLength)
}

function requiredDate(input: unknown, path: string): string {
  const value = requiredString(input, path, 100)
  if (Number.isNaN(Date.parse(value))) {
    throw new ShareParseError('invalidField', `${path} must be an ISO date`)
  }
  return value
}

function optionalDate(input: unknown, path: string): string | undefined {
  if (input === undefined) return undefined
  return requiredDate(input, path)
}

function optionalBoolean(input: unknown, path: string): boolean | undefined {
  if (input === undefined) return undefined
  if (typeof input !== 'boolean') {
    throw new ShareParseError('invalidField', `${path} must be a boolean`)
  }
  return input
}

function requiredEnum(
  input: unknown,
  path: string,
  allowed: string[],
): string {
  const value = requiredString(input, path, 100)
  if (!allowed.includes(value)) {
    throw new ShareParseError(
      'invalidField',
      `${path} must be one of: ${allowed.join(', ')}`,
    )
  }
  return value
}

function parseAttributes(input: unknown, path: string): Record<string, string> {
  if (input === undefined) return {}
  const record = asRecord(input, path)
  const entries = Object.entries(record)
  if (entries.length > MAX_ATTRIBUTES) {
    throw new ShareParseError('tooLarge', `${path} has too many attributes`)
  }
  return Object.fromEntries(
    entries.map(([key, value]) => [
      requiredString(key, `${path} key`, 100),
      requiredString(value, `${path}.${key}`, MAX_TEXT_LENGTH),
    ]),
  )
}
