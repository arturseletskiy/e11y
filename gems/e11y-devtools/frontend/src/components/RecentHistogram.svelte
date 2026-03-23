<script lang="ts">
  import { scaleBand } from "d3-scale"
  import { Axis, Bars, Chart, Svg } from "layerchart"
  import { buildRecentVolumeBuckets, type HistogramTimeRange } from "../lib/recentVolume"

  type HistoRow = {
    idx: number
    t0: number
    t1: number
    e0: number
    e1: number
    w0: number
    w1: number
    r0: number
    r1: number
    total: number
  }

  let {
    recent = [] as Record<string, unknown>[],
    timeRange = $bindable(null as HistogramTimeRange | null),
  } = $props()

  const COL_ERR = "var(--e11y-histo-err)"
  const COL_WARN = "var(--e11y-histo-warn)"
  const COL_REST = "var(--e11y-histo-ok)"
  /** HTML shade above chart, under brush overlay (SVG rect was hidden below overlay). */
  const COL_SEL_SHADE = "var(--e11y-sel-bg)"

  const BAR_RADIUS = 3
  const TWEEN = { duration: 420, easing: (t: number) => 1 - (1 - t) * (1 - t) }

  /** Host height scales with peak bucket total (√ for large spikes). */
  const HISTO_H_MIN = 120
  const HISTO_H_MAX = 260
  const HISTO_H_BASE = 96
  const HISTO_H_PER_SQRT = 16

  /** Must match Chart `padding` (Svg inner `<g>` is translated by this). */
  const CHART_PAD = { top: 6, right: 6, bottom: 26, left: 4 } as const

  let buckets = $derived(buildRecentVolumeBuckets(recent, 32))

  let chartRows = $derived.by((): HistoRow[] => {
    return buckets.map((b, idx) => {
      const err = b.counts.err
      const warn = b.counts.warn
      const rest = b.counts.rest
      const total = err + warn + rest
      return {
        idx,
        t0: b.t0,
        t1: b.t1,
        e0: 0,
        e1: err,
        w0: err,
        w1: err + warn,
        r0: err + warn,
        r1: total,
        total,
      }
    })
  })

  let maxY = $derived(Math.max(1, ...chartRows.map((r) => r.total)))

  let chartHostHeightPx = $derived(
    Math.round(
      Math.min(HISTO_H_MAX, Math.max(HISTO_H_MIN, HISTO_H_BASE + HISTO_H_PER_SQRT * Math.sqrt(maxY)))
    )
  )

  let chartWidth = $state(0)

  let xBand = $derived(
    scaleBand<number>()
      .domain(chartRows.map((r) => r.idx))
      .range([0, Math.max(0, chartWidth - CHART_PAD.left - CHART_PAD.right)])
      .paddingInner(0.18)
      .paddingOuter(0.06)
  )

  let tickIdxs = $derived.by(() => {
    const n = chartRows.length
    if (n === 0) return []
    const want = [0, Math.floor(n / 4), Math.floor(n / 2), Math.floor((3 * n) / 4), n - 1]
    return [...new Set(want.filter((i) => i >= 0 && i < n))]
  })

  let chartHost: HTMLDivElement | null = $state(null)
  let brushOverlay: HTMLDivElement | null = $state(null)
  let dragA = $state<number | null>(null)
  let dragB = $state<number | null>(null)
  let dragging = $state(false)

  function formatTick(ms: number): string {
    return new Date(ms).toISOString().slice(11, 23) + "Z"
  }

  /** X in LayerChart inner `<g>` space (same as band scale output), robust to SVG/CSS transforms. */
  function clientToInnerPlotX(clientX: number, clientY: number): number | null {
    const root = chartHost
    if (!root) return null
    const svg = root.querySelector<SVGSVGElement>("svg.layercake-layout-svg")
    const g = svg?.querySelector<SVGGElement>(".layercake-layout-svg_g")
    if (!svg || !g) return null
    const m = g.getScreenCTM()
    if (!m) return null
    return new DOMPoint(clientX, clientY).matrixTransform(m.inverse()).x
  }

  function indexFromClientX(clientX: number, clientY: number): number {
    const n = chartRows.length
    if (n === 0) return 0
    const root = chartHost
    if (!root) return 0
    const xInner = clientToInnerPlotX(clientX, clientY)
    const bw = xBand.bandwidth()
    if (xInner == null || !Number.isFinite(xInner) || bw <= 0) {
      const svg = root.querySelector<SVGSVGElement>("svg.layercake-layout-svg")
      const rect = svg?.getBoundingClientRect() ?? root.getBoundingClientRect()
      const fallback = clientX - rect.left - CHART_PAD.left
      return indexFromInnerX(fallback, n)
    }
    return indexFromInnerX(xInner, n)
  }

  function indexFromInnerX(xInner: number, n: number): number {
    const bw = xBand.bandwidth()
    for (let i = 0; i < n; i++) {
      const x0 = xBand(i)
      if (x0 === undefined) continue
      if (xInner >= x0 && xInner < x0 + bw) return i
    }
    const first = xBand(0)
    const last = xBand(n - 1)
    if (first !== undefined && xInner < first) return 0
    if (last !== undefined && xInner >= last + bw) return n - 1
    let nearest = 0
    let best = Infinity
    for (let i = 0; i < n; i++) {
      const x0 = xBand(i)
      if (x0 === undefined) continue
      const mid = x0 + bw / 2
      const d = Math.abs(xInner - mid)
      if (d < best) {
        best = d
        nearest = i
      }
    }
    return nearest
  }

  function commitRange(i0: number, i1: number): void {
    const b = buckets
    const lo = Math.min(i0, i1)
    const hi = Math.max(i0, i1)
    timeRange = { startMs: b[lo].t0, endMs: b[hi].t1, lo, hi }
  }

  function onPointerDown(e: PointerEvent): void {
    if (e.button !== 0) return
    if (chartRows.length === 0) return
    const cap = brushOverlay ?? chartHost
    if (!cap) return
    try {
      cap.setPointerCapture(e.pointerId)
    } catch {
      /* ignore */
    }
    dragging = true
    const i = indexFromClientX(e.clientX, e.clientY)
    dragA = i
    dragB = i
  }

  function onPointerMove(e: PointerEvent): void {
    if (!dragging || dragA === null) return
    dragB = indexFromClientX(e.clientX, e.clientY)
  }

  function onPointerUp(e: PointerEvent): void {
    const cap = brushOverlay ?? chartHost
    if (!cap) return
    try {
      cap.releasePointerCapture(e.pointerId)
    } catch {
      /* ignore */
    }
    if (dragging && dragA !== null && dragB !== null) {
      commitRange(dragA, dragB)
    }
    dragging = false
    dragA = null
    dragB = null
  }

  function onDoubleClick(): void {
    timeRange = null
  }

  function clearRange(): void {
    timeRange = null
  }

  function selIndexRange(): { lo: number; hi: number } | null {
    if (dragging && dragA !== null && dragB !== null) {
      return { lo: Math.min(dragA, dragB), hi: Math.max(dragA, dragB) }
    }
    if (!timeRange || buckets.length === 0) return null
    const n = buckets.length
    if (timeRange.lo == null || timeRange.hi == null) return null
    const rawLo = Math.max(0, Math.min(timeRange.lo, n - 1))
    const rawHi = Math.max(0, Math.min(timeRange.hi, n - 1))
    return { lo: Math.min(rawLo, rawHi), hi: Math.max(rawLo, rawHi) }
  }

  let spanLabel = $derived.by((): string | null => {
    if (buckets.length === 0) return null
    const first = buckets[0]
    const last = buckets[buckets.length - 1]
    return `${formatTick(first.t0)} → ${formatTick(last.t1)}`
  })

  let selectionLayout = $derived.by((): { left: number; top: number; width: number; height: number } | null => {
    const sel = selIndexRange()
    if (!sel) return null
    const bw = xBand.bandwidth()
    const x0 = xBand(sel.lo)
    const x1 = (xBand(sel.hi) ?? 0) + bw
    if (x0 === undefined) return null
    const plotH = chartHostHeightPx - CHART_PAD.top - CHART_PAD.bottom
    return {
      left: CHART_PAD.left + x0,
      top: CHART_PAD.top,
      width: Math.max(0, x1 - x0),
      height: Math.max(0, plotH),
    }
  })
