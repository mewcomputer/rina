import { createRootRoute, Link, Outlet } from '@tanstack/react-router'

export const Route = createRootRoute({
  component: RootLayout,
})

function RootLayout() {
  return (
    <div className="min-h-svh bg-background text-foreground">
      <header className="border-b bg-background/90">
        <div className="mx-auto flex h-16 max-w-5xl items-center px-6">
          <Link to="/" className="text-lg font-semibold tracking-tight">
            Ginny
          </Link>
        </div>
      </header>
      <main>
        <Outlet />
      </main>
    </div>
  )
}
