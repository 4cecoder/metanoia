// Adapted from Magic UI's Shimmer Button (MIT, github.com/magicuidesign/magicui),
// verified against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/shimmer-button.tsx
// (fetched directly, not reconstructed from docs). The `animate-shimmer-slide`
// / `animate-spin-around` keyframes it depends on are registered in
// src/styles/globals.css, copied from that component's registry entry
// (apps/www/public/r/shimmer-button.json `cssVars`/`css`).
//
// Deviations from upstream, to match this kit's conventions:
// - No React.forwardRef — this kit targets React 19, where `ref` is a plain
//   prop (see button.tsx, dialog.tsx, ... none of which use forwardRef).
// - Default `shimmerColor`/`background` swapped from hardcoded white/black to
//   this kit's `--color-primary-foreground` / `--color-primary` theme
//   tokens, so the effect follows the active Astryx theme (and dark mode)
//   instead of being pinned to fixed colors.
// - `data-slot="shimmer-button"` added for consistency with every other
//   component in this kit.
import * as React from "react"

import { cn } from "@/lib/utils"

function ShimmerButton({
  shimmerColor = "var(--color-primary-foreground)",
  shimmerSize = "0.05em",
  shimmerDuration = "3s",
  borderRadius = "var(--radius-4xl)",
  background = "var(--color-primary)",
  className,
  children,
  ...props
}: React.ComponentProps<"button"> & {
  shimmerColor?: string
  shimmerSize?: string
  borderRadius?: string
  shimmerDuration?: string
  background?: string
}) {
  return (
    <button
      data-slot="shimmer-button"
      style={
        {
          "--spread": "90deg",
          "--shimmer-color": shimmerColor,
          "--radius": borderRadius,
          "--speed": shimmerDuration,
          "--cut": shimmerSize,
          "--bg": background,
        } as React.CSSProperties
      }
      className={cn(
        "group relative z-0 flex cursor-pointer items-center justify-center overflow-hidden [border-radius:var(--radius)] border border-white/10 px-6 py-3 text-sm font-medium whitespace-nowrap text-primary-foreground [background:var(--bg)]",
        "transform-gpu transition-transform duration-300 ease-in-out active:translate-y-px",
        className
      )}
      {...props}
    >
      {/* spark container */}
      <div className="@container-[size] absolute inset-0 -z-30 overflow-visible blur-[2px]">
        {/* spark */}
        <div className="animate-shimmer-slide absolute inset-0 aspect-square h-[100cqh] rounded-none [mask:none]">
          {/* spark before */}
          <div className="animate-spin-around absolute -inset-full w-auto rotate-0 [background:conic-gradient(from_calc(270deg-(var(--spread)*0.5)),transparent_0,var(--shimmer-color)_var(--spread),transparent_var(--spread))] [translate:0_0]" />
        </div>
      </div>
      {children}

      {/* highlight */}
      <div
        className={cn(
          "absolute inset-0 size-full rounded-2xl px-4 py-1.5 text-sm font-medium shadow-[inset_0_-8px_10px_#ffffff1f]",
          "transform-gpu transition-all duration-300 ease-in-out",
          "group-hover:shadow-[inset_0_-6px_10px_#ffffff3f]",
          "group-active:shadow-[inset_0_-10px_10px_#ffffff3f]"
        )}
      />

      {/* backdrop */}
      <div className="absolute inset-(--cut) -z-20 [border-radius:var(--radius)] [background:var(--bg)]" />
    </button>
  )
}

export { ShimmerButton }
