"use client"
// Hand-built (no shadcn equivalent). API design referenced Astryx's real
// SegmentedControl components for prop-naming/behavior inspiration:
// https://raw.githubusercontent.com/facebook/astryx/main/packages/core/src/SegmentedControl/SegmentedControl.tsx
// https://raw.githubusercontent.com/facebook/astryx/main/packages/core/src/SegmentedControl/SegmentedControlItem.tsx
// (fetched directly, same attribution discipline as the theme tokens).
//
// Kept from Astryx: controlled `value`/`onChange` on the group, a `label`
// for the accessible name, `role="radiogroup"`/`role="radio"` (this is a
// single-choice control with tab-bar visuals, not a real tab bar — Astryx's
// own doc comment makes the same distinction), and a `fill` layout option
// for equal-width segments. Simplified relative to Astryx: no
// `disabledMessage` tooltip-on-disabled affordance, and roving-tabindex
// arrow-key navigation is implemented inline here rather than via a shared
// `useListFocus` hook (Astryx's version pulls that from its internal hooks
// package) — small enough to keep self-contained per this kit's "small and
// simple" bar for hand-built components.

import * as React from "react"

import { cn } from "@/lib/utils"

type SegmentedControlContextValue = {
  value: string
  onChange: (value: string) => void
  fill: boolean
}

const SegmentedControlContext =
  React.createContext<SegmentedControlContextValue | null>(null)

function useSegmentedControlContext() {
  const ctx = React.useContext(SegmentedControlContext)
  if (!ctx) {
    throw new Error(
      "SegmentedControlItem must be used within a SegmentedControl"
    )
  }
  return ctx
}

function SegmentedControl({
  className,
  value,
  onChange,
  label,
  fill = false,
  children,
  ...props
}: Omit<React.ComponentProps<"div">, "onChange"> & {
  value: string
  onChange: (value: string) => void
  label: string
  fill?: boolean
}) {
  const contextValue = React.useMemo(
    () => ({ value, onChange, fill }),
    [value, onChange, fill]
  )

  const handleKeyDown = (event: React.KeyboardEvent<HTMLDivElement>) => {
    if (
      event.key !== "ArrowRight" &&
      event.key !== "ArrowLeft" &&
      event.key !== "Home" &&
      event.key !== "End"
    ) {
      return
    }
    const items = Array.from(
      event.currentTarget.querySelectorAll<HTMLButtonElement>(
        '[role="radio"]:not(:disabled)'
      )
    )
    if (items.length === 0) return

    const currentIndex = items.findIndex(
      (item) => item.dataset.value === value
    )
    let nextIndex = currentIndex
    if (event.key === "ArrowRight") {
      nextIndex = currentIndex === items.length - 1 ? 0 : currentIndex + 1
    } else if (event.key === "ArrowLeft") {
      nextIndex = currentIndex <= 0 ? items.length - 1 : currentIndex - 1
    } else if (event.key === "Home") {
      nextIndex = 0
    } else if (event.key === "End") {
      nextIndex = items.length - 1
    }

    const next = items[nextIndex]
    if (next) {
      event.preventDefault()
      next.focus()
      onChange(next.dataset.value as string)
    }
  }

  return (
    <SegmentedControlContext.Provider value={contextValue}>
      <div
        data-slot="segmented-control"
        role="radiogroup"
        aria-label={label}
        onKeyDown={handleKeyDown}
        className={cn(
          "inline-flex items-center gap-0.5 rounded-lg bg-muted p-0.5",
          fill && "flex w-full",
          className
        )}
        {...props}
      >
        {children}
      </div>
    </SegmentedControlContext.Provider>
  )
}

function SegmentedControlItem({
  className,
  value: itemValue,
  disabled = false,
  children,
  ...props
}: React.ComponentProps<"button"> & { value: string }) {
  const ctx = useSegmentedControlContext()
  const isSelected = ctx.value === itemValue

  return (
    <button
      type="button"
      data-slot="segmented-control-item"
      role="radio"
      aria-checked={isSelected}
      data-value={itemValue}
      data-state={isSelected ? "active" : "inactive"}
      disabled={disabled}
      tabIndex={isSelected ? 0 : -1}
      onClick={() => {
        if (!disabled && !isSelected) ctx.onChange(itemValue)
      }}
      className={cn(
        "inline-flex h-7 items-center justify-center gap-1.5 rounded-md px-2.5 text-sm font-medium whitespace-nowrap text-muted-foreground transition-all outline-none focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:opacity-50",
        ctx.fill && "flex-1",
        isSelected
          ? "bg-background text-foreground shadow-sm"
          : "hover:text-foreground",
        className
      )}
      {...props}
    >
      {children}
    </button>
  )
}

export { SegmentedControl, SegmentedControlItem }
