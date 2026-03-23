<script lang="ts" module>
  export type TimelineTimeRange = { startMs: number; endMs: number }
</script>

<script lang="ts">
  import { scaleTime, scaleLinear } from "d3-scale"
  import { Axis, Chart, Svg } from "layerchart"

  let {
    interactions = [] as Record<string, unknown>[],
    timeRange = $bindable(null as TimelineTimeRange | null),
  } = $props()

  const CHART_PAD = { top: 8, right: 6, bottom: 20, left: 4 } as const
  const HEIGHT = 64

  const COL_ERR = "var(--e11y-err)"
  const COL_WARN = "var(--e11y-warn)"
  const COL_REST = "var(--e11y-ok)"
  const COL_SEL_SHADE = "var(--e11y-sel-bg)"

  let parsed = $derived.by(() => {
    return interactions
      .map((i) => {
        const t = new Date(String(i.started_at || "")).getTime()
        const d = Number(i.duration) || 0
        const s = Number(i.status) || 200
        return { t, d, s, id: String(i.id || Math.random()) }
      })
      .filter((i) => !isNaN(i.t))
      // sort by time so drawing order is consistent
      .sort((a, b) => a.t - b.t)
  })

  let tExtents = $derived.by(() => {
    if (parsed.length === 0) return { min: 0, max: 1 }
    let min = parsed[0].t
    let max = parsed[parsed.length - 1].t
    if (max === min) {
      min -= 1000
      max += 1000
    }
    return { min, max }
  })

  let dMax = $derived.by(() => {
    if (parsed.length === 0) return 1
    return Math.max(1, ...parsed.map((p) => p.d))
  })

  let chartWidth = $state(0)

  let xTime = $derived(
    scaleTime()
      .domain([new Date(tExtents.min), new Date(tExtents.max)])
      .range([0, Math.max(0, chartWidth - CHART_PAD.left - CHART_PAD.right)])
  )

  let yLinear = $derived(
    scaleLinear()
      .domain([0, dMax])
      .range([Math.max(0, HEIGHT - CHART_PAD.top - CHART_PAD.bottom), 0])
  )

  let chartHost: HTMLDivElement | null = $state(null)
  let brushOverlay: HTMLDivElement | null = $state(null)
  let dragA = $state<number | null>(null)
  let dragB = $state<number | null>(null)
  let dragging = $state(false)

  function formatTick(d: Date): string {
    return d.toISOString().slice(11, 23) + "Z"
  }

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

  function timeFromClientX(clientX: number, clientY: number): number {
    if (parsed.length === 0) return 0
    const root = chartHost
    if (!root) return 0
    let xInner = clientToInnerPlotX(clientX, clientY)
    if (xInner == null || !Number.isFinite(xInner)) {
      const svg = root.querySelector<SVGSVGElement>("svg.layercake-layout-svg")
      const rect = svg?.getBoundingClientRect() ?? root.getBoundingClientRect()
      xInner = clientX - rect.left - CHART_PAD.left
    }
    const range = xTime.range()
    xInner = Math.max(range[0], Math.min(range[1], xInner))
    return xTime.invert(xInner).getTime()
  }

  function commitRange(t0: number, t1: number): void {
    const startMs = Math.min(t0, t1)
    const endMs = Math.max(t0, t1)
    timeRange = { startMs, endMs }
  }

  function onPointerDown(e: PointerEvent): void {
    if (e.button !== 0) return
    if (parsed.length === 0) return
    const cap = brushOverlay ?? chartHost
    if (!cap) return
    try {
      cap.setPointerCapture(e.pointerId)
    } catch {
      /* ignore */
    }
    dragging = true
    const t = timeFromClientX(e.clientX, e.clientY)
    dragA = t
    dragB = t
  }

  function onPointerMove(e: PointerEvent): void {
    if (!dragging || dragA === null) return
    dragB = timeFromClientX(e.clientX, e.clientY)
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

  let activeRange = $derived.by(() => {
    if (dragging && dragA !== null && dragB !== null) {
      return { startMs: Math.min(dragA, dragB), endMs: Math.max(dragA, dragB) }
    }
    return timeRange
  })

  let selectionLayout = $derived.by(() => {
    const r = activeRange
    if (!r) return null
    const x0 = xTime(new Date(r.startMs))
    const x1 = xTime(new Date(r.endMs))
    const plotH = HEIGHT - CHART_PAD.top - CHART_PAD.bottom
    return {
      left: CHART_PAD.left + x0,
      top: CHART_PAD.top,
      width: Math.max(0, x1 - x0),
      height: Math.max(0, plotH),
    }
  })

  function colorForStatus(s: number): string {
    if (s >= 500) return COL_ERR
    if (s >= 400) return COL_WARN
    return COL_REST
  }
</script>

{#if parsed.length > 0}
  <div class="e11y-histo-wrap">
    <div
      bind:this={chartHost}
      bind:clientWidth={chartWidth}
      class="e11y-histo-chart-host"
      style:height="{HEIGHT}px"
      style:min-height="{HEIGHT}px"
      role="application"
      aria-label="Interactions timeline. Drag to filter."
    >
      <Chart
        data={parsed}
        x="t"
        xScale={xTime}
        y="d"
        yScale={yLinear}
        padding={{ top: CHART_PAD.top, right: CHART_PAD.right, bottom: CHART_PAD.bottom, left: CHART_PAD.left }}
      >
        <Svg class="e11y-histo-svg">
          {#each parsed as p (p.id)}
            <line
              x1={xTime(new Date(p.t))}
              x2={xTime(new Date(p.t))}
              y1={yLinear(0)}
              y2={yLinear(p.d)}
              stroke={colorForStatus(p.s)}
              stroke-width="2"
              stroke-linecap="round"
            />
          {/each}

          <Axis
            placement="bottom"
            rule={false}
            grid={false}
            ticks={4}
            format={(d) => formatTick(d as Date)}
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
        <span><i class="e11y-histo-dot e11y-histo-dot--err"></i> 5xx</span>
        <span><i class="e11y-histo-dot e11y-histo-dot--warn"></i> 4xx</span>
        <span><i class="e11y-histo-dot e11y-histo-dot--rest"></i> ok</span>
      </div>
      <div class="e11y-histo-meta">
        {#if activeRange}
          <span class="e11y-histo-filter">
            Filter: {formatTick(new Date(activeRange.startMs))}–{formatTick(new Date(activeRange.endMs))}
          </span>
          {#if timeRange}
            <button type="button" class="e11y-histo-clear" onclick={clearRange}>Clear</button>
          {/if}
        {:else}
          <span class="e11y-histo-hint">Drag to narrow · double-click to reset</span>
        {/if}
      </div>
    </div>
  </div>
{/if}
