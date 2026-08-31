// Hand-built (no shadcn equivalent). API design referenced Astryx's real
// Kbd component for prop-naming/behavior inspiration:
// https://raw.githubusercontent.com/facebook/astryx/main/packages/core/src/Kbd/Kbd.tsx
// (fetched directly, same attribution discipline as the theme tokens).
//
// Astryx's Kbd takes a single `keys` string ("mod+shift+p"), splits on "+",
// and renders one styled <kbd> per key with platform-aware glyph mapping
// (mod -> ⌘ on macOS / Ctrl elsewhere) plus a spoken-word aria-label since
// the glyphs aren't meaningfully announced by screen readers.
//
// This kit intentionally keeps a smaller surface: a single children-based
// `<Kbd>⌘K</Kbd>` (per the task's own example), not the "+"-parsing DSL —
// simpler for a general-purpose kit where callers already know their target
// platform's glyphs, at the cost of the platform-detection niceties. The
// visual treatment (a small inset "keycap" look: subtle bg, emphasized
// bottom border to read as a physical key, compact type) mirrors Astryx's
// `kbd` style block. `KbdGroup` is added for chaining multiple keys, e.g.
// <KbdGroup><Kbd>⌘</Kbd><Kbd>K</Kbd></KbdGroup>.
import * as React from "react"

import { cn } from "@/lib/utils"

function Kbd({ className, ...props }: React.ComponentProps<"kbd">) {
  return (
    <kbd
      data-slot="kbd"
      className={cn(
        "inline-flex h-5 min-w-5 items-center justify-center rounded-sm border-b-2 border-b-input bg-muted px-1.5 font-mono text-2xs font-medium text-muted-foreground select-none",
        className
      )}
      {...props}
    />
  )
}

function KbdGroup({ className, ...props }: React.ComponentProps<"span">) {
  return (
    <span
      data-slot="kbd-group"
      className={cn("inline-flex items-center gap-1", className)}
      {...props}
    />
  )
}

export { Kbd, KbdGroup }
