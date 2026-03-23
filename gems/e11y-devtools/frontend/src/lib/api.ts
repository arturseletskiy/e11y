import type { SourceFilter } from "./router"

function useMocks(): boolean {
  return import.meta.env.DEV
}

export async function fetchRecent(limit = 200): Promise<Record<string, unknown>[]> {
  const url = useMocks()
    ? "/mocks/v1/events/recent.json"
    : `/_e11y/v1/events/recent?limit=${limit}`
  const r = await fetch(url)
  if (!r.ok) throw new Error(`recent: ${r.status}`)
  return r.json() as Promise<Record<string, unknown>[]>
}

export async function fetchInteractions(source: SourceFilter): Promise<Record<string, unknown>[]> {
  const url = useMocks()
    ? "/mocks/v1/interactions.json"
    : `/_e11y/v1/interactions${source === "all" ? "" : `?source=${source}`}`
  const r = await fetch(url)
  if (!r.ok) throw new Error(`interactions: ${r.status}`)
  const rows = (await r.json()) as Record<string, unknown>[]
  if (useMocks()) {
    if (source === "all") return rows
    return rows.filter((i) => i.source === source)
  }
  return rows
}

export async function fetchTraceEvents(traceId: string): Promise<Record<string, unknown>[]> {
  const url = useMocks()
    ? `/mocks/v1/traces/${encodeURIComponent(traceId)}/events.json`
    : `/_e11y/v1/traces/${encodeURIComponent(traceId)}/events`
  const r = await fetch(url)
  if (!r.ok) throw new Error(`trace events: ${r.status}`)
  return r.json() as Promise<Record<string, unknown>[]>
}