</script>

{#if chartRows.length > 0}
  <div class="e11y-histo-wrap">
    <div
      bind:this={chartHost}
      bind:clientWidth={chartWidth}
      class="e11y-histo-chart-host"
      style:height="{chartHostHeightPx}px"
      style:min-height="{chartHostHeightPx}px"
      role="application"
      aria-label="Log volume by time (LayerChart). Drag to filter. Double-click resets."
    >
      <Chart
        data={chartRows}
        x="idx"
        xDomain={chartRows.map((r) => r.idx)}
        xScale={xBand}
        y="total"
        yDomain={[0, maxY]}
        yNice={false}
        padding={{ top: CHART_PAD.top, right: CHART_PAD.right, bottom: CHART_PAD.bottom, left: CHART_PAD.left }}
        brush={{ disabled: true }}
      >
        <Svg class="e11y-histo-svg" label="Recent log volume">
          <!-- LayerChart rect helper only reads range from `y` when it is [low, high]; plain y/y1 leaves y1 ignored. -->
          <Bars
            data={chartRows}
            y={(d: HistoRow) => [d.e0, d.e1]}
            fill={COL_ERR}
            stroke="none"
            strokeWidth={0}
            radius={0}
            rounded="none"
            tweened={TWEEN}
          />
          <Bars
            data={chartRows}
            y={(d: HistoRow) => [d.w0, d.w1]}
            fill={COL_WARN}
            stroke="none"
            strokeWidth={0}
            radius={0}
            rounded="none"
            tweened={TWEEN}
          />
          <Bars
            data={chartRows}
            y={(d: HistoRow) => [d.r0, d.r1]}
            fill={COL_REST}
            stroke="none"
            strokeWidth={0}
            radius={BAR_RADIUS}
            rounded="top"
            tweened={TWEEN}
          />

          <Axis
            placement="bottom"
            rule={false}
            grid={false}
            ticks={tickIdxs.map((i) => chartRows[i]!.idx)}
            format={(v) => {
              const row = chartRows.find((r) => r.idx === v)
              return row ? formatTick(row.t0) : ""
            }}
            tickLength={3}
            tickLabelProps={{ class: "e11y-histo-axis-tick" }}
          />
        </Svg>
      </Chart>
      {#if selectionLayout}
        <div
          class="e11y-histo-sel-shade"
          style:left="{selectionLayout.left}px"
          style:top="{selectionLayout.top}px"
          style:width="{selectionLayout.width}px"
          style:height="{selectionLayout.height}px"
          aria-hidden="true"
        ></div>
      {/if}
      <div
        bind:this={brushOverlay}
        class="e11y-histo-brush-overlay"
        aria-hidden="true"
        onpointerdown={onPointerDown}
        onpointermove={onPointerMove}
        onpointerup={onPointerUp}
        onpointercancel={onPointerUp}
        ondblclick={onDoubleClick}
      ></div>
    </div>

    <div class="e11y-histo-footer">
      <div class="e11y-histo-legend">
        <span><i class="e11y-histo-dot e11y-histo-dot--err"></i> error</span>
        <span><i class="e11y-histo-dot e11y-histo-dot--warn"></i> warn</span>
        <span><i class="e11y-histo-dot e11y-histo-dot--rest"></i> other</span>
      </div>
      <div class="e11y-histo-meta">
        {#if spanLabel}
          <span class="e11y-histo-span" title="Full sample span (UTC)">{spanLabel}</span>
        {/if}
        {#if timeRange}
          <span class="e11y-histo-filter" title="Active time filter (UTC)">
            Filter: {formatTick(timeRange.startMs)}–{formatTick(timeRange.endMs)}
          </span>
          <button type="button" class="e11y-histo-clear" onclick={clearRange}>Clear range</button>
        {:else}
          <span class="e11y-histo-hint">Drag to narrow · double-click to reset</span>
        {/if}
      </div>
    </div>
  </div>
{/if}
