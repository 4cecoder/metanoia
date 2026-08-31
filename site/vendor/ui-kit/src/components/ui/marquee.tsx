// Adapted from Magic UI's Marquee (MIT, github.com/magicuidesign/magicui),
// verified against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/marquee.tsx
// (fetched directly, not reconstructed from docs). Behavior/props are
// unchanged; adapted to this kit's `data-slot` convention. The
// `animate-marquee` / `animate-marquee-vertical` keyframes it depends on are
// registered in src/styles/globals.css, copied from that same component's
// registry entry (apps/www/public/r/marquee.json `cssVars`/`css`).
import * as React from "react"

import { cn } from "@/lib/utils"

function Marquee({
  className,
  reverse = false,
  pauseOnHover = false,
  children,
  vertical = false,
  repeat = 4,
  ...props
}: React.ComponentProps<"div"> & {
  reverse?: boolean
  pauseOnHover?: boolean
  vertical?: boolean
  repeat?: number
}) {
  return (
    <div
      data-slot="marquee"
      className={cn(
        "group flex gap-(--gap) overflow-hidden p-2 [--duration:40s] [--gap:1rem]",
        vertical ? "flex-col" : "flex-row",
        className
      )}
      {...props}
    >
      {Array.from({ length: repeat }).map((_, i) => (
        <div
          key={i}
          className={cn(
            "flex shrink-0 justify-around gap-(--gap)",
            vertical
              ? "animate-marquee-vertical flex-col"
              : "animate-marquee flex-row",
            pauseOnHover && "group-hover:[animation-play-state:paused]",
            reverse && "[animation-direction:reverse]"
          )}
        >
          {children}
        </div>
      ))}
    </div>
  )
}

export { Marquee }
