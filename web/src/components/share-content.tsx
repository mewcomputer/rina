import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  AlertTriangle,
  Check,
  ChevronRight,
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
  ShareMessage,
  ShareProviderContinuation,
} from '@/lib/share'

export function ShareMessageList({ messages }: { messages: ShareMessage[] }) {
  const items = []

  for (let index = 0; index < messages.length;) {
    const message = messages[index]
    const calls = message.blocks.filter((block) => block.kind === 'toolCall')

    if (message.role === 'assistant' && calls.length > 0) {
      const results: ShareBlock[] = []
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
          toolActivity={{ calls, results }}
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
        />,
      )
      index += 1
      continue
    }

    items.push(
      <ShareMessageCard
        key={message.id ?? `${message.role}-${index}`}
        message={message}
      />,
    )
    index += 1
  }

  return items
}

export function ShareMessageCard({
  message,
  toolActivity,
}: {
  message: ShareMessage
  toolActivity?: { calls: ShareBlock[]; results: ShareBlock[] }
}) {
  const isUser = message.role === 'user'

  return (
    <article className={isUser ? 'ml-auto max-w-[88%]' : 'max-w-[94%]'}>
      <p className="mb-2 text-xs font-medium uppercase tracking-wider text-muted-foreground">
        {message.role}
      </p>
      <Card className={isUser ? 'bg-muted/60' : undefined}>
        <CardContent className="py-5">
          <ThinkingDisclosure continuations={message.providerContinuations} />
          <div className="typeset typeset-docs max-w-[65ch]">
            {message.blocks.map((block, index) => (
              <ShareBlockView
                key={block.id ?? `${block.kind}-${index}`}
                block={block}
              />
            ))}
          </div>
          {toolActivity && (
            <ShareToolActivityCard
              calls={toolActivity.calls}
              results={toolActivity.results}
            />
          )}
        </CardContent>
      </Card>
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
    <details className="group mb-4 max-w-[65ch] text-muted-foreground">
      <summary className="flex cursor-pointer list-none items-center gap-2 text-sm font-medium marker:hidden">
        <ChevronRight className="size-4 transition-transform group-open:rotate-90" />
        <Sparkles className="size-4" />
        Thinking
      </summary>
      <div className="mt-3 border-l border-border pl-4 [--color-foreground:var(--muted-foreground)]">
        {content ? (
          <div className="typeset typeset-docs text-sm">
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
}: {
  calls: ShareBlock[]
  results: ShareBlock[]
}) {
  if (calls.length === 0 && results.length === 0) return null

  const activities = pairToolActivity(calls, results)
  const hasError = results.some((result) => result.attributes.isError === 'true')
  const isPending =
    calls.some((call) => !call.isComplete)
    || activities.some(({ result }) => !result)
  const label = toolActivityLabel(calls, results, isPending, hasError)
  const StatusIcon = hasError ? AlertTriangle : isPending ? LoaderCircle : Check

  return (
    <details className="group mt-4 max-w-[65ch] rounded-xl border border-border bg-muted/30">
      <summary className="flex cursor-pointer list-none items-center gap-2 px-4 py-3 text-sm font-medium marker:hidden">
        <ChevronRight className="size-4 transition-transform group-open:rotate-90" />
        <StatusIcon
          className={[
            'size-4',
            hasError
              ? 'text-destructive'
              : isPending
                ? 'animate-spin text-muted-foreground'
                : 'text-primary',
          ].join(' ')}
        />
        {label}
      </summary>
      <div className="space-y-4 border-t border-border px-4 py-3">
        {activities.map(({ call, result }, index) => (
          <div
            key={call.id ?? `${call.attributes.callID ?? 'tool'}-${index}`}
            className="space-y-2"
          >
            <div className="text-sm font-medium">
              {call.attributes.name || 'Tool'}
            </div>
            {call.payload && (
              <pre className="overflow-x-auto whitespace-pre-wrap rounded-md bg-background/70 p-3 text-xs leading-5 text-muted-foreground">
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
                <pre className="overflow-x-auto whitespace-pre-wrap rounded-md bg-background/70 p-3 text-xs leading-5 text-muted-foreground">
                  {result.payload}
                </pre>
              </div>
            )}
          </div>
        ))}
      </div>
    </details>
  )
}

export function ShareArtefactCard({ artefact }: { artefact: ShareArtefact }) {
  const content = artefact.renderedContent ?? artefact.source
  const isDocument = artefact.kind === 'document'
  const isWeb = artefact.kind === 'web' || artefact.kind === 'inlineWeb'

  return (
    <Card>
      <CardHeader>
        <CardTitle>{artefact.title}</CardTitle>
        <CardDescription>{artefact.kind}</CardDescription>
      </CardHeader>
      <CardContent>
        {isDocument ? (
          <div className="typeset typeset-docs max-w-[65ch]">
            <MarkdownContent content={artefact.source} />
          </div>
        ) : isWeb ? (
          <InlineWebPreview title={artefact.title} content={content} />
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

function InlineWebPreview({ title, content }: { title: string; content: string }) {
  return (
    <div className="-mx-6 overflow-hidden sm:-mx-6">
      <iframe
        title={`${title} preview`}
        srcDoc={sandboxedWebDocument(content)}
        sandbox="allow-scripts"
        loading="lazy"
        className="block h-[min(70vh,32rem)] min-h-64 w-full border-0 bg-background"
      />
    </div>
  )
}

function sandboxedWebDocument(content: string) {
  const themeStyles = previewThemeStyles()
  const head = `
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; img-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.1.11"></script>
    <style type="text/tailwindcss">${themeStyles}</style>
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
        padding: 16px;
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
        <pre className="overflow-x-auto rounded-md bg-muted p-4 text-sm leading-6">
          {block.payload}
        </pre>
      </div>
    )
  }

  if (block.kind === 'toolCall' || block.kind === 'toolResult') return null

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
  isPending: boolean,
  hasError: boolean,
) {
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

function MarkdownContent({ content }: { content: string }) {
  return <Markdown remarkPlugins={[remarkGfm]}>{content}</Markdown>
}
