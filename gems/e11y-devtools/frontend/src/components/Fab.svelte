<script lang="ts">
  type Props = {
    label: string
    onclick: () => void
    stateClass: "" | "e11y-fab--state-warn" | "e11y-fab--state-err"
    pulseClass: "" | "e11y-fab--pulse-warn" | "e11y-fab--pulse-error"
  }

  let { label, onclick, stateClass, pulseClass }: Props = $props()
</script>

<button
  type="button"
  class="e11y-fab {stateClass} {pulseClass}"
  onclick={onclick}
  aria-label="Open e11y devtools"
>
  {label}
</button>
