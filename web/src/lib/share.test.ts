import { describe, expect, it } from 'vitest'
import {
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
