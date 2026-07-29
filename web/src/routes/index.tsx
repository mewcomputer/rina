import { createFileRoute } from '@tanstack/react-router'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export const Route = createFileRoute('/')({
  component: HomePage,
})

function HomePage() {
  return (
    <section className="mx-auto flex min-h-[calc(100svh-4rem)] max-w-5xl items-center px-6 py-16">
      <Card className="w-full max-w-xl">
        <CardHeader>
          <p className="text-sm font-medium text-primary">Ginny sharing</p>
          <CardTitle className="text-3xl tracking-tight">
            A quiet home for shared work.
          </CardTitle>
          <CardDescription>
            The public viewer is ready for the next step: loading a signed
            Ginny snapshot from an atproto repository.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Button>Set up sharing</Button>
        </CardContent>
      </Card>
    </section>
  )
}
