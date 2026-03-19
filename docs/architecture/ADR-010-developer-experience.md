# ADR-010: Developer Experience

**Status:** Accepted
**Date:** March 18, 2026
**Covers:** UC-017 (Local Development)
**Depends On:** ADR-001 (Core), ADR-004 (Adapter Architecture), ADR-008 (Rails Integration)

---

## Table of Contents

1. [Context & Problem](#1-context--problem)
2. [Architecture: Hub-and-Spoke](#2-architecture-hub-and-spoke)
3. [DevLog Adapter](#3-devlog-adapter)
4. [TUI — Interactive Log Viewer](#4-tui--interactive-log-viewer)
5. [Browser Overlay](#5-browser-overlay)
6. [MCP Server](#6-mcp-server)
7. [CLI Entry Point](#7-cli-entry-point)
8. [Monorepo Structure](#8-monorepo-structure)
9. [Noise Reduction Philosophy](#9-noise-reduction-philosophy)
10. [Technology Choices & Alternatives](#10-technology-choices--alternatives)
11. [Trade-offs](#11-trade-offs)

---

## 1. Context & Problem

### 1.1. Problem Statement

E11y routes events to production backends (Loki, Sentry, OpenTelemetry). During local development, those backends are unavailable or impractical to run. Developers need answers to:

- What events fired during this request?
- Which events contained errors?
- Did sampling or PII filtering suppress an event?
- How do parallel async traces relate to a single user interaction?

Before e11y-devtools, the only option was configuring a `StdoutAdapter` and scanning console output manually — a high-noise, low-signal workflow.

### 1.2. Goals

1. **Zero configuration** — works automatically in `development` and `test` environments.
2. **Zero production overhead** — the write-path adapter is production-safe (tiny, no UI code).
3. **Multiple access modes** — terminal (TUI), browser (overlay), AI assistant (MCP).
4. **Noise reduction** — show developers what matters, hide what does not.

### 1.3. Non-Goals

- Replace production observability backends (Loki, Sentry, OTel).
- Provide event schema registry or documentation generation (separate concern).
- Operate in production (all viewer code is in the opt-in `e11y-devtools` gem).

---

## 2. Architecture: Hub-and-Spoke

```
                    ┌─────────────────────────┐
                    │   E11y Event Pipeline    │
                    │  (production gem code)   │
                    └────────────┬────────────┘
                                 │ DevLog adapter
                                 ▼
                    ┌─────────────────────────┐
                    │   log/e11y_dev.jsonl     │  ← single source of truth
                    │   (JSONL, gzip rotation) │
                    └──────┬────────┬──────────┘
                           │        │
              ┌────────────┘        └────────────────┐
              ▼                                       ▼
   ┌──────────────────┐              ┌───────────────────────────┐
   │   TUI Viewer      │              │   Browser Overlay          │
   │  bundle exec e11y │              │   Rails Engine /_e11y/     │
   │  (ratatui_ruby)   │              │   + injected JS <e11y-     │
   └──────────────────┘              │   overlay> custom element  │
                                     └───────────────────────────┘
                                                    │
                                     ┌──────────────┘
                                     ▼
                          ┌─────────────────────┐
                          │   MCP Server         │
                          │  bundle exec e11y mcp│
                          │  (stdio / HTTP)      │
                          └─────────────────────┘
```

**Key design principle:** `log/e11y_dev.jsonl` is the single source of truth. The write path (DevLog adapter) lives in the production `e11y` gem — it is always available. All three viewers are independent and read the same file; they share no runtime state.

---

## 3. DevLog Adapter

The DevLog adapter is split into three components under `lib/e11y/adapters/dev_log/`.

### 3.1. FileStore

`DevLog::FileStore` is the write path. It writes one JSON line per event and rotates the file when it exceeds configured limits.

Key implementation details:
- Thread-safety: `Mutex` + `File::LOCK_EX` around every write.
- Rotation: atomic rename to `.1`, `.2`, … up to `keep_rotated` numbered gzip files. Older files are deleted.
- Copy strategy: `IO.copy_stream` — no heap allocation for file content during rotation.

| Constant | Default | ENV override |
|---|---|---|
| `DEFAULT_MAX_SIZE` | 50 MB | `E11Y_MAX_SIZE` |
| `DEFAULT_MAX_LINES` | 10 000 | `E11Y_MAX_EVENTS` |
| `DEFAULT_KEEP_ROTATED` | 5 | `E11Y_KEEP_ROTATED` |

### 3.2. Query

`DevLog::Query` is the read path, shared by all three viewers.

- **mtime-cached in-memory cache**: re-parses the JSONL file only when `File.mtime` changes.
- **Optional JSON accelerator**: uses `oj` when available, falls back to stdlib `JSON`.
- **Zero Rails dependency**: usable from the TUI process that has no Rails loaded.

Public API:

```ruby
query = E11y::Adapters::DevLog::Query.new("log/e11y_dev.jsonl")

query.stored_events(limit: 1000, severity: nil, source: nil)  # → Array of event Hashes
query.search("checkout")     # → Array of matching events (full-text)
query.events_by_trace(id)    # → Array of events for one trace_id
query.interactions           # → Array of Interaction structs (grouped traces)
query.stats                  # → Hash with counts, error rate, top events
query.find_event(id)         # → single event Hash or nil
query.updated_since?(time)   # → Boolean (used by polling viewers)
query.clear!                 # → truncates the JSONL file
```

`Interaction` is a plain Struct:
```ruby
Interaction = Struct.new(:started_at, :trace_ids, :has_error?,
                         :source, keyword_init: true) do
  def traces_count = trace_ids.size
end
```

### 3.3. DevLog Adapter Facade

`E11y::Adapters::DevLog` wraps FileStore for writing and delegates all read calls to Query:

```ruby
adapter = E11y::Adapters::DevLog.new(
  path: "log/e11y_dev.jsonl",
  max_size: 50 * 1024 * 1024,
  max_lines: 10_000,
  keep_rotated: 5
)

adapter.write(event_data)            # delegates to FileStore
adapter.recent_events(limit: 50)     # delegates to Query
adapter.capabilities                 # → { dev_log: true, readable: true }
```

### 3.4. DevLogSource Middleware

`E11y::Middleware::DevLogSource` is a Rack middleware that stamps request metadata before events are tracked:

```ruby
Thread.current[:e11y_source] = "web"           # sets thread-local; downstream code (including DevLog#serialize) reads this
env["e11y.trace_id"] ||= Thread.current[:e11y_trace_id]  # exposes trace ID to the Browser Overlay JS
```

### 3.5. Railtie Auto-Registration

The `E11y::Railtie` automatically registers the DevLog adapter in `development` and `test` environments when no `:dev_log` adapter is already configured. ENV vars control limits at boot:

```bash
E11Y_MAX_EVENTS=5000   # override max lines
E11Y_MAX_SIZE=10485760 # override max file size (bytes)
E11Y_KEEP_ROTATED=3    # override number of rotated files kept
```

---

## 4. TUI — Interactive Log Viewer

### 4.1. Entry

```bash
bundle exec e11y        # default: launches TUI
bundle exec e11y tui    # explicit
```

### 4.2. Three-View Navigation

The TUI presents a drill-down hierarchy:

```
:interactions  →  :events  →  :detail
(list of        (events in    (full JSON
 interactions)   one trace)    of one event)
```

### 4.3. Keyboard Map

| Key | View | Action |
|---|---|---|
| `↓` / `↑` | interactions, events | Navigate down/up |
| `Enter` | interactions | Drill into events for selected interaction |
| `Enter` | events | Open detail overlay |
| `Esc` / `b` | events, detail | Go back |
| `w` | interactions | Source filter: web requests only |
| `j` | interactions | Source filter: background jobs only |
| `a` | interactions | Source filter: all sources |
| `r` | interactions | Force reload |
| `q` | any | Quit |
| `c` | detail | Copy event JSON to clipboard |

### 4.4. Interaction Grouping

The `Grouping.group` function converts a flat list of trace IDs into `Interaction` structs:

```ruby
E11y::Devtools::Tui::Grouping.group(traces, window_ms: 500)
```

Algorithm:
1. Sort traces by `started_at`.
2. Assign traces that start within `window_ms` of the group's start into the same `Interaction`.
3. Return interactions sorted newest-first.

This converts N parallel async traces into a single human-readable row without requiring any client-side coordination (no `X-Interaction-ID` header).

### 4.5. File Watcher

The TUI polls `File.mtime` every `POLL_INTERVAL_MS = 250` ms. No inotify/kqueue dependency — zero platform-specific code, cross-platform by default.

### 4.6. Widgets

| Widget | Description |
|---|---|
| `InteractionList` | One row per interaction. Bullet: `●` red (has errors) / `○` gray (clean). |
| `EventList` | Table of events for a trace, colored by severity. |
| `EventDetail` | Popup overlay showing full JSON of a single event. |

---

## 5. Browser Overlay

### 5.1. Rails Engine

The overlay is a Rails Engine with isolated namespace, mounted automatically at `/_e11y/`:

```ruby
# config/routes.rb (added by Railtie)
mount E11y::Devtools::Overlay::Engine => "/_e11y"
```

All controller actions return `404 Not Found` outside the `development` environment, making accidental production mount harmless.

### 5.2. Controller Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/_e11y/events?trace_id=` | Events for a specific trace |
| `GET` | `/_e11y/events/recent?limit=` | Most recent N events |
| `DELETE` | `/_e11y/events` | Clear log; returns 204 No Content |

### 5.3. Rack Middleware — Script Injection

`E11y::Devtools::Overlay::Middleware` sits in the Rack stack and injects the overlay script into HTML responses:

- Skips: XHR requests, asset paths (`/assets/`, `.js`, `.css`, etc.), non-HTML content types.
- Injects `<script>` tag before `</body>`.
- Injects `window.__E11Y_TRACE_ID__` with the current request's trace ID.
- Recalculates and updates `Content-Length` header.

### 5.4. Custom Element

The injected script registers a vanilla JS Custom Element `<e11y-overlay>` using Shadow DOM:

- **Badge**: floating, bottom-right corner. Shows event count and error count.
- **Error indicator**: red border around the badge when any event in the current trace has severity `error` or `fatal`.
- **Panel**: click the badge to open a slide-in panel showing the current trace's events.
- **Polling**: queries `/_e11y/events?trace_id=...` every 2 seconds.
- **Footer actions**: `[clear log]` (DELETE) and `[copy trace_id]`.

No npm build step, no React, no webpack — the script is a single file of vanilla JS shipped with the gem.

---

## 6. MCP Server

### 6.1. Entry

```bash
bundle exec e11y mcp              # stdio transport (Claude Desktop, Cursor)
bundle exec e11y mcp --port 3099  # StreamableHTTP transport (WEBrick)
```

### 6.2. Tools

The MCP server exposes 8 tools backed by `DevLog::Query`:

| Tool | Description |
|---|---|
| `RecentEvents` | Most recent N events (default 50) |
| `EventsByTrace` | All events for a given `trace_id` |
| `Search` | Full-text search across event JSON |
| `Stats` | Summary: total count, error rate, top event types |
| `Interactions` | Grouped interaction list (same grouping as TUI) |
| `EventDetail` | Full data for a single event by ID |
| `Errors` | All events with severity `error` or `fatal` |
| `Clear` | Truncate the log file |

### 6.3 AI Tool Setup

**Cursor** (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "e11y": {
      "command": "bundle",
      "args": ["exec", "e11y", "mcp"],
      "cwd": "/path/to/your/rails/app"
    }
  }
}
```

**Claude Code** (`.claude/mcp.json` or `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "e11y": {
      "command": "bundle",
      "args": ["exec", "e11y", "mcp"]
    }
  }
}
```

Once connected, ask your AI assistant: *"What errors happened in the last request?"* or *"Show me all events for trace abc-123"*.

### 6.4. Server Context

The `server_context` passed to every tool handler contains:

```ruby
{ store: E11y::Adapters::DevLog::Query.new(log_path) }
```

Tools call `context[:store]` directly — no shared mutable state between requests.

---

## 7. CLI Entry Point

The `e11y` executable (`gems/e11y-devtools/exe/e11y`) dispatches subcommands:

| Subcommand | Behavior |
|---|---|
| `e11y` (no args) | Launches TUI (default) |
| `e11y tui` | Launches TUI explicitly |
| `e11y mcp` | Starts MCP server on stdio |
| `e11y mcp --port N` | Starts MCP server on port N over HTTP |
| `e11y tail` | Streams new events to stdout (like `tail -f`) |
| `e11y help` | Prints usage |

**Log path auto-detection**: the CLI walks up from `Dir.pwd` looking for `log/e11y_dev.jsonl`, stopping at the first directory that contains it (or a `Gemfile`). This makes it work correctly from any subdirectory of the project.

---

## 8. Monorepo Structure

e11y uses a two-gem monorepo layout:

```
e11y/                              ← root
├── e11y.gemspec                   ← production gem (v0.2.x)
├── lib/
│   └── e11y/
│       └── adapters/
│           └── dev_log/           ← DevLog adapter (production-safe)
│               ├── file_store.rb
│               ├── query.rb
│               └── dev_log.rb
└── gems/
    └── e11y-devtools/             ← separate gem (dev-only)
        ├── e11y-devtools.gemspec
        └── lib/
            └── e11y/
                └── devtools/
                    ├── tui/       ← TUI viewer
                    ├── overlay/   ← Rails Engine + Rack middleware + JS
                    └── mcp/       ← MCP server tools
```

### 8.1 Why Two Gems?

The write-path (`DevLog` adapter, `FileStore`, `Query`, `DevLogSource` middleware) is
**production-safe**: it has zero viewer dependencies and runs in any environment.
It lives in `gem 'e11y'` so production apps can enable it if needed (e.g., for
log-based observability pipelines).

The viewers (TUI via ratatui_ruby, Browser Overlay, MCP Server) are **dev-only** by
design. `ratatui_ruby` ships Rust-compiled binaries; adding it to production gems
inflates deploy size and introduces native-extension compilation. Keeping viewers in
a separate gem makes the dependency opt-in:

```ruby
# Gemfile
gem "e11y"                             # always
gem "e11y-devtools", group: :development  # never reaches production
```

### 8.2. Gem Dependencies

**`e11y.gemspec`** (production gem — no devtools dependencies):
```ruby
# No ratatui_ruby, no mcp gem here
```

**`gems/e11y-devtools/e11y-devtools.gemspec`** (opt-in dev gem):
```ruby
spec.add_dependency "e11y",          "~> 0.2"
spec.add_dependency "ratatui_ruby",  "~> 1.4"
spec.add_dependency "mcp",           ">= 1.0"
```

Developers add `e11y-devtools` only to the `:development` group in their Gemfile:

```ruby
gem "e11y"

group :development do
  gem "e11y-devtools"
end
```

---

## 9. Noise Reduction Philosophy

Local development log noise is the primary usability concern. e11y-devtools applies noise reduction at three independent layers:

### Layer 1: Buffer Flush (inherited from e11y core)

Debug-level events accumulate in the request-scoped buffer (see ADR-001). They are written to `log/e11y_dev.jsonl` **only when the request fails**. A successful request produces zero debug-level entries in the devlog.

### Layer 2: Viewer Defaults

| Viewer | Default filter |
|---|---|
| TUI | `:web` source filter — shows only web request interactions, not background jobs |
| Browser Overlay | Current trace only — the panel shows only events from the active request |
| MCP `recent_events` | `limit: 50` — bounded by default |

### Layer 3: Interaction Grouping

A single user action typically spawns multiple async traces (background jobs, ActionCable, webhooks). The TUI groups traces within a 500 ms window into one `Interaction` row, reducing visual noise from N rows to 1.

The three layers are independent. Any one layer alone would reduce noise meaningfully; together they make the default view tractable even in busy development servers.

---

## 10. Technology Choices & Alternatives

### 10.1. TUI Library

| Candidate | Chosen? | Rationale |
|---|---|---|
| `ratatui_ruby` | **Yes** | Built-in `TestHelper` for unit testing widgets; 44 published versions (stable); all needed widgets available; single GC (no subprocess) |
| `charm-ruby` | No | ~10 commits total at decision time; no built-in test support |
| Plain ANSI escape codes | No | Custom widget code duplication; no input handling |

### 10.2. MCP Library

| Candidate | Chosen? | Rationale |
|---|---|---|
| `mcp` (Anthropic+Shopify) | **Yes** | StreamableHTTP transport; full MCP spec compliance; actively maintained by protocol authors |
| `fast-mcp` | No | No StreamableHTTP support at decision time; community-maintained, not spec-complete |
| Custom JSON-RPC | No | Significant maintenance surface; no transport flexibility |

### 10.3. Trace Grouping Strategy

| Approach | Chosen? | Rationale |
|---|---|---|
| Time-window grouping (500 ms) | **Yes** | No client-side coordination; zero configuration; works without HTTP header support |
| `X-Interaction-ID` header | No | Requires all clients (background jobs, ActionCable) to propagate a custom header; breaks for third-party callers |

### 10.4. File Watch Strategy

| Approach | Chosen? | Rationale |
|---|---|---|
| Poll `File.mtime` every 250 ms | **Yes** | Zero native dependencies; works on macOS, Linux, Docker without kernel feature flags |
| `inotify` / `kqueue` | No | Platform-specific; adds C extension dependency; Docker volume mounts may not deliver events |
| `listen` gem | No | Pulls in `rb-fsevent` / `rb-inotify`; heavy for a dev-only tool |

### 10.5. Browser Overlay Build

| Approach | Chosen? | Rationale |
|---|---|---|
| Vanilla JS Custom Element | **Yes** | No npm build; zero-config; ships as a single `.js` file in the gem |
| React SPA | No | Requires npm build step; breaks zero-config install; 100 KB+ overhead |
| Separate dev server | No | Port management; firewall issues; second process to manage |

---

## 11. Trade-offs

### 11.1. Accepted Trade-offs

**Polling instead of push**: The 250 ms poll interval means the TUI and overlay lag by up to 250 ms. This is imperceptible in practice for a developer tool and eliminates all platform-specific file-watch dependencies.

**JSONL over SQLite**: A flat JSONL file is simpler to rotate, inspect with standard tools (`tail`, `jq`), and ship without native dependencies. Random-access query performance at 10 000 events (the default limit) is acceptable with the mtime-cached in-memory parse.

**Interaction grouping is heuristic**: The 500 ms window is a heuristic — it may merge unrelated concurrent requests or split a single slow interaction. It is a viewer-level concern only; the raw JSONL contains full per-trace data for manual inspection.

**No structured query language**: The `search` method is full-text across serialized JSON. This is sufficient for local development workflows and avoids embedding a query parser.

### 11.2. Future Considerations

- Configurable `window_ms` for interaction grouping (currently hard-coded at 500).
- WebSocket push from the overlay controller to eliminate polling lag in the browser.
- Index file alongside JSONL for O(1) trace lookup at scale (relevant if `max_lines` is raised significantly).
- `e11y tail` output formats: JSON, pretty-print, structured table.
