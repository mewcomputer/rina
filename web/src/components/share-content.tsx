import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { useEffect, useRef, useState } from 'react'
import {
  AlertTriangle,
  Check,
  ChevronRight,
  ExternalLink,
  Link2,
  LoaderCircle,
  Sparkles,
} from 'lucide-react'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import type {
  ShareArtefact,
  ShareBlock,
  ShareGenerationMetadata,
  ShareMessage,
  ShareProviderContinuation,
} from '@/lib/share'
import { parseAtUri } from '@/lib/share'

export function ShareMessageList({
  messages,
  artefacts = [],
}: {
  messages: ShareMessage[]
  artefacts?: ShareArtefact[]
}) {
  const items = []

  for (let index = 0; index < messages.length;) {
    const message = messages[index]
    const calls = message.blocks.filter((block) => block.kind === 'toolCall')

    if (message.role === 'assistant' && calls.length > 0) {
      const results: ShareBlock[] = []
      const citationBlocks = message.blocks.filter(
        (block) => block.kind === 'citationGroup',
      )
      let nextIndex = index + 1

      while (nextIndex < messages.length && messages[nextIndex].role === 'tool') {
        results.push(
          ...messages[nextIndex].blocks.filter(
            (block) => block.kind === 'toolResult',
          ),
        )
        nextIndex += 1
      }

      items.push(
        <ShareMessageCard
          key={message.id ?? `${message.role}-${index}`}
          message={message}
          artefacts={artefacts}
          toolActivity={{ calls, results, citationBlocks }}
        />,
      )
      index = nextIndex
      continue
    }

    if (message.role === 'tool') {
      const results = message.blocks.filter((block) => block.kind === 'toolResult')
      items.push(
        <ShareToolActivityCard
          key={message.id ?? `${message.role}-${index}`}
          calls={[]}
          results={results}
          citationBlocks={[]}
        />,
      )
      index += 1
      continue
    }

    items.push(
      <ShareMessageCard
        key={message.id ?? `${message.role}-${index}`}
        message={message}
        artefacts={artefacts}
      />,
    )
    index += 1
  }

  return items
}

export function ShareGenerationDetails({
  generation,
}: {
  generation?: ShareGenerationMetadata
}) {
  if (!generation) return null
  const values = [generation.provider, generation.model].filter(Boolean)
  if (generation.thinkingLevel) values.push(`Thinking ${generation.thinkingLevel}`)
  if (values.length === 0) return null

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
      {values.map((value, index) => (
        <span key={`${value}-${index}`} className={index === 0 ? 'font-medium text-foreground/80' : undefined}>
          {value}
          {index < values.length - 1 && (
            <span aria-hidden="true" className="ml-3 text-border">·</span>
          )}
        </span>
      ))}
    </div>
  )
}

