<script lang="ts">
  import { cubicOut } from "svelte/easing"
  import { fade, scale } from "svelte/transition"
  import type { Snippet } from "svelte"

  type Props = {
    open: boolean
    onclose: () => void
    title: string
    headerExtra?: Snippet
    children: Snippet
  }

  let { open, onclose, title, headerExtra, children }: Props = $props()

  function motionOk(): boolean {
    return typeof matchMedia === "undefined" || !matchMedia("(prefers-reduced-motion: reduce)").matches
  }

  const fadeMs = $derived(motionOk() ? 220 : 0)
  const sheetMs = $derived(motionOk() ? 460 : 0)
  const sheetDelay = $derived(motionOk() ? 40 : 0)
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div
    class="e11y-backdrop"
    role="presentation"
    onclick={onclose}
    in:fade={{ duration: fadeMs }}
    out:fade={{ duration: Math.min(fadeMs, 160) }}
  >
    <div
      class="e11y-sheet"
      role="dialog"
      aria-modal="true"
      aria-label={title}
      tabindex="-1"
      onclick={(e) => e.stopPropagation()}
      in:scale={{
        duration: sheetMs,
        delay: sheetDelay,
        start: 0.06,
        opacity: 0.88,
        easing: cubicOut,
      }}
      out:scale={{
        duration: Math.min(sheetMs, 280),
        start: 0.92,
        opacity: 0.9,
        easing: cubicOut,
      }}
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
