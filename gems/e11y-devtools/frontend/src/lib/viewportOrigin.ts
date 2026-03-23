import type { CircleOrigin } from "./transitions"

/** Circle origin from FAB button (center + radius to farthest viewport corner). */
export function originFromFabButton(el: HTMLButtonElement): CircleOrigin {
  const { top, left, width, height } = el.getBoundingClientRect()
  const x = left + width / 2
  const y = top + height / 2
  const vw = typeof window !== "undefined" ? (window.visualViewport?.width ?? window.innerWidth) : 800
  const vh = typeof window !== "undefined" ? (window.visualViewport?.height ?? window.innerHeight) : 600
  const r = Math.hypot(Math.max(x, vw - x), Math.max(y, vh - y))
  return { x, y, r }
}

/** Fallback when opening without a click target (e.g. programmatic). ~bottom-right FAB. */
export function originFallbackFabCorner(): CircleOrigin {
  const vw = typeof window !== "undefined" ? (window.visualViewport?.width ?? window.innerWidth) : 800
  const vh = typeof window !== "undefined" ? (window.visualViewport?.height ?? window.innerHeight) : 600
  const margin = 16
  const halfW = 70
  const halfH = 22
  const x = vw - margin - halfW
  const y = vh - margin - halfH
  const r = Math.hypot(Math.max(x, vw - x), Math.max(y, vh - y))
  return { x, y, r }
}
