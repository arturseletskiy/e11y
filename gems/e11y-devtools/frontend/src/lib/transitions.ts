import { cubicInOut } from "svelte/easing"
import type { TransitionConfig } from "svelte/transition"

export type CircleOrigin = { x: number; y: number; r: number }

/** Circular reveal from (x,y) — same idea as Magic UI theme toggler (clip-path expand). */
export function circleExpand(
  _node: Element,
  { x, y, r, duration }: CircleOrigin & { duration: number }
): TransitionConfig {
  return {
    duration,
    easing: cubicInOut,
    css: (t) => {
      const radius = Math.max(0, t * r)
      return `clip-path: circle(${radius}px at ${x}px ${y}px);`
    },
  }
}

/** Circular collapse back toward (x,y). */
export function circleCollapse(
  _node: Element,
  { x, y, r, duration }: CircleOrigin & { duration: number }
): TransitionConfig {
  return {
    duration,
    easing: cubicInOut,
    css: (t) => {
      const radius = Math.max(0, t * r)
      return `clip-path: circle(${radius}px at ${x}px ${y}px);`
    },
  }
}