export function ShareMessageCard({
  message,
  artefacts = [],
  toolActivity,
}: {
  message: ShareMessage
  artefacts?: ShareArtefact[]
  toolActivity?: {
    calls: ShareBlock[]
    results: ShareBlock[]
    citationBlocks: ShareBlock[]
  }
}) {
  const isUser = message.role === 'user'
  const activityCitationIDs = new Set(
    toolActivity?.citationBlocks.map((block) => block.id).filter(Boolean),
  )
  const standaloneCitationBlocks = message.blocks.filter(
    (block) =>
      block.kind === 'citationGroup' && !activityCitationIDs.has(block.id),
  )

  const content = (
    <>
      <ThinkingDisclosure continuations={message.providerContinuations} />
      <div className="typeset typeset-docs max-w-[65ch]">
        {message.blocks.map((block, index) => (
          block.kind === 'artefactReference'
            ? (
              <div
                key={block.id ?? `${block.kind}-${index}`}
                className="not-typeset my-6"
              >
                {(() => {
                  const artefact = artefacts.find(
                    (candidate) => candidate.id === block.attributes.artefactID,
                  )
                  return artefact ? (
                    <ShareArtefactCard artefact={artefact} />
                  ) : (
                    <div className="border border-dashed border-border px-4 py-3 text-sm text-muted-foreground">
                      Shared artefact unavailable.
                    </div>
                  )
                })()}
              </div>
            )
            : block.kind === 'citationGroup' || activityCitationIDs.has(block.id)
              ? null
              : (
                <ShareBlockView
                  key={block.id ?? `${block.kind}-${index}`}
                  block={block}
                />
              )
        ))}
      </div>
      {standaloneCitationBlocks.length > 0 && (
        <ShareCitationGroups blocks={standaloneCitationBlocks} />
      )}
      {toolActivity && (
        <ShareToolActivityCard
          calls={toolActivity.calls}
          results={toolActivity.results}
          citationBlocks={toolActivity.citationBlocks}
        />
      )}
    </>
  )

  return (
    <article
      aria-label={isUser ? 'User message' : 'Assistant message'}
      className={isUser ? 'ml-auto max-w-[88%]' : 'max-w-[94%]'}
    >
      {isUser ? (
        <div className="rounded-2xl border border-border/70 bg-muted/45 px-5 py-5 shadow-sm sm:px-6">
          {content}
        </div>
      ) : (
        <div className="py-1 text-[1rem] leading-7">{content}</div>
      )}
    </article>
  )
}

function ThinkingDisclosure({
  continuations,
}: {
  continuations: ShareProviderContinuation[]
}) {
  const reasoning = continuations.filter(
    (continuation) => continuation.kind === 'reasoning',
  )
  const content = reasoning
    .map(
      (continuation) =>
        continuation.fields.thinking ?? continuation.fields.text ?? '',
    )
    .join('')
  const isRedacted = reasoning.some(
    (continuation) =>
      continuation.fields.data !== undefined
      && continuation.fields.thinking === undefined
      && continuation.fields.text === undefined,
  )

  if (!content && !isRedacted) return null

  return (
    <details className="group mb-5 max-w-[65ch] text-muted-foreground">
      <summary className="flex cursor-pointer list-none items-center gap-2 rounded-lg px-2 py-1.5 text-sm font-medium transition-colors hover:bg-muted/50 marker:hidden">
        <ChevronRight className="size-3.5 transition-transform group-open:rotate-90" />
        <Sparkles className="size-3.5 text-primary/70" />
        <span>Thinking</span>
      </summary>
      <div className="mt-2 rounded-lg bg-muted/35 px-4 py-3 [--color-foreground:var(--muted-foreground)]">
        {content ? (
          <div className="typeset typeset-docs max-w-[65ch] text-sm">
            <MarkdownContent content={content} />
          </div>
        ) : (
          <p className="text-sm">Reasoning is hidden by the provider.</p>
        )}
      </div>
    </details>
  )
}

