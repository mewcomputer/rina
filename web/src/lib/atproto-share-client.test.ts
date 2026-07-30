import { describe, expect, it } from 'vitest'
import {
  AtprotoShareClient,
  AtprotoShareError,
} from './atproto-share-client'
import { ARTEFACT_COLLECTION, CONVERSATION_COLLECTION } from './share'

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
    const requestedURLs: string[] = []
    const client = new AtprotoShareClient({
      service: 'https://slingshot.firehose.stream',
      fetch: async (input) => {
        requestedURLs.push(String(input))
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

    expect(requestedURLs).toEqual([
      'https://slingshot.firehose.stream/xrpc/com.bad-example.repo.getUriRecord?at_uri=at%3A%2F%2Fdid%3Aplc%3Aexample123%2Fcomputer.mew.rina.share%2F3mabc234xyzab',
    ])
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

  it('resolves artefacts referenced by a typed conversation', async () => {
    const conversationURI = `at://${reference.repo}/${CONVERSATION_COLLECTION}/3mabc234xyzab`
    const artefactURI = `at://${reference.repo}/${ARTEFACT_COLLECTION}/3nabc234xyzab`
    const client = new AtprotoShareClient({
      handler: async (pathname) => {
        if (!pathname.includes('3nabc234xyzab')) {
          return Response.json({
            uri: conversationURI,
            cid: 'bafyconversation',
            value: {
              $type: CONVERSATION_COLLECTION,
              snapshot: {
                schemaVersion: 1,
                title: 'Shared session',
                createdAt: '2026-07-29T18:00:00.000Z',
                updatedAt: '2026-07-29T18:01:00.000Z',
                messages: [],
                artefacts: [
                  {
                    id: '3aaaaaaaaaaaa',
                    revisionID: '3bbbbbbbbbbbb',
                    uri: artefactURI,
                  },
                ],
              },
            },
          })
        }
        return Response.json({
          uri: artefactURI,
          cid: 'bafyartefact',
          value: {
            $type: ARTEFACT_COLLECTION,
            snapshot: {
              schemaVersion: 1,
              id: '3aaaaaaaaaaaa',
              revisionID: '3bbbbbbbbbbbb',
              title: 'Shared preview',
              kind: 'inlineWeb',
              createdAt: '2026-07-29T18:00:00.000Z',
              updatedAt: '2026-07-29T18:01:00.000Z',
              source: '<button>Open</button>',
              renderedContent: '<button>Open</button>',
              metadata: {},
            },
          },
        })
      },
    })

    await expect(client.fetchAtUri(conversationURI)).resolves.toMatchObject({
      artefacts: [
        expect.objectContaining({
          title: 'Shared preview',
          kind: 'inlineWeb',
          uri: artefactURI,
        }),
      ],
    })
  })
})
