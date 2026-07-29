import { Menu } from '@base-ui/react/menu'
import { createFileRoute, Link } from '@tanstack/react-router'
import { EllipsisVertical, Share2 } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { ShareArtefactCard, ShareMessageCard } from '@/components/share-content'
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
  const [shareStatus, setShareStatus] = useState<ShareStatus>('idle')

  return (
    <section className="mx-auto max-w-3xl px-6 py-12 sm:py-20">
      <div className="mb-10 flex items-start justify-between gap-6">
        <div className="space-y-3">
          <p className="text-sm font-medium text-primary">Ginny sharing</p>
          <h1 className="text-4xl font-semibold tracking-tight">{snapshot.title}</h1>
          <time
            className="text-sm text-muted-foreground"
            dateTime={snapshot.createdAt}
          >
            Shared {new Date(snapshot.createdAt).toLocaleDateString()}
          </time>
        </div>
        <ShareMenu onShare={shareCurrentPage} onStatusChange={setShareStatus} />
        <span className="sr-only" role="status" aria-live="polite">
          {shareStatus === 'copied' && 'Share link copied.'}
          {shareStatus === 'shared' && 'Share sheet opened.'}
          {shareStatus === 'error' && 'Could not share this page.'}
        </span>
      </div>

      <div className="space-y-6">
        {snapshot.messages.map((message, index) => (
          <ShareMessageCard
            key={message.id ?? `${message.role}-${index}`}
            message={message}
          />
        ))}
        {snapshot.artefacts.map((artefact, index) => (
          <ShareArtefactCard
            key={artefact.id ?? `${artefact.title}-${index}`}
            artefact={artefact}
          />
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

type ShareStatus = 'idle' | 'copied' | 'shared' | 'error'

function ShareMenu({
  onShare,
  onStatusChange,
}: {
  onShare: () => Promise<ShareStatus>
  onStatusChange: (status: ShareStatus) => void
}) {
  return (
    <Menu.Root>
      <Menu.Trigger
        aria-label="More options"
        render={
          <Button variant="ghost" size="icon" aria-label="More options">
            <EllipsisVertical />
          </Button>
        }
      />
      <Menu.Portal>
        <Menu.Positioner sideOffset={8} align="end">
          <Menu.Popup className="min-w-44 rounded-xl border border-border bg-popover p-1.5 text-popover-foreground shadow-lg outline-none data-[open]:animate-in data-[closed]:animate-out data-[closed]:fade-out-0 data-[open]:fade-in-0">
            <Menu.Item
              className="flex cursor-default items-center gap-2 rounded-lg px-2.5 py-2 text-sm outline-none data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground"
              onClick={async () => onStatusChange(await onShare())}
            >
              <Share2 className="size-4 text-muted-foreground" />
              Share
            </Menu.Item>
          </Menu.Popup>
        </Menu.Positioner>
      </Menu.Portal>
    </Menu.Root>
  )
}

async function shareCurrentPage(): Promise<ShareStatus> {
  const shareData = {
    title: document.title,
    url: window.location.href,
  }

  if (navigator.share) {
    try {
      await navigator.share(shareData)
      return 'shared'
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        return 'idle'
      }
    }
  }

  try {
    await navigator.clipboard.writeText(shareData.url)
    return 'copied'
  } catch {
    return 'error'
  }
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