function ShareToolActivityCard({
  calls,
  results,
  citationBlocks,
}: {
  calls: ShareBlock[]
  results: ShareBlock[]
  citationBlocks: ShareBlock[]
}) {
  if (calls.length === 0 && results.length === 0 && citationBlocks.length === 0) {
    return null
  }

  const activities = pairToolActivity(calls, results)
  const hasError = results.some((result) => result.attributes.isError === 'true')
  const isPending =
    calls.some((call) => !call.isComplete)
    || activities.some(({ result }) => !result)
  const label = toolActivityLabel(
    calls,
    results,
    citationBlocks,
    isPending,
    hasError,
  )
  const StatusIcon = hasError ? AlertTriangle : isPending ? LoaderCircle : Check

  return (
    <details className="group mt-5 max-w-[65ch] rounded-xl border border-border/70 bg-card/35 shadow-sm">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3.5 text-sm font-medium marker:hidden">
        <ChevronRight className="size-3.5 transition-transform group-open:rotate-90" />
        <StatusIcon
          className={[
            'size-3.5',
            hasError
              ? 'text-destructive'
              : isPending
                ? 'animate-spin text-muted-foreground'
                : 'text-primary',
          ].join(' ')}
        />
        {label}
      </summary>
      <div className="space-y-4 border-t border-border/70 px-4 py-4">
        {activities.map(({ call, result }, index) => (
          <div
            key={call.id ?? `${call.attributes.callID ?? 'tool'}-${index}`}
            className="space-y-2"
          >
            <div className="text-xs font-medium uppercase tracking-[0.12em] text-muted-foreground">
              {call.attributes.name || 'Tool'}
            </div>
            {call.payload && (
              <pre className="overflow-x-auto whitespace-pre-wrap rounded-lg bg-background/70 p-3 text-xs leading-5 text-muted-foreground ring-1 ring-inset ring-border/50">
                {call.payload}
              </pre>
            )}
            {result && (
              <div className="space-y-2 border-t border-border/70 pt-3">
                <p
                  className={[
                    'text-xs font-medium',
                    result.attributes.isError === 'true'
                      ? 'text-destructive'
                      : 'text-muted-foreground',
                  ].join(' ')}
                >
                  Result
                </p>
                <pre className="overflow-x-auto whitespace-pre-wrap rounded-lg bg-background/70 p-3 text-xs leading-5 text-muted-foreground ring-1 ring-inset ring-border/50">
                  {result.payload}
                </pre>
              </div>
            )}
          </div>
        ))}
        {citationBlocks.length > 0 && (
          <ShareCitationGroups blocks={citationBlocks} collapsible={false} />
        )}
      </div>
    </details>
  )
}

