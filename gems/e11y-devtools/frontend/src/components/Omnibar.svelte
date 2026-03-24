<script lang="ts">
  import { Search, XCircle } from "lucide-svelte"
  import type { ListSeverityFilter } from "../lib/listFilter"

  let {
    search = $bindable(""),
    severity = $bindable<ListSeverityFilter>("all"),
    placeholder = "Search (e.g. is:error source:web)...",
  } = $props()

  const severities = [
    { id: "all", label: "All", color: "bg-e11y-muted" },
    { id: "error", label: "Error", color: "bg-e11y-err" },
    { id: "warn", label: "Warn", color: "bg-e11y-warn" },
    { id: "rest", label: "Other", color: "bg-e11y-ok" },
  ] as const

  function clearSearch() {
    search = ""
  }
</script>

<div class="flex items-center gap-3 bg-e11y-input border border-e11y-border rounded-md px-3 py-1.5 focus-within:border-e11y-accent focus-within:ring-1 focus-within:ring-e11y-accent transition-all">
  <Search size={16} class="text-e11y-muted flex-shrink-0" />

  <input
    type="text"
    class="flex-1 bg-transparent border-none outline-none text-sm text-e11y-text placeholder:text-e11y-muted/50"
    {placeholder}
    bind:value={search}
  />

  {#if search}
    <button type="button" onclick={clearSearch} class="text-e11y-muted hover:text-e11y-text">
      <XCircle size={14} />
    </button>
  {/if}

  <div class="w-px h-4 bg-e11y-border mx-1"></div>

  <div class="flex items-center gap-1">
    {#each severities as s (s.id)}
      <button
        type="button"
        class="flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium transition-colors border {severity === s.id ? 'border-e11y-accent bg-e11y-accent-bg text-e11y-text' : 'border-transparent text-e11y-muted hover:bg-e11y-hover'}"
        onclick={() => (severity = s.id)}
      >
        <span class="w-2 h-2 rounded-full {s.color}"></span>
        {s.label}
      </button>
    {/each}
  </div>
</div>
