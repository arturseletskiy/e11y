export type ListSeverityFilter = "all" | "error" | "warn" | "rest"

/** error filter matches error + fatal */
export function eventMatchesSeverity(ev: Record<string, unknown>, filter: ListSeverityFilter): boolean {
  if (filter === "all") return true
  const s = String(ev.severity ?? "")
  if (filter === "error") return s === "error" || s === "fatal"
  if (filter === "warn") return s === "warn"
  /* rest: debug, info, success, … */
  return s !== "error" && s !== "fatal" && s !== "warn"
}

export function eventMatchesSearch(ev: Record<string, unknown>, query: string): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  if (String(ev.event_name ?? "").toLowerCase().includes(q)) return true
  if (String(ev.trace_id ?? "").toLowerCase().includes(q)) return true
  const meta = ev.metadata
  if (meta && typeof meta === "object") {
    try {
      if (JSON.stringify(meta).toLowerCase().includes(q)) return true
    } catch {
      /* ignore */
    }
  }
  const payload = ev.payload
  if (payload !== undefined && payload !== null) {
    try {
      if (JSON.stringify(payload).toLowerCase().includes(q)) return true
    } catch {
      /* ignore */
    }
  }
  return false
}

export function filterEventList(
  rows: Record<string, unknown>[],
  severity: ListSeverityFilter,
  search: string
): Record<string, unknown>[] {
  return rows.filter((ev) => eventMatchesSeverity(ev, severity) && eventMatchesSearch(ev, search))
}