export function ShareArtefactCard({
  artefact,
  mode = 'preview',
}: {
  artefact: ShareArtefact
  mode?: 'preview' | 'page'
}) {
  const content = artefact.renderedContent ?? artefact.source
  const isDocument = artefact.kind === 'document'
  const isWeb = artefact.kind === 'web' || artefact.kind === 'inlineWeb'
  const fullArtefactPath = artefactPath(artefact.uri)

  if (artefact.kind === 'web' && mode === 'preview' && fullArtefactPath) {
    return (
      <a href={fullArtefactPath} className="group block rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-ring">
        <Card className="overflow-hidden border-border/70 bg-card/35 shadow-sm transition-colors group-hover:bg-card/55">
          <CardHeader className="gap-2 border-b border-border/60 px-5 py-5 sm:px-6">
            <CardTitle className="text-xl tracking-[-0.025em]">{artefact.title}</CardTitle>
            <CardDescription className="text-[11px] font-medium uppercase tracking-[0.16em]">
              Web artefact
            </CardDescription>
          </CardHeader>
          <CardContent className="flex items-center justify-between gap-4 px-5 py-5 sm:px-6">
            <div>
              <p className="text-sm font-medium">Open full artefact</p>
              <p className="mt-1 text-sm text-muted-foreground">Launch the interactive experience.</p>
            </div>
            <ExternalLink className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
          </CardContent>
        </Card>
      </a>
    )
  }

  return (
    <Card className={[
      'overflow-hidden border-border/70 bg-card/35 shadow-sm',
      mode === 'page' && artefact.kind === 'web' ? 'min-h-[calc(100svh-8rem)]' : '',
    ].join(' ')}>
      <CardHeader className="gap-2 border-b border-border/60 px-5 py-5 sm:px-6">
        <CardTitle className="text-xl tracking-[-0.025em]">{artefact.title}</CardTitle>
        <CardDescription className="text-[11px] font-medium uppercase tracking-[0.16em]">
          {artefact.kind}
        </CardDescription>
      </CardHeader>
      <CardContent className="px-5 py-5 sm:px-6 sm:py-6">
        {isDocument ? (
          <div className="typeset typeset-docs max-w-[65ch]">
            <MarkdownContent content={artefact.source} />
          </div>
        ) : isWeb ? (
          <WebArtefactPreview
            title={artefact.title}
            content={content}
            isInline={artefact.kind === 'inlineWeb'}
            isFullscreen={mode === 'page' && artefact.kind === 'web'}
          />
        ) : (
          <div className="not-typeset">
            <pre className="overflow-x-auto whitespace-pre-wrap text-sm leading-6">
              {content}
            </pre>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function WebArtefactPreview({
  title,
  content,
  isInline,
  isFullscreen = false,
}: {
  title: string
  content: string
  isInline: boolean
  isFullscreen?: boolean
}) {
  const iframeRef = useRef<HTMLIFrameElement>(null)
  const [contentHeight, setContentHeight] = useState<number>()

  useEffect(() => {
    if (!isInline) return

    const handleMessage = (event: MessageEvent) => {
      if (
        event.source !== iframeRef.current?.contentWindow
        || event.data?.type !== 'rina-artefact-height'
        || typeof event.data.height !== 'number'
      ) {
        return
      }

      setContentHeight(Math.max(288, Math.ceil(event.data.height)))
    }

    window.addEventListener('message', handleMessage)
    return () => window.removeEventListener('message', handleMessage)
  }, [isInline])

  const className = isInline
    ? 'block min-h-72 w-full border-0 bg-background'
    : isFullscreen
      ? 'block min-h-[calc(100svh-14rem)] w-full overflow-y-auto border-0 bg-background'
      : 'block h-[min(70vh,32rem)] min-h-64 w-full overflow-y-auto border-0 bg-background'

  return (
    <div className="-mx-5 overflow-hidden sm:-mx-6">
      <iframe
        ref={iframeRef}
        title={`${title} preview`}
        srcDoc={sandboxedWebDocument(content)}
        sandbox="allow-scripts"
        loading="eager"
        referrerPolicy="no-referrer"
        className={className}
        style={isInline ? {
          height: contentHeight ? `${contentHeight}px` : 'min(78vh, 36rem)',
        } : undefined}
      />
    </div>
  )
}

function artefactPath(uri?: string) {
  if (!uri) return undefined

  try {
    const reference = parseAtUri(uri)
    return `/s/${encodeURIComponent(reference.repo)}/${reference.collection}/${reference.rkey}`
  } catch {
    return undefined
  }
}

function sandboxedWebDocument(content: string) {
  const themeStyles = previewThemeStyles()
  const head = `
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.1.11"></script>
    <style type="text/tailwindcss">${themeStyles}</style>
    <script>
      (() => {
        const reportHeight = () => {
          const height = Math.max(
            document.body?.scrollHeight ?? 0,
            document.documentElement?.scrollHeight ?? 0
          )
          parent.postMessage({ type: 'rina-artefact-height', height }, '*')
        }
        addEventListener('load', reportHeight)
        new ResizeObserver(reportHeight).observe(document.documentElement)
      })()
    </script>
  `

  if (/<head\b[^>]*>/i.test(content)) {
    return content.replace(/<head\b[^>]*>/i, (tag) => `${tag}${head}`)
  }

  return `<!doctype html><html><head>${head}</head><body>${content}</body></html>`
}

function previewThemeStyles() {
  const tokenNames = [
    'background',
    'foreground',
    'card',
    'card-foreground',
    'primary',
    'primary-foreground',
    'secondary',
    'secondary-foreground',
    'muted',
    'muted-foreground',
    'accent',
    'accent-foreground',
    'destructive',
    'border',
    'input',
    'ring',
  ]
  const root = typeof document === 'undefined' ? undefined : document.documentElement
  const computed = root ? getComputedStyle(root) : undefined
  const declarations = tokenNames
    .map((name) => {
      const value = computed?.getPropertyValue(`--${name}`).trim()
      return value ? `--${name}: ${value};` : ''
    })
    .filter(Boolean)
    .join(' ')

  return `
    :root {
      ${declarations}
      --radius: 0.625rem;
      color-scheme: ${root?.classList.contains('dark') ? 'dark' : 'light'};
    }
    @theme {
      --color-background: var(--background);
      --color-foreground: var(--foreground);
      --color-card: var(--card);
      --color-card-foreground: var(--card-foreground);
      --color-primary: var(--primary);
      --color-primary-foreground: var(--primary-foreground);
      --color-secondary: var(--secondary);
      --color-secondary-foreground: var(--secondary-foreground);
      --color-muted: var(--muted);
      --color-muted-foreground: var(--muted-foreground);
      --color-accent: var(--accent);
      --color-accent-foreground: var(--accent-foreground);
      --color-destructive: var(--destructive);
      --color-border: var(--border);
      --color-input: var(--input);
      --color-ring: var(--ring);
      --radius-sm: calc(var(--radius) - 4px);
      --radius-md: calc(var(--radius) - 2px);
      --radius-lg: var(--radius);
    }
    @layer base {
      *, ::before, ::after { box-sizing: border-box; }
      html, body { margin: 0; min-height: 100%; }
      body {
        padding: 12px;
        background: var(--background);
        color: var(--foreground);
        overflow-x: hidden;
      }
    }
  `
}

function ShareBlockView({ block }: { block: ShareBlock }) {
  if (
    block.kind === 'code'
  ) {
    return (
      <div className="not-typeset">
        <pre className="overflow-x-auto rounded-lg bg-muted/60 p-4 text-sm leading-6 ring-1 ring-inset ring-border/50">
          {block.payload}
        </pre>
      </div>
    )
  }

  if (block.kind === 'toolCall' || block.kind === 'toolResult') return null

  if (block.kind === 'citationGroup') return null

  if (block.kind === 'artefactReference' || block.kind === 'fileReference') {
    return null
  }

  return <MarkdownContent content={block.payload} />
}

function pairToolActivity(calls: ShareBlock[], results: ShareBlock[]) {
  const remainingResults = [...results]

  return calls.map((call) => {
    const callID = call.attributes.callID
    const resultIndex = remainingResults.findIndex(
      (result) => result.attributes.callID === callID,
    )
    const result = resultIndex === -1 ? undefined : remainingResults.splice(resultIndex, 1)[0]
    return { call, result }
  })
}

function toolActivityLabel(
  calls: ShareBlock[],
  results: ShareBlock[],
  citationBlocks: ShareBlock[],
  isPending: boolean,
  hasError: boolean,
) {
  if (citationBlocks.length > 0 && !isPending && !hasError) {
    return citationActivitySummary(citationBlocks)
  }

  if (calls.length !== 1) {
    return calls.length === 0
      ? results.length === 1
        ? 'Tool result'
        : `${results.length} tool results`
      : `${calls.length} tool activities`
  }

  const name = calls[0].attributes.name
  const copy: Record<string, [string, string, string]> = {
    create_artefact: ['Writing artefact', 'Wrote artefact', 'Couldn’t write artefact'],
    update_artefact: ['Updating artefact', 'Updated artefact', 'Couldn’t update artefact'],
    display_artefact: ['Displaying artefact', 'Displayed artefact', 'Couldn’t display artefact'],
    read_artefact: ['Reading artefact', 'Read artefact', 'Couldn’t read artefact'],
    list_artefacts: ['Searching artefacts', 'Searched artefacts', 'Couldn’t search artefacts'],
    search_web: ['Searching the web', 'Searched the web', 'Couldn’t search the web'],
    search_workspace: ['Searching the workspace', 'Searched the workspace', 'Couldn’t search the workspace'],
  }
  const phrases = name ? copy[name] : undefined
  if (!phrases) return 'Tool activity'
  return isPending ? phrases[0] : hasError ? phrases[2] : phrases[1]
}

function ShareCitationGroups({
  blocks,
  collapsible = true,
}: {
  blocks: ShareBlock[]
  collapsible?: boolean
}) {
  const citations = deduplicateCitations(
    blocks.flatMap((block) => parseCitations(block.payload)),
  )
  const content = (
    <div className="space-y-3">
      <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-[0.12em] text-muted-foreground">
        <Link2 className="size-3.5" />
        Sources
      </div>
      {citations.length === 0 ? (
        <p className="text-sm text-muted-foreground">Sources unavailable</p>
      ) : (
        <div className="divide-y divide-border/60 border-y border-border/60">
          {citations.map((citation, index) => (
            <a
              key={citation.id ?? `${citation.url}-${index}`}
              href={citation.url}
              target="_blank"
              rel="noreferrer"
              className="group block px-2 py-3 transition-colors hover:bg-muted/50"
            >
              <div className="flex items-start gap-2">
                <div className="min-w-0 flex-1">
                  <p className="line-clamp-2 text-sm font-medium leading-5">
                    {citation.title || citation.url}
                  </p>
                  <p className="mt-1 truncate text-xs text-muted-foreground">
                    {citation.url}
                  </p>
                  {citation.snippet && (
                    <p className="mt-2 line-clamp-3 text-xs leading-5 text-muted-foreground">
                      {citation.snippet}
                    </p>
                  )}
                </div>
                <ExternalLink className="mt-0.5 size-3.5 shrink-0 text-muted-foreground transition-colors group-hover:text-foreground" />
              </div>
            </a>
          ))}
        </div>
      )}
    </div>
  )

  if (!collapsible) return content

  return (
    <details className="not-typeset group mt-5 max-w-[65ch] rounded-xl border border-border/70 bg-card/35 shadow-sm">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3.5 text-sm font-medium marker:hidden">
        <ChevronRight className="size-3.5 transition-transform group-open:rotate-90" />
        {citationActivitySummary(blocks)}
      </summary>
      <div className="border-t border-border/70 px-4 py-4">{content}</div>
    </details>
  )
}

type ShareCitation = {
  id?: string
  title: string
  url: string
  snippet: string
}

function parseCitations(payload: string): ShareCitation[] {
  try {
    const value: unknown = JSON.parse(payload)
    if (!Array.isArray(value)) return []

    return value.flatMap((item): ShareCitation[] => {
      if (!item || typeof item !== 'object') return []
      const record = item as Record<string, unknown>
      if (typeof record.url !== 'string' || !isSafeCitationURL(record.url)) {
        return []
      }
      return [{
        id: typeof record.id === 'string' ? record.id : undefined,
        title: typeof record.title === 'string' ? record.title : '',
        url: record.url,
        snippet: typeof record.snippet === 'string' ? record.snippet : '',
      }]
    })
  } catch {
    return []
  }
}

function deduplicateCitations(citations: ShareCitation[]) {
  return citations.filter((citation, index, values) =>
    values.findIndex(
      (candidate) =>
        (citation.id && candidate.id === citation.id)
        || candidate.url === citation.url,
    ) === index,
  )
}

function isSafeCitationURL(value: string) {
  try {
    const url = new URL(value)
    return url.protocol === 'https:' || url.protocol === 'http:'
  } catch {
    return false
  }
}

function citationActivitySummary(citationBlocks: ShareBlock[]) {
  const domains = citationBlocks.flatMap((block) =>
    parseCitations(block.payload).flatMap((citation) => {
      try {
        const host = new URL(citation.url).hostname.replace(/^www\./, '')
        return host ? [host] : []
      } catch {
        return []
      }
    }),
  ).filter((domain, index, values) => values.indexOf(domain) === index)

  if (domains.length === 0) return 'Found items'
  const visible = domains.slice(0, 3)
  const domainText = visible.length === 1
    ? visible[0]
    : visible.length === 2
      ? `${visible[0]} and ${visible[1]}`
      : `${visible.slice(0, -1).join(', ')}, and ${visible.at(-1)}`
  return `Found items from ${domainText}${domains.length > 3 ? ', and more' : ''}`
}

function MarkdownContent({ content }: { content: string }) {
  return <Markdown remarkPlugins={[remarkGfm]}>{content}</Markdown>
}
