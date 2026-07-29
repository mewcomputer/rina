import { describe, expect, it } from 'vitest'
import {
  ARTEFACT_COLLECTION,
  CONVERSATION_COLLECTION,
  SHARE_COLLECTION,
  ShareParseError,
  parseAtUri,
  parseShareRecord,
} from './share'

const validRecord = {
  $type: SHARE_COLLECTION,
  schemaVersion: 1,
  title: 'A small research note',
  createdAt: '2026-07-29T18:00:00.000Z',
  snapshot: {
    kind: 'conversation',
    messages: [
      {
        role: 'user',
        blocks: [{ kind: 'text', payload: 'What should I investigate next?' }],
      },
      {
        role: 'assistant',
        blocks: [
          {
            kind: 'markdown',
            payload: 'Start with the primary sources.',
            attributes: { emphasis: 'high' },
          },
        ],
      },
    ],
    artefacts: [],
    relationships: [],
  },
}

describe('parseAtUri', () => {
  it('extracts the durable repository, collection, and record key', () => {
    expect(
      parseAtUri(
        'at://did:plc:example123/computer.mew.rina.share/3mabc123xyz',
      ),
    ).toEqual({
      repo: 'did:plc:example123',
      collection: SHARE_COLLECTION,
      rkey: '3mabc123xyz',
    })
  })

  it('rejects handles, queries, and non-share collections that are unsafe to route', () => {
    expect(() => parseAtUri('https://example.com/share')).toThrow(ShareParseError)
    expect(() =>
      parseAtUri('at://alice.example/computer.mew.rina.share/3mabc123xyz?x=1'),
    ).toThrow('queries and fragments are not supported')
    expect(() =>
      parseAtUri('at://did:plc:example123/app.bsky.feed.post/3mabc123xyz'),
    ).toThrow('Unsupported collection')
  })
})

describe('parseShareRecord', () => {
  it('parses a typed conversation record', () => {
    expect(
      parseShareRecord(
        {
          $type: CONVERSATION_COLLECTION,
          snapshot: {
            schemaVersion: 1,
            title: 'Accessible card review',
            createdAt: '2026-07-29T18:00:00.000Z',
            updatedAt: '2026-07-29T18:01:00.000Z',
            messages: [
              {
                id: 'message-1',
                role: 'assistant',
                blocks: [
                  {
                    id: 'block-1',
                    kind: 'markdown',
                    payload: 'Use a visible focus ring.',
                    attributes: {},
                  },
                ],
                createdAt: '2026-07-29T18:00:00.000Z',
              },
            ],
          },
        },
        CONVERSATION_COLLECTION,
      ),
    ).toMatchObject({
      title: 'Accessible card review',
      kind: 'conversation',
      messages: [{ role: 'assistant', blocks: [{ kind: 'markdown' }] }],
      artefacts: [],
    })
  })

  it('parses a typed artefact record', () => {
    expect(
      parseShareRecord(
        {
          $type: ARTEFACT_COLLECTION,
          snapshot: {
            schemaVersion: 1,
            title: 'Accessible card',
            kind: 'code',
            createdAt: '2026-07-29T18:00:00.000Z',
            updatedAt: '2026-07-29T18:01:00.000Z',
            source: '<button>Save</button>',
            renderedContent: '<button>Save</button>',
            metadata: { language: 'html' },
          },
        },
        ARTEFACT_COLLECTION,
      ),
    ).toMatchObject({
      title: 'Accessible card',
      kind: 'artefact',
      artefacts: [
        expect.objectContaining({
          kind: 'code',
          source: '<button>Save</button>',
        }),
      ],
    })
  })

  it('normalizes a valid record without losing block attributes', () => {
    expect(parseShareRecord(validRecord)).toEqual({
      schemaVersion: 1,
      title: 'A small research note',
      createdAt: '2026-07-29T18:00:00.000Z',
      kind: 'conversation',
      messages: [
        {
          role: 'user',
          blocks: [
            {
              kind: 'text',
              payload: 'What should I investigate next?',
              attributes: {},
              isComplete: true,
            },
          ],
        },
        {
          role: 'assistant',
          blocks: [
            {
              kind: 'markdown',
              payload: 'Start with the primary sources.',
              attributes: { emphasis: 'high' },
              isComplete: true,
            },
          ],
        },
      ],
      artefacts: [],
      relationships: [],
    })
  })

  it('rejects a future schema version instead of guessing', () => {
    expect(() =>
      parseShareRecord({ ...validRecord, schemaVersion: 2 }),
    ).toThrow('Unsupported share schema version: 2')
  })

  it('rejects oversized and malformed content at the trust boundary', () => {
    const malformed = {
      ...validRecord,
      snapshot: {
        ...validRecord.snapshot,
        messages: [{ role: 'assistant', blocks: [{ kind: 'markdown' }] }],
      },
    }
    expect(() => parseShareRecord(malformed)).toThrow('payload must be a string')

    expect(() =>
      parseShareRecord({
        ...validRecord,
        title: 'x'.repeat(201),
      }),
    ).toThrow('title is too long')
  })
})
