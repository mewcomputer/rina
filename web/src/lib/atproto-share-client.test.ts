import { describe, expect, it } from 'vitest'
import {
  AtprotoShareClient,
  AtprotoShareError,
} from './atproto-share-client'

const reference = {
  repo: 'did:plc:example123',
  collection: 'computer.mew.rina.share' as const,
  rkey: '3mabc234xyzab',
}

const record = {
  $type: 'computer.mew.rina.share',
  schemaVersion: 1,
  title: 'A public note',
  createdAt: '2026-07-29T18:00:00.000Z',
  snapshot: {
    kind: 'artefact',
    messages: [],
    artefacts: [
      {
        title: 'A public note',
        kind: 'document',
        source: 'The source of the shared note.',
      },
    ],
    relationships: [],
  },
}

describe('AtprotoShareClient', () => {
  it('fetches and parses a public record through atcute', async () => {
    const client = new AtprotoShareClient({
      handler: async (pathname) => {
        expect(pathname).toContain('com.atproto.repo.getRecord')
        expect(pathname).toContain('repo=did%3Aplc%3Aexample123')
        return Response.json({
          uri: `at://${reference.repo}/${reference.collection}/${reference.rkey}`,
          cid: 'bafyexample',
          value: record,
        })
      },
    })

    await expect(client.fetchRecord(reference)).resolves.toMatchObject({
      title: 'A public note',
      kind: 'artefact',
      artefacts: [
        expect.objectContaining({ source: 'The source of the shared note.' }),
      ],
    })
  })

  it('turns an atproto error response into a user-facing typed error', async () => {
    const client = new AtprotoShareClient({
      handler: async () =>
        Response.json(
          { error: 'RecordNotFound', message: 'That share no longer exists.' },
          { status: 404 },
        ),
    })

    await expect(client.fetchRecord(reference)).rejects.toEqual(
      expect.objectContaining<Partial<AtprotoShareError>>({
        name: 'AtprotoShareError',
        status: 404,
        errorName: 'RecordNotFound',
        message: 'That share no longer exists.',
      }),
    )
  })
})
