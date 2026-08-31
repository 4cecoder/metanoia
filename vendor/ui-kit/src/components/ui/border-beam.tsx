// Adapted from Magic UI's Border Beam (MIT, github.com/magicuidesign/magicui),
// verified against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/border-beam.tsx
// (fetched directly, not reconstructed from docs). Upstream imports from
// "motion/react" (the `motion` npm package) — that's what this kit adds as
// a dependency, not `framer-motion`.
//
// Deviations from upstream, to match this kit's conventions:
// - `data-slot="border-beam"` added.
// - Default `colorFrom`/`colorTo` swapped from hardcoded "#ffaa40"/"#9c40ff"
//   to this kit's `--color-primary` / `--color-ring` theme tokens, so the
//   subtle highlight follows the active Astryx theme and dark mode. Both
//   remain fully overridable via props.
"use client"

import * as React from "react"
import { motion, type MotionStyle, type Transition } from "motion/react"

import { cn } from "@/lib/utils"

function BorderBeam({
  className,
  size = 50,
  delay = 0,
  duration = 6,
  colorFrom = "var(--color-primary)",
  colorTo = "var(--color-ring)",
  transition,
  style,
  reverse = false,
  initialOffset = 0,
  borderWidth = 1,
}: {
  size?: number
  duration?: number
  delay?: number
  colorFrom?: string
  colorTo?: string
  transition?: Transition
  className?: string
  style?: React.CSSProperties
  reverse?: boolean
  initialOffset?: number
  borderWidth?: number
}) {
  return (
    <div
      data-slot="border-beam"
      className="pointer-events-none absolute inset-0 rounded-[inherit] border-(length:--border-beam-width) border-transparent mask-[linear-gradient(transparent,transparent),linear-gradient(#000,#000)] mask-intersect [mask-clip:padding-box,border-box]"
      style={{ "--border-beam-width": `${borderWidth}px` } as React.CSSProperties}
    >
      <motion.div
        className={cn(
          "absolute aspect-square bg-linear-to-l from-(--color-from) via-(--color-to) to-transparent",
          className
        )}
        style={
          {
            width: size,
            offsetPath: `rect(0 auto auto 0 round ${size}px)`,
            "--color-from": colorFrom,
            "--color-to": colorTo,
            ...style,
          } as MotionStyle
        }
        initial={{ offsetDistance: `${initialOffset}%` }}
        animate={{
          offsetDistance: reverse
            ? [`${100 - initialOffset}%`, `${-initialOffset}%`]
            : [`${initialOffset}%`, `${100 + initialOffset}%`],
        }}
        transition={{
          repeat: Infinity,
          ease: "linear",
          duration,
          delay: -delay,
          ...transition,
        }}
      />
    </div>
  )
}

export { BorderBeam }
