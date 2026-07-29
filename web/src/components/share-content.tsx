import Markdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import type { ShareArtefact, ShareBlock, ShareMessage } from '@/lib/share'

export function ShareMessageCard({ message }: { message: ShareMessage }) {
  const isUser = message.role === 'user'

  return (
    <article className={isUser ? 'ml-auto max-w-[88%]' : 'max-w-[94%]'}>
      <p className="mb-2 text-xs font-medium uppercase tracking-wider text-muted-foreground">
        {message.role}
      </p>
      <Card className={isUser ? 'bg-muted/60' : undefined}>
        <CardContent className="py-5">
          <div className="typeset typeset-docs max-w-[65ch]">
            {message.blocks.map((block, index) => (
              <ShareBlockView
                key={block.id ?? `${block.kind}-${index}`}
                block={block}
              />
            ))}
          </div>
        </CardContent>
      </Card>
    </article>
  )
}

export function ShareArtefactCard({ artefact }: { artefact: ShareArtefact }) {
  const content = artefact.renderedContent ?? artefact.source
  const isDocument = artefact.kind === 'document'

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

function ShareBlockView({ block }: { block: ShareBlock }) {
  if (
    block.kind === 'code'
    || block.kind === 'toolCall'
    || block.kind === 'toolResult'
  ) {
    return (
      <div className="not-typeset">
        <pre className="overflow-x-auto rounded-md bg-muted p-4 text-sm leading-6">
          {block.payload}
        </pre>
      </div>
    )
  }

  if (block.kind === 'artefactReference' || block.kind === 'fileReference') {
    return null
  }

  return <MarkdownContent content={block.payload} />
}

function MarkdownContent({ content }: { content: string }) {
  return <Markdown remarkPlugins={[remarkGfm]}>{content}</Markdown>
}
