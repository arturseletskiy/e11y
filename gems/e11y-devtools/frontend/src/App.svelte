<script lang="ts">
  import Fab from "./components/Fab.svelte"
  import Omnibar from "./components/Omnibar.svelte"
  import FullscreenPanel from "./components/FullscreenPanel.svelte"
  import InteractionsTimeline, { type TimelineTimeRange } from "./components/InteractionsTimeline.svelte"
  import RecentHistogram from "./components/RecentHistogram.svelte"
  import { fetchInteractions, fetchRecent, fetchTraceEvents } from "./lib/api"
  import { eventKey } from "./lib/eventIdentity"
  import { formatInteractionStarted, summarizeTraceIds } from "./lib/format"
  import { filterEventList, type ListSeverityFilter } from "./lib/listFilter"
  import { buildRecentVolumeBuckets, eventTimestampMs, type HistogramTimeRange } from "./lib/recentVolume"
  import type { OverlayRoute, SourceFilter } from "./lib/router"
  import type { CircleOrigin } from "./lib/transitions"
  import { originFallbackFabCorner, originFromFabButton } from "./lib/viewportOrigin"

  const SPLIT_MIN_PX = 900

  let panelOpen = $state(false)
  let panelCircleOrigin = $state<CircleOrigin | null>(null)
  let source = $state<SourceFilter>("web")
  let route = $state<OverlayRoute>({ screen: "interactions" })
  let interactions = $state<Record<string, unknown>[]>([])
  let events = $state<Record<string, unknown>[]>([])
  let recentEvents = $state<Record<string, unknown>[]>([])
  let loadError = $state<string | null>(null)
  /** Selected interaction row key when using wide split layout. */
  let splitSelectedKey = $state<string | null>(null)
  let layoutWide = $state(false)

  /** Global text search and severity filter across all lists. */
  let globalSearch = $state("")
  let globalSeverity = $state<ListSeverityFilter>("all")

  let rowExpanded = $state<Record<string, boolean>>({})
  /** Index in the current filtered trace list; neighbors ±2 highlighted after returning from detail. */
  let contextAnchorIndex = $state<number | null>(null)

  /** Problems-tab histogram: filter errors to [startMs, endMs] (UTC, inclusive). */
  let histogramTimeRange = $state<HistogramTimeRange | null>(null)

  /** Interactions-tab timeline: filter interactions to [startMs, endMs] (UTC, inclusive). */
  let interactionsTimeRange = $state<TimelineTimeRange | null>(null)

  let prevRecentKeys = $state<Set<string>>(new Set())
  let firstRecentPoll = $state(true)
  let pulseKind = $state<"none" | "error" | "warn">("none")
  let pulseTimer: ReturnType<typeof setTimeout> | null = null

  const POLL_MS = 2000
  const PULSE_MS = 3000

  let problemEvents = $derived.by(() =>
    recentEvents.filter((e) => e.severity === "error" || e.severity === "fatal")
  )

  let filteredInteractions = $derived.by(() => {
    let rows = interactions

    if (interactionsTimeRange) {
      const { startMs, endMs } = interactionsTimeRange
      rows = rows.filter((i) => {
        const t = new Date(String(i.started_at || "")).getTime()
        if (isNaN(t)) return false
        return t >= startMs && t <= endMs
      })
    }

    if (globalSeverity !== "all") {
      rows = rows.filter((i) => {
        const s = Number(i.status) || 200
        const hasErr = !!i.has_error
        if (globalSeverity === "error") return s >= 500 || hasErr
        if (globalSeverity === "warn") return s >= 400 && s < 500
        if (globalSeverity === "rest") return s < 400 && !hasErr
        return true
      })
    }

    const q = globalSearch.trim().toLowerCase()
    if (q) {
      rows = rows.filter((i) => {
        const path = String(i.path || "").toLowerCase()
        const method = String(i.method || "").toLowerCase()
        const traceIds = ((i.trace_ids as string[]) || []).join(" ").toLowerCase()
        return path.includes(q) || method.includes(q) || traceIds.includes(q)
      })
    }

    return rows
  })

  let filteredProblemEvents = $derived.by(() => {
    let rows = filterEventList(problemEvents, globalSeverity, globalSearch)
    const r = histogramTimeRange
    if (r) {
      const buckets = buildRecentVolumeBuckets(recentEvents, 32)
      const n = buckets.length
      if (n === 0) {
        rows = []
      } else {
        const tMin = buckets[0].t0
        const tMax = buckets[n - 1].t1
        const w = (tMax - tMin) / n
        
        // If lo/hi are missing (e.g. old state), fallback to time-based filter
        if (r.lo == null || r.hi == null) {
          rows = rows.filter((ev) => {
            const t = eventTimestampMs(ev)
            if (t == null) return false
            return t >= r.startMs && t <= r.endMs
          })
        } else {
          const lo = Math.max(0, Math.min(r.lo, n - 1))
          const hi = Math.max(0, Math.min(r.hi, n - 1))
          const i0 = Math.min(lo, hi)
          const i1 = Math.max(lo, hi)
          rows = rows.filter((ev) => {
            const t = eventTimestampMs(ev)
            if (t == null) return false
            const idx = Math.min(n - 1, Math.max(0, Math.floor((t - tMin) / w)))
            return idx >= i0 && idx <= i1
          })
        }
      }
    }
    return rows
  })

  let filteredTraceEvents = $derived.by(() =>
    filterEventList(events, globalSeverity, globalSearch)
  )

  let activeTraceId = $derived.by(() => {
    if (route.screen === "events") return route.traceId
    return String((events[0] as Record<string, unknown> | undefined)?.trace_id ?? "")
  })

  const CONTEXT_RADIUS = 2

  $effect(() => {
    globalSearch
    globalSeverity
    contextAnchorIndex = null
  })

  $effect(() => {
    const mq = window.matchMedia(`(min-width: ${SPLIT_MIN_PX}px)`)
    const sync = (): void => {
      layoutWide = mq.matches
    }
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  })

  /** If viewport becomes narrow while split view had a selection, fall back to full-screen events list. */
  $effect(() => {
    if (layoutWide) return
    if (route.screen !== "interactions" || !splitSelectedKey) return
    const tid = events[0] && String((events[0] as Record<string, unknown>).trace_id ?? "")
    if (tid) route = { screen: "events", traceId: tid }
  })

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

  function goTabProblems(): void {
    splitSelectedKey = null
    contextAnchorIndex = null
    route = { screen: "problems" }
  }

  function goTabInteractions(): void {
    splitSelectedKey = null
    contextAnchorIndex = null
    histogramTimeRange = null
    events = []
    route = { screen: "interactions" }
    void loadInteractionsList()
  }

  async function onInteractionRowClick(row: Record<string, unknown>): Promise<void> {
    const ids = row.trace_ids as string[] | undefined
    const tid = ids?.[0]
    if (!tid) return
    const key = interactionRowKey(row)
    try {
      contextAnchorIndex = null
      events = await fetchTraceEvents(tid)
      if (layoutWide) {
        splitSelectedKey = key
        route = { screen: "interactions" }
      } else {
        splitSelectedKey = null
        route = { screen: "events", traceId: tid }
      }
    } catch (e) {
      loadError = String(e)
    }
  }

  function openProblemDetail(ev: Record<string, unknown>): void {
    const tid = String(ev.trace_id ?? "")
    route = { screen: "detail", traceId: tid, event: ev, detailFrom: "problems" }
  }

  function selectEvent(ev: Record<string, unknown>, indexInFiltered: number): void {
    const tid = String(ev.trace_id ?? "")
    contextAnchorIndex = indexInFiltered
    if (route.screen === "events") {
      route = { screen: "detail", traceId: route.traceId, event: ev, detailFrom: "events" }
      return
    }
    if (route.screen === "interactions" && layoutWide && splitSelectedKey) {
      route = { screen: "detail", traceId: tid, event: ev, detailFrom: "events" }
    }
  }

  function back(): void {
    if (route.screen === "detail") {
      if (route.detailFrom === "problems") {
        route = { screen: "problems" }
      } else if (layoutWide && splitSelectedKey) {
        route = { screen: "interactions" }
      } else {
        route = { screen: "events", traceId: route.traceId }
      }
      return
    }
    if (route.screen === "events") {
      splitSelectedKey = null
      route = { screen: "interactions" }
    }
  }

  function fabClick(e: MouseEvent): void {
    const el = e.currentTarget
    if (panelOpen) {
      if (el instanceof HTMLButtonElement) panelCircleOrigin = originFromFabButton(el)
      panelOpen = false
      return
    }
    if (el instanceof HTMLButtonElement) {
      panelCircleOrigin = originFromFabButton(el)
    } else {
      panelCircleOrigin = originFallbackFabCorner()
    }
    panelOpen = true
    splitSelectedKey = null
    const { err } = countsFromRecent(recentEvents)
    if (err > 0) {
      route = { screen: "problems" }
    } else {
      histogramTimeRange = null
      route = { screen: "interactions" }
    }
    void loadInteractionsList()
  }

  async function copyText(text: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      /* ignore */
    }
  }

  async function copyDetailJson(): Promise<void> {
    if (route.screen !== "detail") return
    await copyText(JSON.stringify(route.event, null, 2))
  }

  async function copyDetailTraceId(): Promise<void> {
    if (route.screen !== "detail") return
    const tid = String(route.event.trace_id ?? "")
    if (tid) await copyText(tid)
  }

  async function copyDetailRequestId(): Promise<void> {
    if (route.screen !== "detail") return
    const m = route.event.metadata as Record<string, unknown> | undefined
    const rid = m && typeof m.request_id === "string" ? m.request_id : ""
    if (rid) await copyText(rid)
  }

  function toggleRowExpand(key: string, e: MouseEvent): void {
    e.stopPropagation()
    rowExpanded = { ...rowExpanded, [key]: !rowExpanded[key] }
  }

  function payloadSummary(ev: Record<string, unknown>): string {
    const p = ev.payload
    if (p && typeof p === "object" && !Array.isArray(p)) {
      const o = p as Record<string, unknown>
      const msg = o.message
      if (typeof msg === "string" && msg.length > 0) {
        return msg.length > 140 ? `${msg.slice(0, 137)}…` : msg
      }
    }
    try {
      const s = JSON.stringify(p)
      return s.length > 120 ? `${s.slice(0, 117)}…` : s
    } catch {
      return ""
    }
  }

  function isContextNeighbor(indexInFiltered: number): boolean {
    if (contextAnchorIndex === null) return false
    if (!activeTraceId) return false
    return Math.abs(indexInFiltered - contextAnchorIndex) <= CONTEXT_RADIUS
  }

  let panelTitle = $derived.by(() => {
    if (route.screen === "problems") return "e11y — problems"
    if (route.screen === "interactions") return "e11y — interactions"
    if (route.screen === "events") return `e11y — trace ${route.traceId}`
    if (route.screen === "detail") return `e11y — ${String(route.event.event_name ?? "event")}`
    return "e11y"
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

  let tabProblemsActive = $derived.by(
    () => route.screen === "problems" || (route.screen === "detail" && route.detailFrom === "problems")
  )
  let tabInteractionsActive = $derived.by(
    () =>
      route.screen === "interactions" ||
      route.screen === "events" ||
      (route.screen === "detail" && route.detailFrom === "events")
  )

  let showTraceFilters = $derived.by(
    () =>
      route.screen === "events" ||
      (route.screen === "interactions" && layoutWide && !!splitSelectedKey)
  )

  let errCount = $derived.by(() => countsFromRecent(recentEvents).err)

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
</script>

<div class="e11y-dt">
  <Fab label={badgeLabel} onclick={fabClick} stateClass={fabStateClass} pulseClass={fabPulseClass} />

  <FullscreenPanel
    open={panelOpen}
    onclose={() => (panelOpen = false)}
    origin={panelCircleOrigin}
  >
    {#snippet headerTopLeft()}
      {#if route.screen === "events" || route.screen === "detail"}
        <button type="button" class="e11y-icon-btn" onclick={back} aria-label="Back" title="Go back" style="margin-right: -4px;">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 12H5M12 19l-7-7 7-7"/></svg>
        </button>
      {/if}

      <div class="e11y-tab-row" role="tablist">
        <button
          type="button"
          role="tab"
          class="e11y-tab"
          class:e11y-tab--active={tabProblemsActive}
          aria-selected={tabProblemsActive}
          onclick={goTabProblems}
        >
          Problems{#if errCount > 0}&nbsp;<span class="e11y-tab-badge">{errCount}</span>{/if}
        </button>
        <button
          type="button"
          role="tab"
          class="e11y-tab"
          class:e11y-tab--active={tabInteractionsActive}
          aria-selected={tabInteractionsActive}
          onclick={goTabInteractions}
        >
          Interactions
        </button>
      </div>

      {#if route.screen === "events" || route.screen === "detail"}
        <span class="e11y-breadcrumb-sep">/</span>
        <span class="e11y-panel-title e11y-panel-title--sub" title={activeTraceId || undefined}>
          {#if route.screen === "detail"}
            Event Details
          {:else}
            Trace: {activeTraceId ? activeTraceId.slice(0, 8) + "…" : "Unknown"}
          {/if}
        </span>
      {/if}
    {/snippet}

    {#snippet headerTopRight()}
      {#if route.screen === "detail"}
        <button type="button" class="e11y-btn" onclick={() => void copyDetailJson()}>Copy JSON</button>
        <button type="button" class="e11y-btn" onclick={() => void copyDetailTraceId()}>Copy trace_id</button>
        <button type="button" class="e11y-btn" onclick={() => void copyDetailRequestId()}>Copy request_id</button>
      {:else if tabInteractionsActive && route.screen === "interactions"}
        <div class="e11y-chip-row e11y-chip-row--header">
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
      {/if}
    {/snippet}

    {#snippet headerBottom()}
      <Omnibar
        bind:search={globalSearch}
        bind:severity={globalSeverity}
        placeholder={
          route.screen === "interactions"
            ? "Search paths, methods, traces..."
            : route.screen === "problems"
              ? "Search problems, traces..."
              : "Filter name, trace, payload..."
        }
      />
    {/snippet}

    {#snippet children()}
      {#if loadError}
        <p class="e11y-err-msg">{loadError}</p>
      {/if}

      {#if showTraceFilters}
        {#if contextAnchorIndex !== null}
          <p class="e11y-context-hint">
            Context: ±{CONTEXT_RADIUS} rows around last opened event (change filter to clear).
          </p>
        {/if}
      {/if}

      {#if route.screen === "problems"}
        <RecentHistogram bind:timeRange={histogramTimeRange} recent={recentEvents} />
        <p class="e11y-problems-hint">Recent error / fatal events from the dev log (newest first).</p>
        {#if problemEvents.length === 0}
          <p class="e11y-muted e11y-empty">No errors in the recent buffer.</p>
          <button type="button" class="e11y-btn" onclick={goTabInteractions}>Open interactions</button>
        {:else if filteredProblemEvents.length === 0}
          <p class="e11y-muted e11y-empty">
            {#if histogramTimeRange && !globalSearch.trim()}
              No errors in the selected time range. Widen the selection or clear it.
            {:else if globalSearch.trim()}
              No matches for this search (and current time range, if any).
            {:else}
              No matching errors.
            {/if}
          </p>
        {:else}
          {#each filteredProblemEvents as ev, i (eventKey(ev, i))}
            {@const tr = String(ev.trace_id ?? "")}
            {@const ek = eventKey(ev, i)}
            {@const sum = payloadSummary(ev)}
            <div
              class="e11y-row e11y-row--problem"
              role="button"
              tabindex="0"
              onclick={() => openProblemDetail(ev)}
              onkeydown={(e) => e.key === "Enter" && openProblemDetail(ev)}
            >
              <button
                type="button"
                class="e11y-row-expand"
                class:e11y-row-expand--open={rowExpanded[ek]}
                aria-expanded={!!rowExpanded[ek]}
                aria-label={rowExpanded[ek] ? "Collapse row" : "Expand row"}
                onclick={(e) => toggleRowExpand(ek, e)}>▸</button
              >
              <span class="e11y-sev {sevClass(ev.severity)}">{String(ev.severity ?? "?")}</span>
              <span class="e11y-row-title">{String(ev.event_name ?? "")}</span>
              <span class="e11y-row-meta e11y-mono" title={tr || undefined}
                >{tr.length > 14 ? `${tr.slice(0, 12)}…` : tr || "—"}</span
              >
              <span class="e11y-row-meta">{String(ev.timestamp ?? "")}</span>
              {#if rowExpanded[ek]}
                <div class="e11y-row-body">
                  {#if sum}<p class="e11y-row-sum">{sum}</p>{/if}
                  <pre class="e11y-row-pre">{JSON.stringify(ev.payload, null, 2)}</pre>
                </div>
              {/if}
            </div>
          {/each}
        {/if}
      {:else if route.screen === "interactions"}
        <InteractionsTimeline bind:timeRange={interactionsTimeRange} {interactions} />
        {#if layoutWide}
          <div class="e11y-split">
            <div class="e11y-split-primary">
              {#if interactions.length === 0}
                <p class="e11y-muted e11y-empty">No interactions recorded yet.</p>
              {:else if filteredInteractions.length === 0}
                <p class="e11y-muted e11y-empty">No interactions in the selected time range.</p>
              {:else}
                {#each filteredInteractions as row (interactionRowKey(row))}
                {@const ids = (row.trace_ids as string[] | undefined) ?? []}
                {@const tc = Number(row.traces_count ?? ids.length)}
                {@const { absolute, relative } = formatInteractionStarted(String(row.started_at ?? ""))}
                {@const { primary, extra, preview } = summarizeTraceIds(ids)}
                {@const ikey = interactionRowKey(row)}
                <div
                  class="e11y-ix"
                  class:e11y-ix--error={!!row.has_error}
                  class:e11y-ix--selected={splitSelectedKey === ikey}
                  role="button"
                  tabindex="0"
                  onclick={() => void onInteractionRowClick(row)}
                  onkeydown={(e) => e.key === "Enter" && void onInteractionRowClick(row)}
                >
                  <div class="e11y-ix-main">
                    <div class="e11y-ix-time">
                      <span class="e11y-ix-time-abs">{absolute}</span>
                      {#if relative}
                        <span class="e11y-ix-time-rel">{relative}</span>
                      {/if}
                    </div>
                    <div class="e11y-ix-trace-line">
                      <code class="e11y-ix-trace-primary">{primary}</code>
                      {#if extra > 0}
                        <span class="e11y-muted">+{extra}</span>
                      {/if}
                    </div>
                    {#if preview && ids.length > 1}
                      <div class="e11y-ix-preview">{preview}</div>
                    {/if}
                  </div>
                  <div class="e11y-ix-aside">
                    <span class={sourcePillClass(row.source)}>{String(row.source ?? "?")}</span>
                    {#if row.has_error}
                      <span class="e11y-pill e11y-pill--err">err</span>
                    {/if}
                    <span class="e11y-ix-count">{tc}×</span>
                  </div>
                </div>
              {/each}
              {/if}
            </div>
            <div class="e11y-split-secondary">
              {#if !splitSelectedKey}
                <p class="e11y-split-placeholder">Select an interaction to see events.</p>
              {:else if filteredTraceEvents.length === 0}
                <p class="e11y-muted e11y-split-placeholder">No events match the current filter.</p>
              {:else}
                {#each filteredTraceEvents as ev, j (eventKey(ev, j))}
                  {@const ek = eventKey(ev, j)}
                  {@const sum = payloadSummary(ev)}
                  <div
                    class="e11y-row"
                    class:e11y-row--context={isContextNeighbor(j)}
                    role="button"
                    tabindex="0"
                    onclick={() => selectEvent(ev, j)}
                    onkeydown={(e) => e.key === "Enter" && selectEvent(ev, j)}
                  >
                    <button
                      type="button"
                      class="e11y-row-expand"
                      class:e11y-row-expand--open={rowExpanded[ek]}
                      aria-expanded={!!rowExpanded[ek]}
                      aria-label={rowExpanded[ek] ? "Collapse row" : "Expand row"}
                      onclick={(e) => toggleRowExpand(ek, e)}>▸</button
                    >
                    <span class="e11y-sev {sevClass(ev.severity)}">{String(ev.severity ?? "?")}</span>
                    <span class="e11y-row-title">{String(ev.event_name ?? "")}</span>
                    <span class="e11y-row-meta">{String(ev.timestamp ?? "")}</span>
                    {#if rowExpanded[ek]}
                      <div class="e11y-row-body">
                        {#if sum}<p class="e11y-row-sum">{sum}</p>{/if}
                        <pre class="e11y-row-pre">{JSON.stringify(ev.payload, null, 2)}</pre>
                      </div>
                    {/if}
                  </div>
                {/each}
              {/if}
            </div>
          </div>
        {:else}
          {#if interactions.length === 0}
            <p class="e11y-muted e11y-empty">No interactions recorded yet.</p>
          {:else if filteredInteractions.length === 0}
            <p class="e11y-muted e11y-empty">No interactions in the selected time range.</p>
          {:else}
            {#each filteredInteractions as row (interactionRowKey(row))}
            {@const ids = (row.trace_ids as string[] | undefined) ?? []}
            {@const tc = Number(row.traces_count ?? ids.length)}
            {@const { absolute, relative } = formatInteractionStarted(String(row.started_at ?? ""))}
            {@const { primary, extra, preview } = summarizeTraceIds(ids)}
            <div
              class="e11y-ix"
              class:e11y-ix--error={!!row.has_error}
              role="button"
              tabindex="0"
              onclick={() => void onInteractionRowClick(row)}
              onkeydown={(e) => e.key === "Enter" && void onInteractionRowClick(row)}
            >
              <div class="e11y-ix-main">
                <div class="e11y-ix-time">
                  <span class="e11y-ix-time-abs">{absolute}</span>
                  {#if relative}
                    <span class="e11y-ix-time-rel">{relative}</span>
                  {/if}
                </div>
                <div class="e11y-ix-trace-line">
                  <code class="e11y-ix-trace-primary" title="First trace_id">{primary}</code>
                  {#if extra > 0}
                    <span class="e11y-muted">+{extra} parallel</span>
                  {/if}
                </div>
                {#if preview && ids.length > 1}
                  <div class="e11y-ix-preview" title="Trace ids in group">{preview}</div>
                {/if}
                <div class="e11y-ix-hint">Click → events for first trace</div>
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
          {/if}
        {/if}
      {:else if route.screen === "events"}
        {#if filteredTraceEvents.length === 0}
          <p class="e11y-muted e11y-empty">No events match the current filter.</p>
        {:else}
          {#each filteredTraceEvents as ev, i (eventKey(ev, i))}
            {@const ek = eventKey(ev, i)}
            {@const sum = payloadSummary(ev)}
            <div
              class="e11y-row"
              class:e11y-row--context={isContextNeighbor(i)}
              role="button"
              tabindex="0"
              onclick={() => selectEvent(ev, i)}
              onkeydown={(e) => e.key === "Enter" && selectEvent(ev, i)}
            >
              <button
                type="button"
                class="e11y-row-expand"
                class:e11y-row-expand--open={rowExpanded[ek]}
                aria-expanded={!!rowExpanded[ek]}
                aria-label={rowExpanded[ek] ? "Collapse row" : "Expand row"}
                onclick={(e) => toggleRowExpand(ek, e)}>▸</button
              >
              <span class="e11y-sev {sevClass(ev.severity)}">{String(ev.severity ?? "?")}</span>
              <span class="e11y-row-title">{String(ev.event_name ?? "")}</span>
              <span class="e11y-row-meta">{String(ev.timestamp ?? "")}</span>
              {#if rowExpanded[ek]}
                <div class="e11y-row-body">
                  {#if sum}<p class="e11y-row-sum">{sum}</p>{/if}
                  <pre class="e11y-row-pre">{JSON.stringify(ev.payload, null, 2)}</pre>
                </div>
              {/if}
            </div>
          {/each}
        {/if}
      {:else if route.screen === "detail"}
        {@const d = route.event}
        {@const meta = d.metadata as Record<string, unknown> | undefined}
        <div class="e11y-detail">
          <dl class="e11y-detail-dl">
            <dt>trace_id</dt>
            <dd class="e11y-mono">{String(d.trace_id ?? "—")}</dd>
            <dt>span_id</dt>
            <dd class="e11y-mono">{String(d.span_id ?? "—")}</dd>
            <dt>request_id</dt>
            <dd class="e11y-mono">{String(meta?.request_id ?? "—")}</dd>
            <dt>timestamp</dt>
            <dd>{String(d.timestamp ?? "—")}</dd>
          </dl>
          <details class="e11y-details">
            <summary>payload</summary>
            <pre class="e11y-detail-pre">{JSON.stringify(d.payload, null, 2)}</pre>
          </details>
          <details class="e11y-details">
            <summary>metadata</summary>
            <pre class="e11y-detail-pre">{JSON.stringify(d.metadata ?? {}, null, 2)}</pre>
          </details>
          <details class="e11y-details">
            <summary>full JSON</summary>
            <pre class="e11y-detail-pre">{JSON.stringify(d, null, 2)}</pre>
          </details>
        </div>
      {/if}
    {/snippet}
  </FullscreenPanel>
</div>
