<script lang="ts">
  import type { ListSeverityFilter } from "../lib/listFilter"

  let {
    search = $bindable(""),
    severity = $bindable<ListSeverityFilter>("all"),
    placeholder = "Search...",
    class: className = "",
  } = $props()

  const severities: { id: ListSeverityFilter; label: string; dotClass: string }[] = [
    { id: "all", label: "All", dotClass: "e11y-chip-dot--all" },
    { id: "error", label: "Error", dotClass: "e11y-chip-dot--err" },
    { id: "warn", label: "Warn", dotClass: "e11y-chip-dot--warn" },
    { id: "rest", label: "Other", dotClass: "e11y-chip-dot--rest" },
  ]
</script>

<div class="e11y-list-filters {className}">
  <input
    type="search"
    class="e11y-search"
    {placeholder}
    bind:value={search}
    aria-label="Search"
  />
  {#each severities as s (s.id)}
    <button
      type="button"
      class="e11y-chip e11y-chip--{s.id}"
      class:e11y-chip--active={severity === s.id}
      onclick={() => (severity = s.id)}
    >
      <i class="e11y-chip-dot {s.dotClass}"></i>
      {s.label}
    </button>
  {/each}
</div>
