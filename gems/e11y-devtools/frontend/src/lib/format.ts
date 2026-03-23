/** Format ISO timestamp for list rows + short relative hint. */
export function formatInteractionStarted(iso: string): { absolute: string; relative: string } {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) {
    return { absolute: iso || "—", relative: "" }
  }
  const absolute = d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  })
  const sec = Math.round((Date.now() - d.getTime()) / 1000)
  let relative = ""
  if (sec < 60) relative = `${sec}s ago`
  else if (sec < 3600) relative = `${Math.floor(sec / 60)}m ago`
  else if (sec < 86400) relative = `${Math.floor(sec / 3600)}h ago`
  else relative = `${Math.floor(sec / 86400)}d ago`
  return { absolute, relative }
}

export function summarizeTraceIds(ids: string[] | undefined): {
  primary: string
  extra: number
  preview: string
} {
  const list = ids ?? []
  if (list.length === 0) {
    return { primary: "—", extra: 0, preview: "" }
  }
  const primary = list[0] ?? "—"
  const extra = Math.max(0, list.length - 1)
  const preview =
    list.length <= 2 ? list.join(", ") : `${list[0]}, ${list[1]} +${list.length - 2}`
  return { primary, extra, preview }
}
