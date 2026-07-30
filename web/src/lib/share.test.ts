import { describe, expect, it } from 'vitest'
import {
  ARTEFACT_COLLECTION,
  CONVERSATION_COLLECTION,
  SHARE_COLLECTION,
  ShareParseError,
  parseAtUri,
  parseShareRecord,
  referencedArtefactIDs,
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
        'at://did:plc:example123/computer.mew.rina.share/3mabc234xyzab',
      ),
    ).toEqual({
      repo: 'did:plc:example123',
      collection: SHARE_COLLECTION,
      rkey: '3mabc234xyzab',
    })
  })

  it('rejects handles, queries, and non-share collections that are unsafe to route', () => {
    expect(() => parseAtUri('https://example.com/share')).toThrow(ShareParseError)
    expect(() =>
      parseAtUri('at://alice.example/computer.mew.rina.share/3mabc234xyzab?x=1'),
    ).toThrow('queries and fragments are not supported')
    expect(() =>
      parseAtUri('at://did:plc:example123/app.bsky.feed.post/3mabc234xyzab'),
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
            generation: {
              provider: 'Umans',
              model: 'umans-coder',
              thinkingLevel: 'high',
            },
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
                  {
                    id: 'call-1',
                    kind: 'toolCall',
                    payload: '{"q":"focus"}',
                    attributes: { callID: 'call-1', name: 'search_web' },
                  },
                ],
                providerContinuations: [
                  {
                    provider: 'umans',
                    id: 'reasoning-1',
                    kind: 'reasoning',
                    fields: { thinking: 'Check the primary sources.' },
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
      generation: {
        provider: 'Umans',
        model: 'umans-coder',
        thinkingLevel: 'high',
      },
      messages: [
        {
          role: 'assistant',
          blocks: [{ kind: 'markdown' }, { kind: 'toolCall' }],
          providerContinuations: [
            { kind: 'reasoning', fields: { thinking: 'Check the primary sources.' } },
          ],
        },
      ],
      artefacts: [],
    })
  })

  it('validates typed conversation artefact references', () => {
    expect(
      parseShareRecord(
        {
          $type: CONVERSATION_COLLECTION,
          snapshot: {
            schemaVersion: 1,
            title: 'Shared preview',
            createdAt: '2026-07-29T18:00:00.000Z',
            updatedAt: '2026-07-29T18:01:00.000Z',
            messages: [],
            artefacts: [
              {
                id: '3aaaaaaaaaaaa',
                revisionID: '3bbbbbbbbbbbb',
                uri: 'at://did:plc:example/computer.mew.rina.artefact/3mabc234xyzab',
              },
            ],
          },
        },
        CONVERSATION_COLLECTION,
      ),
    ).toMatchObject({
      artefactReferences: [
        {
          id: '3aaaaaaaaaaaa',
          revisionID: '3bbbbbbbbbbbb',
          uri: 'at://did:plc:example/computer.mew.rina.artefact/3mabc234xyzab',
        },
      ],
    })
  })

  it('finds artefacts at their message attachment points', () => {
    const messages = parseShareRecord(
      {
        $type: CONVERSATION_COLLECTION,
        snapshot: {
          schemaVersion: 1,
          title: 'Inline preview',
          createdAt: '2026-07-29T18:00:00.000Z',
          messages: [
            {
              role: 'assistant',
              blocks: [
                {
                  kind: 'markdown',
                  payload: 'Before the preview.',
                },
                {
                  kind: 'artefactReference',
                  payload: '',
                  attributes: { artefactID: '3aaaaaaaaaaaa' },
                },
              ],
            },
          ],
          artefacts: [],
        },
      },
      CONVERSATION_COLLECTION,
    ).messages

    expect([...referencedArtefactIDs(messages)]).toEqual(['3aaaaaaaaaaaa'])
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
          providerContinuations: [],
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
          providerContinuations: [],
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
      artefactReferences: [],
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

  it('allows metadata-only blocks to carry an empty payload', () => {
    expect(
      parseShareRecord({
        $type: CONVERSATION_COLLECTION,
        snapshot: {
          schemaVersion: 1,
          title: 'Artefact reference',
          createdAt: '2026-07-29T18:00:00.000Z',
          updatedAt: '2026-07-29T18:01:00.000Z',
          messages: [
            {
              role: 'assistant',
              blocks: [
                {
                  kind: 'artefactReference',
                  payload: '',
                  attributes: {
                    artefactID: '3aaaaaaaaaaaa',
                    revisionID: '3bbbbbbbbbbbb',
                  },
                },
              ],
            },
          ],
        },
      }, CONVERSATION_COLLECTION),
    ).toMatchObject({
      messages: [{ blocks: [{ kind: 'artefactReference', payload: '' }] }],
    })
  })

  it('drops empty content blocks without dropping the rest of the message', () => {
    expect(
      parseShareRecord({
        $type: CONVERSATION_COLLECTION,
        snapshot: {
          schemaVersion: 1,
          title: 'Search answer',
          createdAt: '2026-07-29T18:00:00.000Z',
          updatedAt: '2026-07-29T18:01:00.000Z',
          messages: [
            {
              role: 'assistant',
              blocks: [
                { kind: 'text', payload: '', attributes: {} },
                { kind: 'citationGroup', payload: '[]', attributes: {} },
              ],
            },
          ],
        },
      }, CONVERSATION_COLLECTION),
    ).toMatchObject({
      messages: [{ blocks: [{ kind: 'citationGroup', payload: '[]' }] }],
    })
  })
})
