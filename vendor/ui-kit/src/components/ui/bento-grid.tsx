// Adapted from Magic UI's Bento Grid (MIT, github.com/magicuidesign/magicui),
// verified against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/bento-grid.tsx
// (fetched directly, not reconstructed from docs).
//
// Deviations from upstream, to match this kit's conventions:
// - `data-slot` attributes added; `key` removed from BentoCard's own props
//   spread (React warns on that pattern — callers still supply `key` from
//   the outside when mapping).
// - Icon import swapped from `@radix-ui/react-icons` (not a dependency of
//   this kit) to `lucide-react` (already this kit's icon library, e.g.
//   dialog.tsx, sonner.tsx) — same "pass a component" shape either way.
// - Hardcoded `neutral-*`/black colors replaced with this kit's semantic
//   theme classes (`bg-card`, `text-foreground`, `text-muted-foreground`,
//   `ring-foreground/10`) so the effect follows the active Astryx theme and
//   automatic dark mode instead of a separate manual `dark:` palette.
import * as React from "react"
import { ArrowRightIcon } from "lucide-react"

import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"

function BentoGrid({
  className,
  ...props
}: React.ComponentProps<"div">) {
  return (
    <div
      data-slot="bento-grid"
      className={cn(
        "grid w-full auto-rows-[22rem] grid-cols-3 gap-4",
        className
      )}
      {...props}
    />
  )
}

function BentoCard({
  name,
  className,
  background,
  Icon,
  description,
  href,
  cta,
  ...props
}: React.ComponentProps<"div"> & {
  name: string
  className: string
  background: React.ReactNode
  Icon: React.ElementType
  description: string
  href: string
  cta: string
}) {
  return (
    <div
      data-slot="bento-card"
      className={cn(
        "group relative col-span-3 flex flex-col justify-between overflow-hidden rounded-xl bg-card ring-1 ring-foreground/10 transform-gpu",
        className
      )}
      {...props}
    >
      <div>{background}</div>
      <div className="p-4">
        <div className="pointer-events-none z-10 flex transform-gpu flex-col gap-1 transition-all duration-300 lg:group-hover:-translate-y-10">
          <Icon className="h-12 w-12 origin-left transform-gpu text-foreground transition-all duration-300 ease-in-out group-hover:scale-75" />
          <h3 className="text-xl font-semibold text-foreground">{name}</h3>
          <p className="max-w-lg text-muted-foreground">{description}</p>
        </div>

        <div className="pointer-events-none flex w-full translate-y-0 transform-gpu flex-row items-center transition-all duration-300 group-hover:translate-y-0 group-hover:opacity-100 lg:hidden">
          <Button variant="link" asChild size="sm" className="pointer-events-auto p-0">
            <a href={href}>
              {cta}
              <ArrowRightIcon className="ms-2 h-4 w-4 rtl:rotate-180" />
            </a>
          </Button>
        </div>
      </div>

      <div className="pointer-events-none absolute bottom-0 hidden w-full translate-y-10 transform-gpu flex-row items-center p-4 opacity-0 transition-all duration-300 group-hover:translate-y-0 group-hover:opacity-100 lg:flex">
        <Button variant="link" asChild size="sm" className="pointer-events-auto p-0">
          <a href={href}>
            {cta}
            <ArrowRightIcon className="ms-2 h-4 w-4 rtl:rotate-180" />
          </a>
        </Button>
      </div>

      <div className="pointer-events-none absolute inset-0 transform-gpu bg-transparent transition-all duration-300 group-hover:bg-foreground/3" />
    </div>
  )
}

export { BentoGrid, BentoCard }
