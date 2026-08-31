// Hand-built (no shadcn equivalent). API design referenced Astryx's real
// EmptyState component for prop-naming/behavior inspiration:
// https://raw.githubusercontent.com/facebook/astryx/main/packages/core/src/EmptyState/EmptyState.tsx
// (fetched directly, same attribution discipline as the theme tokens).
//
// Kept the same core shape as Astryx's: `title` (required), `description`,
// `icon` (rendered aria-hidden, decorative), `actions`, and `role="status"`
// so assistive tech is told about the empty content region. Simplified
// relative to Astryx: no `headingLevel`/`isCompact` variant props — this
// kit's version always renders an <h3> with one spacing scale, which covers
// the common "no items yet" case this component targets; consumers needing
// a different heading level can wrap their own heading and skip the `title`
// prop's default rendering by passing a `className` override, or just reach
// for plain markup for bespoke cases.
import * as React from "react"

import { cn } from "@/lib/utils"

function EmptyState({
  className,
  title,
  description,
  icon,
  actions,
  ...props
}: React.ComponentProps<"div"> & {
  title: string
  description?: string
  icon?: React.ReactNode
  actions?: React.ReactNode
}) {
  return (
    <div
      data-slot="empty-state"
      role="status"
      className={cn(
        "flex flex-col items-center justify-center gap-4 px-6 py-8 text-center",
        className
      )}
      {...props}
    >
      {icon != null && (
        <div
          data-slot="empty-state-icon"
          aria-hidden="true"
          className="text-muted-foreground [&>svg]:size-10"
        >
          {icon}
        </div>
      )}
      <div className="flex max-w-90 flex-col items-center gap-1">
        <h3 data-slot="empty-state-title" className="font-heading text-base font-medium text-foreground">
          {title}
        </h3>
        {description != null && (
          <p data-slot="empty-state-description" className="text-sm text-muted-foreground">
            {description}
          </p>
        )}
      </div>
      {actions != null && (
        <div data-slot="empty-state-actions" className="mt-1 flex flex-row items-center gap-2">
          {actions}
        </div>
      )}
    </div>
  )
}

export { EmptyState }
