<script lang="ts">
  import { Copy, TerminalSquare, Database, FileJson } from "lucide-svelte"

  let { event } = $props<{ event: Record<string, any> }>()

  let activeTab = $state<"overview" | "raw">("overview")

  const payload = $derived(event.payload || {})
  const metadata = $derived(event.metadata || {})

  // Extract common Sentry-like fields
  const exception = $derived(payload.exception || payload.error)
  const stacktrace = $derived(payload.stacktrace || exception?.backtrace)

  async function copyText(text: string) {
    try {
      await navigator.clipboard.writeText(text)
    } catch {}
  }
</script>

<div class="flex flex-col h-full bg-e11y-bg text-e11y-text rounded-lg border border-e11y-border overflow-hidden">
  <!-- Header -->
  <div class="flex items-center justify-between px-4 py-3 border-b border-e11y-border bg-e11y-bg2">
    <div class="flex items-center gap-3">
      <span
        class="px-2 py-1 text-xs font-bold uppercase rounded {event.severity === 'error'
          ? 'bg-e11y-err-bg text-e11y-err'
          : 'bg-e11y-accent-bg text-e11y-accent'}"
      >
        {event.severity || "info"}
      </span>
      <h2 class="text-sm font-semibold truncate">{event.event_name}</h2>
    </div>
  </div>

  <!-- Tabs -->
  <div class="flex border-b border-e11y-border px-2">
    <button
      class="px-4 py-2 text-xs font-medium border-b-2 {activeTab === 'overview'
        ? 'border-e11y-accent text-e11y-accent'
        : 'border-transparent text-e11y-muted hover:text-e11y-text'}"
      onclick={() => (activeTab = "overview")}
    >
      <div class="flex items-center gap-1.5"><TerminalSquare size={14} /> Overview</div>
    </button>
    <button
      class="px-4 py-2 text-xs font-medium border-b-2 {activeTab === 'raw'
        ? 'border-e11y-accent text-e11y-accent'
        : 'border-transparent text-e11y-muted hover:text-e11y-text'}"
      onclick={() => (activeTab = "raw")}
    >
      <div class="flex items-center gap-1.5"><FileJson size={14} /> Raw JSON</div>
    </button>
  </div>

  <!-- Content -->
  <div class="flex-1 overflow-y-auto p-4">
    {#if activeTab === "overview"}
      <div class="space-y-6">
        <!-- Tags / Meta -->
        <div class="flex flex-wrap gap-4 text-xs">
          <div class="flex flex-col gap-1">
            <span class="text-e11y-muted">Trace ID</span>
            <button
              class="font-mono text-e11y-accent hover:underline flex items-center gap-1"
              onclick={() => copyText(String(event.trace_id ?? ""))}
            >
              {event.trace_id || "—"} <Copy size={12} />
            </button>
          </div>
          {#if event.span_id}
            <div class="flex flex-col gap-1">
              <span class="text-e11y-muted">Span ID</span>
              <button
                class="font-mono text-e11y-accent hover:underline flex items-center gap-1"
                onclick={() => copyText(String(event.span_id ?? ""))}
              >
                {event.span_id} <Copy size={12} />
              </button>
            </div>
          {/if}
          <div class="flex flex-col gap-1">
            <span class="text-e11y-muted">Timestamp</span>
            <span>{event.timestamp || "—"}</span>
          </div>
          {#if metadata.request_id}
            <div class="flex flex-col gap-1">
              <span class="text-e11y-muted">Request ID</span>
              <span class="font-mono">{metadata.request_id}</span>
            </div>
          {/if}
        </div>

        <!-- Exception / Message -->
        {#if exception}
          <div class="space-y-2">
            <h3 class="text-sm font-semibold text-e11y-err flex items-center gap-1.5">
              <Database size={14} /> Exception
            </h3>
            <div class="p-3 bg-e11y-err-bg border border-e11y-err/30 rounded-md text-xs font-mono whitespace-pre-wrap">
              {typeof exception === "string"
                ? exception
                : exception.message || JSON.stringify(exception)}
            </div>
          </div>
        {/if}

        <!-- Stacktrace -->
        {#if stacktrace}
          <div class="space-y-2">
            <h3 class="text-sm font-semibold flex items-center gap-1.5">Stacktrace</h3>
            <div class="p-3 bg-e11y-input border border-e11y-border rounded-md text-xs font-mono overflow-x-auto">
              {#if Array.isArray(stacktrace)}
                {#each stacktrace as frame}
                  <div class="py-0.5 border-b border-e11y-border/50 last:border-0">
                    {typeof frame === "string" ? frame : JSON.stringify(frame)}
                  </div>
                {/each}
              {:else}
                <pre>{stacktrace}</pre>
              {/if}
            </div>
          </div>
        {/if}
      </div>
    {:else}
      <div class="relative">
        <button
          class="absolute top-2 right-2 p-1.5 bg-e11y-bg hover:bg-e11y-hover border border-e11y-border rounded text-e11y-muted"
          onclick={() => copyText(JSON.stringify(event, null, 2))}
          title="Copy JSON"
        >
          <Copy size={14} />
        </button>
        <pre
          class="p-4 bg-e11y-input border border-e11y-border rounded-md text-xs font-mono overflow-x-auto text-e11y-text">{JSON.stringify(
            event,
            null,
            2
          )}</pre>
      </div>
    {/if}
  </div>
</div>
