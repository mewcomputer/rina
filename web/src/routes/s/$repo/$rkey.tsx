import { createFileRoute, Link } from '@tanstack/react-router'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  atprotoShareClient,
  AtprotoShareError,
} from '@/lib/atproto-share-client'
import {
  SHARE_COLLECTION,
  type ShareBlock,
  type ShareMessage,
} from '@/lib/share'

export const Route = createFileRoute('/s/$repo/$rkey')({
  loader: ({ params }) =>
    atprotoShareClient.fetchAtUri(
      `at://${params.repo}/${SHARE_COLLECTION}/${params.rkey}`,
    ),
  pendingComponent: SharePending,
  errorComponent: ShareError,
  component: SharePage,
})

function SharePage() {
  const snapshot = Route.useLoaderData()

  return (
    <section className="mx-auto max-w-3xl px-6 py-12 sm:py-20">
      <div className="mb-10 space-y-3">
        <p className="text-sm font-medium text-primary">Ginny sharing</p>
        <h1 className="text-4xl font-semibold tracking-tight">{snapshot.title}</h1>
        <time
          className="text-sm text-muted-foreground"
          dateTime={snapshot.createdAt}
        >
          Shared {new Date(snapshot.createdAt).toLocaleDateString()}
        </time>
      </div>

      <div className="space-y-6">
        {snapshot.messages.map((message, index) => (
          <MessageCard key={message.id ?? `${message.role}-${index}`} message={message} />
        ))}
        {snapshot.artefacts.map((artefact, index) => (
          <Card key={artefact.id ?? `${artefact.title}-${index}`}>
            <CardHeader>
              <CardTitle>{artefact.title}</CardTitle>
              <CardDescription>{artefact.kind}</CardDescription>
            </CardHeader>
            <CardContent>
              <pre className="overflow-x-auto whitespace-pre-wrap text-sm leading-6">
                {artefact.source}
              </pre>
            </CardContent>
          </Card>
        ))}
        {snapshot.messages.length === 0 && snapshot.artefacts.length === 0 && (
          <Card>
            <CardContent className="py-8 text-sm text-muted-foreground">
              This share has no renderable content.
            </CardContent>
          </Card>
        )}
      </div>
    </section>
  )
}

function MessageCard({ message }: { message: ShareMessage }) {
  const isUser = message.role === 'user'

  return (
    <article className={isUser ? 'ml-auto max-w-[88%]' : 'max-w-[94%]'}>
      <p className="mb-2 text-xs font-medium uppercase tracking-wider text-muted-foreground">
        {message.role}
      </p>
      <Card className={isUser ? 'bg-muted/60' : undefined}>
        <CardContent className="space-y-4 py-5">
          {message.blocks.map((block, index) => (
            <ShareBlockView key={block.id ?? `${block.kind}-${index}`} block={block} />
          ))}
        </CardContent>
      </Card>
    </article>
  )
}

function ShareBlockView({ block }: { block: ShareBlock }) {
  if (block.kind === 'code' || block.kind === 'toolResult') {
    return (
      <pre className="overflow-x-auto rounded-md bg-muted p-4 text-sm leading-6">
        {block.payload}
      </pre>
    )
  }

  return <p className="whitespace-pre-wrap text-[0.95rem] leading-7">{block.payload}</p>
}

function SharePending() {
  return (
    <section className="mx-auto max-w-3xl px-6 py-20">
      <Card>
        <CardContent className="py-10 text-sm text-muted-foreground">
          Loading shared work…
        </CardContent>
      </Card>
    </section>
  )
}

function ShareError({ error }: { error: unknown }) {
  const message =
    error instanceof AtprotoShareError
      ? error.message
      : error instanceof Error
        ? error.message
        : 'Ginny could not load this share.'

  return (
    <section className="mx-auto max-w-3xl px-6 py-20">
      <Card>
        <CardHeader>
          <CardTitle>Couldn’t load this share</CardTitle>
          <CardDescription>{message}</CardDescription>
        </CardHeader>
        <CardContent>
          <Link
            to="/"
            className="inline-flex h-9 items-center rounded-lg border border-border bg-background px-3 text-sm font-medium transition-colors hover:bg-muted"
          >
            Back to Ginny
          </Link>
        </CardContent>
      </Card>
    </section>
  )
}
