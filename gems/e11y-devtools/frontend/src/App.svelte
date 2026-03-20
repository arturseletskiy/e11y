<script lang="ts">
  import Fab from "./components/Fab.svelte"
  import FullscreenPanel from "./components/FullscreenPanel.svelte"
  import { fetchInteractions, fetchRecent, fetchTraceEvents } from "./lib/api"
  import { formatInteractionStarted, summarizeTraceIds } from "./lib/format"
  import { eventKey } from "./lib/eventIdentity"
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

  let prevRecentKeys = $state<Set<string>>(new Set())
  let firstRecentPoll = $state(true)
  let pulseKind = $state<"none" | "error" | "warn">("none")
  let pulseTimer: ReturnType<typeof setTimeout> | null = null

  const POLL_MS = 2000
  const PULSE_MS = 3000

  let problemEvents = $derived.by(() =>
    recentEvents.filter((e) => e.severity === "error" || e.severity === "fatal")
  )

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
    route = { screen: "problems" }
  }

  function goTabInteractions(): void {
    splitSelectedKey = null
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

  function selectEvent(ev: Record<string, unknown>): void {
    const tid = String(ev.trace_id ?? "")
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
      route = { screen: "interactions" }
    }
    void loadInteractionsList()
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

  let showEventsToolbar = $derived.by(
    () => route.screen === "events" || route.screen === "detail"
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
    title={panelTitle}
    origin={panelCircleOrigin}
  >
    {#snippet headerExtra()}
      <div class="e11y-header-nav">
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
        {#if tabInteractionsActive && route.screen === "interactions"}
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
      </div>
    {/snippet}

    {#snippet children()}
      {#if loadError}
        <p class="e11y-err-msg">{loadError}</p>
      {/if}

      {#if showEventsToolbar}
        <div class="e11y-toolbar">
          <button type="button" class="e11y-btn" onclick={back}>← Back</button>
          {#if route.screen === "detail"}
            <button type="button" class="e11y-btn" onclick={() => void copyDetailJson()}>Copy JSON</button>
          {/if}
        </div>
      {/if}

      {#if route.screen === "problems"}
        <p class="e11y-problems-hint">Recent error / fatal events from the dev log (newest first).</p>
        {#if problemEvents.length === 0}
          <p class="e11y-muted e11y-empty">No errors in the recent buffer.</p>
          <button type="button" class="e11y-btn" onclick={goTabInteractions}>Open interactions</button>
        {:else}
          {#each problemEvents as ev, i (eventKey(ev, i))}
            {@const tr = String(ev.trace_id ?? "")}
            <div
              class="e11y-row e11y-row--problem"
              role="button"
              tabindex="0"
              onclick={() => openProblemDetail(ev)}
              onkeydown={(e) => e.key === "Enter" && openProblemDetail(ev)}
            >
              <span class="e11y-sev {sevClass(ev.severity)}">{String(ev.severity ?? "?")}</span>
              <span class="e11y-row-title">{String(ev.event_name ?? "")}</span>
              <span class="e11y-row-meta e11y-mono" title={tr || undefined}
                >{tr.length > 14 ? `${tr.slice(0, 12)}…` : tr || "—"}</span
              >
              <span class="e11y-row-meta">{String(ev.timestamp ?? "")}</span>
            </div>
          {/each}
        {/if}
      {:else if route.screen === "interactions"}
        {#if layoutWide}
          <div class="e11y-split">
            <div class="e11y-split-primary">
              {#each interactions as row (interactionRowKey(row))}
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
            </div>
            <div class="e11y-split-secondary">
              {#if !splitSelectedKey}
                <p class="e11y-split-placeholder">Select an interaction to see events.</p>
              {:else}
                {#each events as ev, j (eventKey(ev, j))}
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
              {/if}
            </div>
          </div>
        {:else}
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
        <pre class="e11y-detail-pre">{JSON.stringify(route.event, null, 2)}</pre>
      {/if}
    {/snippet}
  </FullscreenPanel>
</div>
