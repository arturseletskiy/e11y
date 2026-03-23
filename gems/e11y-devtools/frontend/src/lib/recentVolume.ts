/** Stacked severity counts per time slice (for recent-events volume bar). */

/** Histogram brush: bucket indices + bounds (indices stay aligned with columns when `recent` changes). */
export type HistogramTimeRange = {
  startMs: number
  endMs: number
  lo: number
  hi: number
}

export type VolumeSeverity = "err" | "warn" | "rest"

export interface VolumeBucket {
  /** Bucket start (ms since epoch). */
  t0: number
  t1: number
  counts: Record<VolumeSeverity, number>
}

function severityVolumeGroup(sev: unknown): VolumeSeverity {
  const s = String(sev ?? "")
  if (s === "error" || s === "fatal") return "err"
  if (s === "warn") return "warn"
  return "rest"
}

/** Parse event `timestamp` (ISO string) to epoch ms. */
export function eventTimestampMs(ev: Record<string, unknown>): number | null {
  const raw = ev.timestamp
  if (typeof raw !== "string") return null
  const ms = Date.parse(raw)
  return Number.isFinite(ms) ? ms : null
}

/** Newest-first input (as from API); builds ~`bucketCount` buckets from oldest→newest span. */
export function buildRecentVolumeBuckets(
  rows: Record<string, unknown>[],
  bucketCount = 28
): VolumeBucket[] {
  if (rows.length === 0) return []

  const times: number[] = []
  for (const ev of rows) {
    const t = eventTimestampMs(ev)
    if (t != null) times.push(t)
  }
  if (times.length === 0) return []

  let tMin = Math.min(...times)
  let tMax = Math.max(...times)
  if (tMax <= tMin) {
    tMin -= 1
    tMax += 1
  }

  const n = Math.max(1, Math.min(bucketCount, Math.ceil(rows.length / 2) || bucketCount))
  const width = (tMax - tMin) / n
  const buckets: VolumeBucket[] = []
  for (let i = 0; i < n; i++) {
    buckets.push({
      t0: tMin + i * width,
      t1: tMin + (i + 1) * width,
      counts: { err: 0, warn: 0, rest: 0 },
    })
  }

  for (const ev of rows) {
    const t = eventTimestampMs(ev)
    if (t == null) continue
    const idx = Math.min(n - 1, Math.max(0, Math.floor((t - tMin) / width)))
    const g = severityVolumeGroup(ev.severity)
    buckets[idx].counts[g] += 1
  }

  return buckets
}

export function bucketTotal(b: VolumeBucket): number {
  return b.counts.err + b.counts.warn + b.counts.rest
}
