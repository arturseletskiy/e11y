<script lang="ts">
  import type { Snippet } from "svelte"

  type Props = {
    open: boolean
    onclose: () => void
    title: string
    headerExtra?: Snippet
    children: Snippet
  }

  let { open, onclose, title, headerExtra, children }: Props = $props()
</script>

{#if open}
  <div class="e11y-backdrop" role="presentation">
    <div
      class="e11y-sheet e11y-sheet--open"
      role="dialog"
      aria-modal="true"
      aria-label={title}
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
