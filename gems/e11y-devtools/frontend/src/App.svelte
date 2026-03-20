<script lang="ts">
  import Fab from "./components/Fab.svelte"
  import FullscreenPanel from "./components/FullscreenPanel.svelte"
  import { fetchInteractions, fetchRecent, fetchTraceEvents } from "./lib/api"
  import { formatInteractionStarted, summarizeTraceIds } from "./lib/format"
  import { eventKey } from "./lib/eventIdentity"
  import type { OverlayRoute, SourceFilter } from "./lib/router"

  let panelOpen = $state(false)
  let source = $state<SourceFilter>("web")
  let route = $state<OverlayRoute>({ screen: "interactions" })
  let interactions = $state<Record<string, unknown>[]>([])
  let events = $state<Record<string, unknown>[]>([])
  let recentEvents = $state<Record<string, unknown>[]>([])
  let loadError = $state<string | null>(null)

  let prevRecentKeys = $state<Set<string>>(new Set())
  let firstRecentPoll = $state(true)
  let pulseKind = $state<"none" | "error" | "warn">("none")
  let pulseTimer: ReturnType<typeof setTimeout> | null = null

  const POLL_MS = 2000
  const PULSE_MS = 3000

  function severityRank(s: "none" | "error" | "warn"): number {
    if (s === "error") return 2
    if (s === "warn") return 1
    return 0
  }

  function applyPulse(next: "error" | "warn"): void {
    if (pulseTimer) clearTimeout(pulseTimer)
    if (severityRank(next) >= severityRank(pulseKind)) pulseKind = next
    pulseTimer = setTimeout(() => {
      pulseKind = "none"
      pulseTimer = null
    }, PULSE_MS)
  }

  function processRecentForPulse(rows: Record<string, unknown>[]): void {
    const nextKeys = new Set<string>()
    rows.forEach((e, i) => nextKeys.add(eventKey(e, i)))

    if (firstRecentPoll) {
      firstRecentPoll = false
      prevRecentKeys = nextKeys
      return
    }

    let sawNewError = false
    let sawNewWarn = false
    for (let i = 0; i < rows.length; i++) {
      const e = rows[i]
      const k = eventKey(e, i)
      if (!prevRecentKeys.has(k)) {
        const sev = e.severity
        if (sev === "error" || sev === "fatal") sawNewError = true
        else if (sev === "warn") sawNewWarn = true
      }
    }
    prevRecentKeys = nextKeys
    if (sawNewError) applyPulse("error")
    else if (sawNewWarn) applyPulse("warn")
  }

  function countsFromRecent(rows: Record<string, unknown>[]): {
    total: number
    err: number
    warn: number
  } {
    let err = 0
    let warn = 0
    for (const e of rows) {
      const s = e.severity
      if (s === "error" || s === "fatal") err++
      else if (s === "warn") warn++
    }
    return { total: rows.length, err, warn }
  }

  async function pollRecent(): Promise<void> {
    try {
      const rows = await fetchRecent()
      recentEvents = rows
      processRecentForPulse(rows)
      loadError = null
    } catch {
      /* ignore transient poll failures */
    }
  }

  async function loadInteractionsList(): Promise<void> {
    try {
      interactions = await fetchInteractions(source)
      loadError = null
    } catch (e) {
      loadError = String(e)
    }
  }

  async function openTraceFromInteraction(row: Record<string, unknown>): Promise<void> {
    const ids = row.trace_ids as string[] | undefined
    const tid = ids?.[0]
    if (!tid) return
    try {
      events = await fetchTraceEvents(tid)
      route = { screen: "events", traceId: tid }
    } catch (e) {
      loadError = String(e)
    }
  }

  function selectEvent(ev: Record<string, unknown>): void {
    if (route.screen !== "events") return
    route = { screen: "detail", traceId: route.traceId, event: ev }
  }

  function back(): void {
    if (route.screen === "detail") {
      route = { screen: "events", traceId: route.traceId }
    } else if (route.screen === "events") {
      route = { screen: "interactions" }
    }
  }

  function togglePanel(): void {
    panelOpen = !panelOpen
    if (panelOpen) {
      route = { screen: "interactions" }
      void loadInteractionsList()
    }
  }

  async function copyDetailJson(): Promise<void> {
    if (route.screen !== "detail") return
    const text = JSON.stringify(route.event, null, 2)
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      /* ignore */
    }
  }

  let panelTitle = $derived.by(() => {
    if (route.screen === "interactions") return "e11y — interactions"
    if (route.screen === "events") return `e11y — trace ${route.traceId}`
    return "e11y — event"
  })

  let badgeLabel = $derived.by(() => {
    const { total, err, warn } = countsFromRecent(recentEvents)
    if (total === 0) return "e11y"
    const parts: string[] = [`e11y ${total}`]
    if (warn) parts.push(`${warn}⚠`)
    if (err) parts.push(`${err}✕`)
    return parts.join(" · ")
  })

  let fabStateClass = $derived.by((): "" | "e11y-fab--state-warn" | "e11y-fab--state-err" => {
    const { err, warn } = countsFromRecent(recentEvents)
    if (err) return "e11y-fab--state-err"
    if (warn) return "e11y-fab--state-warn"
    return ""
  })

  let fabPulseClass = $derived.by((): "" | "e11y-fab--pulse-error" | "e11y-fab--pulse-warn" => {
    if (pulseKind === "error") return "e11y-fab--pulse-error"
    if (pulseKind === "warn") return "e11y-fab--pulse-warn"
    return ""
  })

  function sevClass(sev: unknown): string {
    const s = String(sev ?? "info")
    if (s === "error" || s === "fatal") return "e11y-sev--error"
    if (s === "warn") return "e11y-sev--warn"
    return "e11y-sev--info"
  }

  function interactionRowKey(row: Record<string, unknown>): string {
    const ids = (row.trace_ids as string[] | undefined) ?? []
    return `${row.started_at ?? ""}|${ids.join(",")}`
  }

  function sourcePillClass(src: unknown): string {
    const s = String(src ?? "")
    if (s === "web") return "e11y-pill e11y-pill--web"
    if (s === "job") return "e11y-pill e11y-pill--job"
    return "e11y-pill"
  }

  $effect(() => {
    const id = setInterval(() => void pollRecent(), POLL_MS)
    void pollRecent()
    return () => clearInterval(id)
  })

  $effect(() => {
    if (!panelOpen) return
    void loadInteractionsList()
  })

  $effect(() => {
    source
    if (panelOpen) void loadInteractionsList()
  })

  $effect(() => {
    if (!panelOpen) return
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") panelOpen = false
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  })
</script>

