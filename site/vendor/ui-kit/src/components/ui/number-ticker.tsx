// Adapted from Magic UI's Number Ticker (MIT, github.com/magicuidesign/magicui)
// — the one text/number-animation component curated from Magic UI's several
// variants (Text Reveal, Typing Animation, Number Ticker, ...), verified
// against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/number-ticker.tsx
// (fetched directly, not reconstructed from docs). Upstream imports from
// "motion/react" (the `motion` npm package) — that's what this kit adds as
// a dependency, not `framer-motion`.
//
// Deviations from upstream: `data-slot="number-ticker"` added; hardcoded
// `text-black dark:text-white` replaced with this kit's `text-foreground`
// theme class.
"use client"

import * as React from "react"
import { useEffect, useRef } from "react"
import { useInView, useMotionValue, useSpring } from "motion/react"

import { cn } from "@/lib/utils"

function NumberTicker({
  value,
  startValue = 0,
  direction = "up",
  delay = 0,
  className,
  decimalPlaces = 0,
  ...props
}: React.ComponentProps<"span"> & {
  value: number
  startValue?: number
  direction?: "up" | "down"
  delay?: number
  decimalPlaces?: number
}) {
  const ref = useRef<HTMLSpanElement>(null)
  const motionValue = useMotionValue(direction === "down" ? value : startValue)
  const springValue = useSpring(motionValue, {
    damping: 60,
    stiffness: 100,
  })
  const isInView = useInView(ref, { once: true, margin: "0px" })

  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | null = null

    if (isInView) {
      timer = setTimeout(() => {
        motionValue.set(direction === "down" ? startValue : value)
      }, delay * 1000)
    }

    return () => {
      if (timer !== null) {
        clearTimeout(timer)
      }
    }
  }, [motionValue, isInView, delay, value, direction, startValue])

  useEffect(
    () =>
      springValue.on("change", (latest) => {
        if (ref.current) {
          ref.current.textContent = Intl.NumberFormat("en-US", {
            minimumFractionDigits: decimalPlaces,
            maximumFractionDigits: decimalPlaces,
          }).format(Number(latest.toFixed(decimalPlaces)))
        }
      }),
    [springValue, decimalPlaces]
  )

  return (
    <span
      ref={ref}
      data-slot="number-ticker"
      className={cn("inline-block tracking-wider text-foreground tabular-nums", className)}
      {...props}
    >
      {startValue}
    </span>
  )
}

export { NumberTicker }
