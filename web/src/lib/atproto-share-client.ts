import {
  Client,
  ClientResponseError,
  retryFetchHandler,
  simpleFetchHandler,
  type FetchHandler,
} from '@atcute/client'
import type {} from '@atcute/atproto'
import type { ActorIdentifier } from '@atcute/lexicons'
import {
  parseAtUri,
  parseShareRecord,
  type ShareReference,
  type ShareSnapshot,
} from './share'

const DEFAULT_PUBLIC_SERVICE = 'https://public.api.bsky.app'

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
}

export class AtprotoShareClient {
  private readonly client: Client

  constructor(options: AtprotoShareClientOptions = {}) {
    const handler =
      options.handler ??
      retryFetchHandler({
        handler: simpleFetchHandler({
          service: options.service ?? DEFAULT_PUBLIC_SERVICE,
        }),
        maxRetries: 2,
      })
    this.client = new Client({ handler })
  }

  async fetchRecord(reference: ShareReference | string): Promise<ShareSnapshot> {
    const parsed = typeof reference === 'string' ? parseAtUri(reference) : reference
    const reassembled = `at://${parsed.repo}/${parsed.collection}/${parsed.rkey}`
    // TODO: add proper lexicon
    const response = await this.client.get('com.bad-example.repo.getUriRecord' as any, {
      params: {
        at_uri: reassembled
      },
    })

    if (!response.ok) {
      throw new AtprotoShareError(
        response.data.message ?? `atproto returned ${response.data.error}`,
        {
          status: response.status,
          errorName: response.data.error,
        },
      )
    }

    try {
      return parseShareRecord(response.data.value, parsed.collection)
    } catch (error) {
      if (error instanceof Error) {
        throw new AtprotoShareError(`Invalid Ginny share record: ${error.message}`)
      }
      throw new AtprotoShareError('Invalid Ginny share record')
    }
  }

  async fetchAtUri(uri: string): Promise<ShareSnapshot> {
    return this.fetchRecord(parseAtUri(uri))
  }
}

export const atprotoShareClient = new AtprotoShareClient()

export function isAtprotoNotFound(error: unknown): boolean {
  return error instanceof ClientResponseError && error.status === 404
}
