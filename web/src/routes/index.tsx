import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/')({
  component: HomePage,
})

function HomePage() {
  return (
    <section className="min-h-[calc(100svh-3.5rem)]">
      <div className="mx-auto flex max-w-6xl items-center px-6 py-24 sm:py-32 lg:min-h-[calc(100svh-3.5rem)] lg:py-20">
        <div className="max-w-2xl">
          <p className="flex items-center gap-3 text-[11px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
            <span aria-hidden="true" className="size-2 rounded-full bg-primary" />
            Rina / shared work
          </p>
          <h1 className="mt-8 max-w-xl text-balance text-5xl font-semibold leading-[0.98] tracking-[-0.055em] sm:text-7xl">
            Conversations worth keeping.
          </h1>
          <p className="mt-8 max-w-lg text-lg leading-8 text-muted-foreground">
            A calm, public window into the conversations and artefacts you
            choose to share from Rina.
          </p>
          <div className="mt-16 flex items-center gap-4 border-t border-border/70 pt-5 text-xs text-muted-foreground">
            <span className="font-medium uppercase tracking-[0.16em] text-foreground">
              atproto
            </span>
            <span aria-hidden="true" className="size-1 rounded-full bg-border" />
            <span>open by design</span>
          </div>
        </div>
      </div>
    </section>
  )
}
