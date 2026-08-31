"use client"
// Adapted from Magic UI's Confetti (MIT, github.com/magicuidesign/magicui),
// verified against the real upstream source at
// https://raw.githubusercontent.com/magicuidesign/magicui/main/apps/www/registry/magicui/confetti.tsx
// (fetched directly, not reconstructed from docs). Depends on the
// `canvas-confetti` npm package (upstream's own registry entry lists it as
// a dependency) — added alongside `@types/canvas-confetti` for this kit's
// strict TypeScript config. Good fit for a "success" moment in a product,
// e.g. after a payment completes.
//
// Deviations from upstream: `data-slot="confetti"` added to the canvas and
// the `ConfettiButton`; `<ConfettiButton>` renders this kit's own `Button`
// (already the case upstream — no change needed there, just noting it uses
// this kit's variant/size props for free).

import type { ReactNode } from "react"
import React, {
  createContext,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
} from "react"
import type {
  GlobalOptions as ConfettiGlobalOptions,
  CreateTypes as ConfettiInstance,
  Options as ConfettiOptions,
} from "canvas-confetti"
import confetti from "canvas-confetti"

import { Button } from "@/components/ui/button"

type Api = {
  fire: (options?: ConfettiOptions) => void
}

export type ConfettiRef = Api | null

type ConfettiProps = React.ComponentPropsWithoutRef<"canvas"> & {
  ref?: React.Ref<ConfettiRef>
  options?: ConfettiOptions
  globalOptions?: ConfettiGlobalOptions
  manualstart?: boolean
  children?: ReactNode
}

const ConfettiContext = createContext<Api>({} as Api)

function Confetti({
  ref,
  options,
  globalOptions = { resize: true, useWorker: true },
  manualstart = false,
  children,
  ...props
}: ConfettiProps) {
  const instanceRef = useRef<ConfettiInstance | null>(null)

  const canvasRef = useCallback(
    (node: HTMLCanvasElement | null) => {
      if (node !== null) {
        if (instanceRef.current) return
        instanceRef.current = confetti.create(node, {
          ...globalOptions,
          resize: true,
        })
      } else {
        if (instanceRef.current) {
          instanceRef.current.reset()
          instanceRef.current = null
        }
      }
    },
    [globalOptions]
  )

  const fire = useCallback(
    async (opts: ConfettiOptions = {}) => {
      try {
        await instanceRef.current?.({ ...options, ...opts })
      } catch (error) {
        console.error("Confetti error:", error)
      }
    },
    [options]
  )

  const api = useMemo(() => ({ fire }), [fire])

  useImperativeHandle(ref, () => api, [api])

  useEffect(() => {
    if (!manualstart) {
      ;(async () => {
        try {
          await fire()
        } catch (error) {
          console.error("Confetti effect error:", error)
        }
      })()
    }
  }, [manualstart, fire])

  return (
    <ConfettiContext.Provider value={api}>
      <canvas data-slot="confetti" ref={canvasRef} {...props} />
      {children}
    </ConfettiContext.Provider>
  )
}

function ConfettiButton({
  options,
  children,
  ...props
}: React.ComponentProps<"button"> & {
  options?: ConfettiOptions &
    ConfettiGlobalOptions & { canvas?: HTMLCanvasElement }
}) {
  const handleClick = async (event: React.MouseEvent<HTMLButtonElement>) => {
    try {
      const rect = event.currentTarget.getBoundingClientRect()
      const x = rect.left + rect.width / 2
      const y = rect.top + rect.height / 2
      await confetti({
        ...options,
        origin: {
          x: x / window.innerWidth,
          y: y / window.innerHeight,
        },
      })
    } catch (error) {
      console.error("Confetti button error:", error)
    }
  }

  return (
    <Button data-slot="confetti-button" onClick={handleClick} {...props}>
      {children}
    </Button>
  )
}

export { Confetti, ConfettiButton }
