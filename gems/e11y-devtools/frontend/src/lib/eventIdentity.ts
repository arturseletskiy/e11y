/** Stable key for deduping events across polls (pulse / badges). */
export function eventKey(e: Record<string, unknown>, index: number): string {
  const id = e.id
  if (typeof id === "string" && id.length > 0) return id

  return [
    String(e.trace_id ?? ""),
    String(e.timestamp ?? ""),
    String(e.event_name ?? ""),
    index,
  ].join("|")
}
