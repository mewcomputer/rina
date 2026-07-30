import { Menu } from '@base-ui/react/menu'
import { createFileRoute, Link } from '@tanstack/react-router'
import { EllipsisVertical, Share2 } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui/button'
import {
  ShareArtefactCard,
  ShareGenerationDetails,
  ShareMessageList,
} from '@/components/share-content'
import {
  atprotoShareClient,
  AtprotoShareError,
} from '@/lib/atproto-share-client'
import {
  SHARE_COLLECTION,
  referencedArtefactIDs,
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
  const inlineArtefactIDs = referencedArtefactIDs(snapshot.messages)
  const standaloneArtefacts = snapshot.artefacts.filter(
    (artefact) => !inlineArtefactIDs.has(artefact.id ?? ''),
  )

  return (
    <section className="min-h-[calc(100svh-3.5rem)]">
      <div className="mx-auto max-w-4xl px-6 pb-20 sm:pb-28">
        <div className="flex items-start justify-between gap-6 border-b border-border/70 pb-10 pt-16 sm:pt-24">
          <div className="min-w-0 space-y-5">
            <p className="flex items-center gap-3 text-[11px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
              <span aria-hidden="true" className="size-2 rounded-full bg-primary" />
              Rina conversation
            </p>
            <h1 className="max-w-3xl text-balance text-4xl font-semibold leading-[1.02] tracking-[-0.045em] sm:text-6xl">
              {snapshot.title}
            </h1>
            <time className="block text-sm text-muted-foreground" dateTime={snapshot.createdAt}>
              Shared {new Date(snapshot.createdAt).toLocaleDateString()}
            </time>
            <ShareGenerationDetails generation={snapshot.generation} />
          </div>
          <ShareMenu onShare={shareCurrentPage} onStatusChange={setShareStatus} />
          <span className="sr-only" role="status" aria-live="polite">
            {shareStatus === 'copied' && 'Share link copied.'}
            {shareStatus === 'shared' && 'Share sheet opened.'}
            {shareStatus === 'error' && 'Could not share this page.'}
          </span>
        </div>

        <div className="mx-auto max-w-3xl space-y-12 pt-10 sm:pt-14">
          <div className="space-y-10">
            <ShareMessageList messages={snapshot.messages} artefacts={snapshot.artefacts} />
          </div>
          {standaloneArtefacts.length > 0 && (
            <section className="space-y-5 border-t border-border/70 pt-8">
              <p className="text-[11px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
                Artefacts
              </p>
              <div className="space-y-6">
                {standaloneArtefacts.map((artefact, index) => (
                  <ShareArtefactCard
                    key={artefact.id ?? `${artefact.title}-${index}`}
                    artefact={artefact}
                  />
                ))}
              </div>
            </section>
          )}
          {snapshot.messages.length === 0 && snapshot.artefacts.length === 0 && (
            <div className="border border-dashed border-border px-5 py-8 text-sm text-muted-foreground">
              This share has no renderable content.
            </div>
          )}
        </div>
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
    <section className="mx-auto max-w-4xl px-6 py-24">
      <div className="border-t border-border/70 pt-5 text-sm text-muted-foreground">
        Loading shared work…
      </div>
    </section>
  )
}

function ShareError({ error }: { error: unknown }) {
  const message =
    error instanceof AtprotoShareError
      ? error.message
      : error instanceof Error
        ? error.message
        : 'Rina could not load this share.'

  return (
    <section className="mx-auto max-w-4xl px-6 py-24">
      <div className="max-w-xl border-t border-destructive/60 pt-5">
        <h1 className="text-2xl font-semibold tracking-tight">Couldn’t load this share</h1>
        <p className="mt-3 text-sm leading-6 text-muted-foreground">{message}</p>
        <Link
          to="/"
          className="mt-8 inline-flex h-9 items-center border border-border px-3 text-sm font-medium transition-colors hover:bg-muted"
        >
          Back to Rina
        </Link>
      </div>
    </section>
  )
}