<div class="e11y-dt">
  <Fab label={badgeLabel} onclick={togglePanel} stateClass={fabStateClass} pulseClass={fabPulseClass} />

  <FullscreenPanel open={panelOpen} onclose={() => (panelOpen = false)} title={panelTitle}>
    {#snippet headerExtra()}
      <div class="e11y-chip-row">
        {#each ["web", "job", "all"] as s (s)}
          <button
            type="button"
            class="e11y-chip"
            class:e11y-chip--active={source === s}
            onclick={() => (source = s as SourceFilter)}
          >
            {s}
          </button>
        {/each}
      </div>
    {/snippet}

    {#snippet children()}
      {#if loadError}
        <p class="e11y-err-msg">{loadError}</p>
      {/if}

      {#if route.screen !== "interactions"}
        <div class="e11y-toolbar">
          <button type="button" class="e11y-btn" onclick={back}>← Back</button>
        </div>
      {/if}

      {#if route.screen === "interactions"}
        {#each interactions as row (interactionRowKey(row))}
          {@const ids = (row.trace_ids as string[] | undefined) ?? []}
          {@const tc = Number(row.traces_count ?? ids.length)}
          {@const { absolute, relative } = formatInteractionStarted(String(row.started_at ?? ""))}
          {@const { primary, extra, preview } = summarizeTraceIds(ids)}
          <div
            class="e11y-ix"
            class:e11y-ix--error={!!row.has_error}
            role="button"
            tabindex="0"
            onclick={() => void openTraceFromInteraction(row)}
            onkeydown={(e) => e.key === "Enter" && void openTraceFromInteraction(row)}
          >
            <div class="e11y-ix-main">
              <div class="e11y-ix-time">
                <span class="e11y-ix-time-abs">{absolute}</span>
                {#if relative}
                  <span class="e11y-ix-time-rel">{relative}</span>
                {/if}
              </div>
              <div class="e11y-ix-trace-line">
                <code class="e11y-ix-trace-primary" title="First trace_id (drill-down target)">{primary}</code>
                {#if extra > 0}
                  <span class="e11y-muted">+{extra} parallel</span>
                {/if}
              </div>
              {#if preview && ids.length > 1}
                <div class="e11y-ix-preview" title="All trace ids in this interaction window">{preview}</div>
              {/if}
              <div class="e11y-ix-hint">Click → events for first trace (same as TUI)</div>
            </div>
            <div class="e11y-ix-aside">
              <span class={sourcePillClass(row.source)}>{String(row.source ?? "?")}</span>
              {#if row.has_error}
                <span class="e11y-pill e11y-pill--err">Has errors</span>
              {:else}
                <span class="e11y-pill e11y-pill--ok">Clean</span>
              {/if}
              <span class="e11y-ix-count" title="Traces in group">{tc} trace{tc === 1 ? "" : "s"}</span>
            </div>
          </div>
        {/each}
      {:else if route.screen === "events"}
        {#each events as ev, i (eventKey(ev, i))}
          <div
            class="e11y-row"
            role="button"
            tabindex="0"
            onclick={() => selectEvent(ev)}
            onkeydown={(e) => e.key === "Enter" && selectEvent(ev)}
          >
            <span class="e11y-sev {sevClass(ev.severity)}">{String(ev.severity ?? "?")}</span>
            <span class="e11y-row-title">{String(ev.event_name ?? "")}</span>
            <span class="e11y-row-meta">{String(ev.timestamp ?? "")}</span>
          </div>
        {/each}
      {:else if route.screen === "detail"}
        <div class="e11y-toolbar">
          <button type="button" class="e11y-btn" onclick={() => void copyDetailJson()}>Copy JSON</button>
        </div>
        <pre class="e11y-detail-pre">{JSON.stringify(route.event, null, 2)}</pre>
      {/if}
    {/snippet}
  </FullscreenPanel>
</div>
