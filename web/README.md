# Ginny web

The public sharing viewer for Ginny.

This app is intentionally separate from the native iOS target. It uses:

- Vite and React 19
- TanStack Router with file-based routes
- Tailwind CSS v4
- shadcn/ui with the Nova preset

## Commands

```sh
pnpm install
pnpm dev
pnpm build
pnpm lint
pnpm test
```

`pnpm build` generates `src/routeTree.gen.ts` before type-checking and building. The generated route tree is ignored by git.

The first route is a deliberately small shell. Shared atproto records and the read-only renderer will be added on top of this foundation.

## Deployment

The presumed production origin is `https://rina.mew.computer`. Copy `.env.example` to `.env` when deploying somewhere else and override `VITE_PUBLIC_BASE_URL`. This origin will be used for canonical share links and future atproto OAuth client metadata.
