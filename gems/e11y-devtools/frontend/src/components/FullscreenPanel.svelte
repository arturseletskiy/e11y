<script lang="ts">
  import type { Snippet } from "svelte"
  import { circleCollapse, circleExpand, type CircleOrigin } from "../lib/transitions"
  import { originFallbackFabCorner } from "../lib/viewportOrigin"

  type Props = {
    open: boolean
    onclose: () => void
    title: string
    /** Circle reveal origin (FAB center + radius); falls back if null. */
    origin: CircleOrigin | null
    headerExtra?: Snippet
    children: Snippet
  }

  let { open, onclose, title, headerExtra, children, origin }: Props = $props()

  function motionOk(): boolean {
    return typeof matchMedia === "undefined" || !matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  const o = $derived(origin ?? originFallbackFabCorner())
  const openMs = $derived(motionOk() ? 440 : 0)
  const closeMs = $derived(motionOk() ? 360 : 0)

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === "Escape") onclose()
  }

  $effect(() => {
    if (!open) return
    window.addEventListener("keydown", handleKeydown)
    return () => window.removeEventListener("keydown", handleKeydown)
  })
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div
    class="e11y-backdrop"
    role="presentation"
    onclick={onclose}
    in:circleExpand={{ ...o, duration: openMs }}
    out:circleCollapse={{ ...o, duration: closeMs }}
  >
    <div
      class="e11y-sheet"
      role="dialog"
      aria-modal="true"
      aria-label={title}
      tabindex="-1"
      onclick={(e) => e.stopPropagation()}
    >
      <div class="e11y-panel-header">
        <span class="e11y-panel-title">{title}</span>
        {#if headerExtra}
          {@render headerExtra()}
        {/if}
        <button type="button" class="e11y-icon-btn" onclick={onclose} aria-label="Close"
          >&times;</button
        >
      </div>
      <div class="e11y-panel-body">
        {@render children()}
      </div>
    </div>
  </div>
{/if}
