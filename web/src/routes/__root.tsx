import { createRootRoute, Link, Outlet } from '@tanstack/react-router'

export const Route = createRootRoute({
  component: RootLayout,
})

function RootLayout() {
  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="border-b border-border/60 bg-background">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
          <Link to="/" className="group inline-flex items-center gap-2.5 text-sm font-semibold tracking-tight">
            <span
              aria-hidden="true"
              className="size-2 rounded-full bg-primary transition-transform duration-300 group-hover:scale-125"
            />
            <span>Rina</span>
            <span className="font-normal text-muted-foreground">sharing</span>
          </Link>
          <span className="hidden text-[10px] font-medium uppercase tracking-[0.18em] text-muted-foreground sm:block">
            public snapshots
          </span>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
    </div>
  )
}
