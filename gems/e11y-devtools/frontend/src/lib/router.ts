export type SourceFilter = "web" | "job" | "all"

export type OverlayRoute =
  | { screen: "interactions" }
  | { screen: "events"; traceId: string }
  | { screen: "detail"; traceId: string; event: Record<string, unknown> }
