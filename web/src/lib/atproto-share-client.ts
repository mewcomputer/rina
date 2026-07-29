import {
  Client,
  ClientResponseError,
  retryFetchHandler,
  simpleFetchHandler,
  type FetchHandler,
} from '@atcute/client'
import type {} from '@atcute/atproto'
import {
  parseAtUri,
  parseShareRecord,
  type ShareReference,
  type ShareSnapshot,
} from './share'

const DEFAULT_PUBLIC_SERVICE = 'https://slingshot.firehose.stream'
const GET_URI_RECORD = 'com.bad-example.repo.getUriRecord'

export class AtprotoShareError extends Error {
  readonly status?: number
  readonly errorName?: string

  constructor(message: string, options: { status?: number; errorName?: string } = {}) {
    super(message)
    this.name = 'AtprotoShareError'
    this.status = options.status
    this.errorName = options.errorName
  }
}

export type AtprotoShareClientOptions = {
  service?: string | URL
  handler?: FetchHandler
  fetch?: typeof globalThis.fetch
}

export class AtprotoShareClient {
  private readonly client: Client

  constructor(options: AtprotoShareClientOptions = {}) {
    const handler =
      options.handler ??
      retryFetchHandler({
        handler: simpleFetchHandler({
          service: options.service ?? DEFAULT_PUBLIC_SERVICE,
          fetch: options.fetch,
        }),
        maxRetries: 2,
      })
    this.client = new Client({ handler })
  }

  async fetchRecord(reference: ShareReference | string): Promise<ShareSnapshot> {
    const parsed = typeof reference === 'string' ? parseAtUri(reference) : reference
    const reassembled = `at://${parsed.repo}/${parsed.collection}/${parsed.rkey}`
    const response = await this.client.get(GET_URI_RECORD as any, {
      params: {
        at_uri: reassembled
      },
    })

    if (!response.ok) {
      const errorData = response.data as { error?: string; message?: string }
      throw new AtprotoShareError(
        errorData.message ?? `atproto returned ${errorData.error}`,
        {
          status: response.status,
          errorName: errorData.error,
        },
      )
    }

    try {
      const recordData = response.data as { value: unknown }
      return parseShareRecord(recordData.value, parsed.collection)
    } catch (error) {
      if (error instanceof Error) {
        throw new AtprotoShareError(`Invalid Rina share record: ${error.message}`)
      }
      throw new AtprotoShareError('Invalid Rina share record')
    }
  }

  async fetchAtUri(uri: string): Promise<ShareSnapshot> {
    const snapshot = await this.fetchRecord(parseAtUri(uri))
    if (snapshot.kind !== 'conversation' || snapshot.artefactReferences.length === 0) {
      return snapshot
    }

    const referencedSnapshots = await Promise.all(
      snapshot.artefactReferences.map((reference) => this.fetchRecord(reference.uri)),
    )
    const artefacts = referencedSnapshots.flatMap((referenced) => {
      if (referenced.kind !== 'artefact') {
        throw new AtprotoShareError('Referenced record is not an artefact.')
      }
      return referenced.artefacts
    })

    return { ...snapshot, artefacts }
  }
}

export const atprotoShareClient = new AtprotoShareClient()

export function isAtprotoNotFound(error: unknown): boolean {
  return error instanceof ClientResponseError && error.status === 404
}
