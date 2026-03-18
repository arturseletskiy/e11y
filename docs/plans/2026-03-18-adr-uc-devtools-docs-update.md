# ADR/UC Devtools Documentation Update Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fully rewrite ADR-010 and UC-017 to reflect the actual e11y-devtools implementation; update ADR-INDEX, UC-001, and CLAUDE.md accordingly.

**Architecture:** Hub-and-Spoke devtools ecosystem — single JSONL file (`log/e11y_dev.jsonl`) as source of truth, three independent viewers (TUI via ratatui_ruby, Browser Overlay via Rails Engine, MCP Server via official `mcp` gem), production-safe core adapter in `gem 'e11y'`, viewers in `gem 'e11y-devtools'`.

**Tech Stack:** Ruby 3.2+, Rails 7–8, ratatui_ruby ~> 1.4, gem 'mcp' (official Anthropic+Shopify SDK), vanilla JS + Shadow DOM, Zlib gzip rotation.

**Worktree:** `.worktrees/feat-docs-update` on branch `feat/docs-adr-uc-devtools`

---

## Phase 1: Core documents

### Task 1: Rewrite ADR-010

**File:** `docs/ADR-010-DEVELOPER-EXPERIENCE.md` (currently 1956 lines, Draft)

This is a complete replacement. The existing file describes imaginary components
(`ConsoleAdapter`, unbuilt Web UI, unbuilt Event Registry). Replace with accurate
description of what was actually built.

**Step 1: Read the current file to understand its scope**

```bash
wc -l docs/ADR-010-DEVELOPER-EXPERIENCE.md
head -30 docs/ADR-010-DEVELOPER-EXPERIENCE.md
```

**Step 2: Write the new ADR-010**

Replace the entire file with the following content (expand each section to
be complete and accurate):

```markdown
# ADR-010: Developer Experience

**Status:** Accepted
**Date:** March 18, 2026
**Covers:** UC-017 (Local Development)
**Depends On:** ADR-001 (Core), ADR-004 (Adapter Architecture), ADR-008 (Rails Integration)

---

## 📋 Table of Contents

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
```

**Section 1 — Context & Problem** (real pain points, no fictional code):

```markdown
## 1. Context & Problem

### 1.1 Problem Statement

Before devtools, developing with e11y meant firing events into the void:

- Events were routed to production adapters (Loki, Sentry) with no local visibility
- Debug-level events were silently discarded unless a request failed (buffer flush)
- No way to correlate events from a single user interaction across parallel requests
- No tooling for AI-assisted debugging (Cursor, Claude Code) to query event history

### 1.2 Requirements

| Requirement | Priority |
|-------------|----------|
| Zero-config: auto-activate in development | Must |
| Post-mortem debugging: browse past events | Must |
| Real-time awareness: see events as they happen | Must |
| Interaction grouping: N parallel traces → 1 row | Must |
| Production-safe: no devtools code in production gem | Must |
| AI integration: MCP Server for Cursor / Claude Code | Should |
| No extra services required (no Redis, no DB) | Must |
```

**Section 2 — Hub-and-Spoke Architecture** (ASCII diagram + explanation):

```markdown
## 2. Architecture: Hub-and-Spoke

Single source of truth: `log/e11y_dev.jsonl`. All viewers read independently.

```
                    ┌─────────────────────┐
  Rails request ───►│   E11y Pipeline     │
  Background job ──►│   (middleware)      │
  Console ─────────►│                     │
                    └──────────┬──────────┘
                               │ DevLog Adapter
                               ▼ (write)
                    ┌─────────────────────┐
                    │  log/e11y_dev.jsonl │  ← single source of truth
                    │  (JSONL, gzip rot.) │
                    └──────┬──────┬───────┘
                           │      │       └─────────────────┐
                     (read)│      │(read)                   │(read)
                           ▼      ▼                         ▼
               ┌───────────────┐ ┌──────────────┐ ┌──────────────────┐
               │  TUI          │ │   Browser    │ │  MCP Server      │
               │  (ratatui_   │ │   Overlay    │ │  (8 tools, AI)   │
               │   ruby)       │ │  (Rails Eng) │ │                  │
               └───────────────┘ └──────────────┘ └──────────────────┘
```

**Key insight:** Each viewer is stateless — it holds no events of its own.
The JSONL file is the only persistent store. Viewers can be started, stopped,
or replaced without data loss.
```

**Section 3 — DevLog Adapter** (FileStore + Query, rotation, caching):

Describe both sub-components:

- **FileStore** (`lib/e11y/adapters/dev_log/file_store.rb`):
  - Thread-safe via `Mutex` + `File::LOCK_EX` (multi-process safe)
  - Numbered gzip rotation: `.1.gz`, `.2.gz`, ... up to `keep_rotated` (default 5)
  - Atomic rotation: compress to `.tmp`, then `File.rename`
  - Streaming gzip: `IO.copy_stream` (no full-file heap allocation)
  - Constants: `DEFAULT_MAX_SIZE = 50 * 1024 * 1024`, `DEFAULT_MAX_LINES = 10_000`, `DEFAULT_KEEP_ROTATED = 5`

- **Query** (`lib/e11y/adapters/dev_log/query.rb`):
  - mtime-invalidated in-memory cache (re-reads only when file changes)
  - `stored_events(limit:, severity:, source:)` — newest-first
  - `search(query_str)` — full-text in event_name + payload JSON
  - `events_by_trace(trace_id)` — chronological for one trace
  - `interactions(window_ms: 500)` — time-window grouping → `Interaction` structs
  - `stats` — total, by_severity, by_event_name, file_size
  - Zero Rails dependency (stdlib only: `json`, `time`, `fileutils`)

- **Railtie auto-registration** (`lib/e11y/railtie.rb`):
  - Activates in `development` and `test` environments
  - Guard: only if `:dev_log` adapter not already configured
  - Mounts `DevLogSource` Rack middleware to set `Thread.current[:e11y_source]`
  - Respects ENV: `E11Y_MAX_EVENTS`, `E11Y_MAX_SIZE`, `E11Y_KEEP_ROTATED`

**Section 4 — TUI** (ratatui_ruby, keyboard navigation, interaction grouping):

```markdown
## 4. TUI — Interactive Log Viewer

**Entry:** `bundle exec e11y` (or `bundle exec e11y tui`)
**Library:** ratatui_ruby ~> 1.4

### 4.1 Navigation Model

Three nested views, navigated with keyboard:

```
:interactions  ──[Enter]──►  :events  ──[Enter]──►  :detail
               ◄──[Esc]──               ◄──[Esc/b]──
```

**Interactions view** (left panel):
- One row per interaction group (parallel requests from a single user action)
- Bullet: `●` red (has error) / `○` gray (clean)
- Shows: time, request count, error indicator

**Events view** (right panel):
- Table: #, Severity (colored), Event Name, Duration, Timestamp
- Filtered to selected interaction's trace IDs

**Detail overlay**:
- Full event payload (pretty-printed JSON)
- `[c]` copy to clipboard, `[b]` / `[Esc]` back

### 4.2 Keyboard Map

| Key | Context | Action |
|-----|---------|--------|
| `j` / `↓` | interactions, events | Move down |
| `k` / `↑` | interactions, events | Move up |
| `Enter` | interactions | Drill into events |
| `Enter` | events | Open detail overlay |
| `Esc` / `b` | events, detail | Go back |
| `w` | interactions | Filter: web requests only |
| `j` | interactions | Filter: background jobs only |
| `a` | interactions | Filter: all sources |
| `r` | interactions | Force reload |
| `q` / `Ctrl-c` | any | Quit |
| `c` | detail | Copy event JSON to clipboard |

### 4.3 Interaction Grouping

Implemented in `E11y::Devtools::Tui::Grouping.group(traces, window_ms:)`:

- Sort traces by `started_at`
- Open new group when gap > `window_ms` (default 500ms)
- Group inherits `has_error?` from any error/fatal trace within it
- Return groups newest-first

### 4.4 File Watching

`App#reload_if_changed!` polls `File.mtime` every `POLL_INTERVAL_MS = 250`.
No inotify/kqueue dependency — pure Ruby, works cross-platform.
```

**Section 5 — Browser Overlay** (Rails Engine, Rack middleware, Shadow DOM):

```markdown
## 5. Browser Overlay

**Gem:** `e11y-devtools`
**Path:** `gems/e11y-devtools/lib/e11y/devtools/overlay/`

### 5.1 Components

**Rails Engine** (`overlay/engine.rb`):
- Mounts at `/_e11y/` (isolated namespace)
- Auto-mounts `Overlay::Middleware` in development only

**JSON Endpoints** (`overlay/controller.rb`):
- `GET  /_e11y/events?trace_id=<id>` — events for one trace
- `GET  /_e11y/events/recent?limit=N` — recent N events (default 50)
- `DELETE /_e11y/events` — clear log (returns 204)
- All endpoints return 404 outside development

**Rack Middleware** (`overlay/middleware.rb`):
- Injects `<script>` tag before `</body>` in HTML responses only
- Skips: XHR requests, asset paths (`/assets/`, `/packs/`, `/_e11y/`)
- Updates `Content-Length` header after injection
- Injects `window.__E11Y_TRACE_ID__` from `env["e11y.trace_id"]`

**Vanilla JS + Shadow DOM** (`overlay/assets/overlay.js`):
- Custom element `<e11y-overlay>` — Shadow DOM isolates all CSS
- Floating badge (bottom-right): `e11y  N  ● E` (event count, error count)
- Red border when errors present
- Click badge → slide-in panel with event list
- Auto-polls `/_e11y/events/recent` every 2 seconds
- `[clear log]` and `[copy trace_id]` footer actions
```

**Section 6 — MCP Server** (8 tools, transports):

```markdown
## 6. MCP Server

**Entry:** `bundle exec e11y mcp [--port N]`
**Library:** `gem 'mcp'` (official Anthropic + Shopify SDK)
**Path:** `gems/e11y-devtools/lib/e11y/devtools/mcp/`

### 6.1 Tools

| Tool | Description |
|------|-------------|
| `recent_events` | Last N events (filterable by severity) |
| `events_by_trace` | All events for a trace_id (chronological) |
| `search` | Full-text search in event_name + payload |
| `stats` | Aggregate: total, by_severity, by_event_name, file_size |
| `interactions` | Time-grouped interactions (newest-first) |
| `event_detail` | Full event by UUID |
| `errors` | Recent error/fatal events only |
| `clear` | Clear the log file |

### 6.2 Transports

**stdio** (default — for Cursor, Claude Code):
```bash
bundle exec e11y mcp
```

**HTTP** (for browser-based AI tools):
```bash
bundle exec e11y mcp --port 3099
# → WEBrick + StreamableHTTP at http://localhost:3099/mcp
```

### 6.3 Cursor Setup

```json
// .cursor/mcp.json
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
```

**Section 7 — CLI Entry Point**:

```markdown
## 7. CLI Entry Point

`gems/e11y-devtools/exe/e11y` dispatches subcommands:

| Command | Description |
|---------|-------------|
| `bundle exec e11y` | Launch TUI (default) |
| `bundle exec e11y tui` | Launch TUI explicitly |
| `bundle exec e11y mcp` | Start MCP server (stdio) |
| `bundle exec e11y mcp --port N` | Start MCP server (HTTP) |
| `bundle exec e11y tail` | Stream new events to stdout |
| `bundle exec e11y help` | Show help |

Auto-detection: walks up from `Dir.pwd` looking for `log/e11y_dev.jsonl`.
```

**Section 8 — Monorepo Structure**:

```markdown
## 8. Monorepo Structure

Two gemspecs in one repository (Rails-style monorepo):

```
e11y/                              ← gem 'e11y' (production-safe)
├── lib/e11y/adapters/dev_log.rb   ← DevLog adapter façade
├── lib/e11y/adapters/dev_log/
│   ├── file_store.rb              ← JSONL write, gzip rotation
│   └── query.rb                  ← Read API, caching, interactions
├── lib/e11y/middleware/dev_log_source.rb
└── lib/e11y/railtie.rb            ← auto-registration

gems/e11y-devtools/               ← gem 'e11y-devtools' (dev-only)
├── exe/e11y                      ← CLI entry point
├── lib/e11y/devtools/
│   ├── tui/app.rb                ← Main TUI loop
│   ├── tui/grouping.rb           ← Interaction grouping algorithm
│   ├── tui/widgets/              ← ratatui_ruby widgets
│   ├── overlay/engine.rb         ← Rails Engine
│   ├── overlay/controller.rb     ← JSON API endpoints
│   ├── overlay/middleware.rb     ← HTML injection
│   ├── overlay/assets/overlay.js ← Shadow DOM badge + panel
│   └── mcp/server.rb             ← MCP Server
│   └── mcp/tools/                ← 8 MCP tool files
└── e11y-devtools.gemspec
```

**Why split?** The `ratatui_ruby` gem includes Rust-compiled binaries.
Keeping it in a separate gem ensures production deploys don't pull
native extensions.
```

**Section 9 — Noise Reduction Philosophy**:

```markdown
## 9. Noise Reduction Philosophy

Three independent layers reduce signal-to-noise ratio:

**Layer 1: Buffer flush (existing feature, enhanced)**
Debug-level events accumulate in a request-scoped buffer. On success: discarded.
On failure: flushed to all registered adapters — including DevLog.
Result: debug events appear in the log *only* for failed requests.

**Layer 2: Viewer defaults**
- TUI: starts with `source_filter = :web` (no background jobs by default)
- Browser Overlay: shows last 20 events for current trace only
- Both show all severities but display error/warn prominently (color coding)

**Layer 3: Interaction grouping**
Parallel requests triggered by one user click (e.g., page load spawning 4 XHRs)
are grouped into one row in the TUI. Developer sees one interaction, not 4.
Drill-down reveals individual traces.
```

**Section 10 — Technology Choices & Alternatives**:

```markdown
## 10. Technology Choices & Alternatives

### 10.1 TUI Library: ratatui_ruby vs charm-ruby

| Criterion | ratatui_ruby | charm-ruby |
|-----------|-------------|------------|
| Built-in TestHelper | ✅ Yes | ❌ No |
| Widget coverage | ✅ Table, List, Paragraph, Block | ⚠️ Basic |
| Maturity | ✅ 44 versions | ⚠️ 10 commits |
| GC pressure | ✅ Single Rust GC | ❌ Bridge overhead |
| Pre-compiled binaries | ✅ Yes | ❌ No |

**Decision: ratatui_ruby** — built-in TestHelper and widget maturity were decisive.

### 10.2 MCP Library: gem 'mcp' vs fast-mcp

| Criterion | gem 'mcp' (official) | fast-mcp |
|-----------|---------------------|----------|
| StreamableHTTP transport | ✅ Yes | ❌ No |
| Full MCP spec compliance | ✅ Yes | ⚠️ Partial |
| Maintained by | Anthropic + Shopify | Community |
| RSpec utilities | ✅ Yes | ❌ No |

**Decision: gem 'mcp'** — StreamableHTTP transport and full spec compliance.

### 10.3 X-Interaction-ID vs Time-Window Grouping

Considered adding an `X-Interaction-ID` header to group related requests at
the HTTP layer. Rejected: requires client-side JS coordination, adds coupling.

**Decision: Pure time-window algorithm** — traces starting within 500ms → one group.
No coordination between client and server needed.

### 10.4 Rejected: X-Interaction-ID header

Would require JavaScript on every page to generate and attach an ID to all
parallel requests. Too invasive for a zero-config tool.

### 10.5 Rejected: Separate SPA for Web UI

Initial design considered a React SPA with its own server. Rejected:
- Requires npm build step (breaks zero-config goal)
- Separate server means port management in dev
- Shadow DOM badge is sufficient for in-page awareness;
  TUI is sufficient for deep analysis
```

**Section 11 — Trade-offs**:

```markdown
## 11. Trade-offs

| Decision | Pro | Con |
|----------|-----|-----|
| JSONL (text) vs binary | Human-readable, grep-able | Slower than binary for large files |
| Polling vs inotify/kqueue | Zero deps, cross-platform | 250ms TUI / 2s overlay latency |
| Monorepo vs two repos | Atomic commits, easy dev | Single Gemfile complexity |
| No dedicated server | Zero-config setup | Can't share devtools across team |
| mtime cache invalidation | Simple, correct | Misses if file replaced atomically |
```

**Step 3: Commit**

```bash
git add docs/ADR-010-DEVELOPER-EXPERIENCE.md
git commit -m "docs: rewrite ADR-010 to reflect e11y-devtools implementation (Accepted)"
```

---

### Task 2: Rewrite UC-017

**File:** `docs/use_cases/UC-017-LOCAL-DEVELOPMENT.md` (currently 867 lines, MVP Feature/Draft)

Complete replacement. Existing file describes a fictional `ConsoleAdapter`.
Replace with a practical developer guide matching what was built.

**Step 1: Read the current file structure**

```bash
head -30 docs/use_cases/UC-017-LOCAL-DEVELOPMENT.md
```

**Step 2: Write the new UC-017**

```markdown
# UC-017: Local Development with e11y-devtools

**Status:** Implemented
**Complexity:** Beginner
**Setup Time:** 2 minutes (zero-config) or 5 minutes (manual)
**Target Users:** All Rails Developers
**Related ADR:** [ADR-010: Developer Experience](../ADR-010-DEVELOPER-EXPERIENCE.md)

---

## 📋 Overview

### Problem Statement

Before e11y-devtools, local development meant:
- Events disappeared silently (routed to production backends)
- No visibility into what was tracked or why
- Debug events were discarded unless a request failed
- No way to correlate parallel XHR requests from one user click

### Solution

e11y-devtools provides three complementary viewers for development:

| Tool | When to use |
|------|-------------|
| **Browser Overlay** | While browsing your app — badge shows real-time event count |
| **TUI** | Post-request analysis — keyboard-driven event browser |
| **MCP Server** | AI-assisted debugging — ask Cursor/Claude about your events |

All three read from a single JSONL file (`log/e11y_dev.jsonl`). No extra services.

---

## 🚀 Setup

### Zero-Config (Recommended)

The `DevLog` adapter is auto-registered in development/test via Railtie.
Add the gem and start your app:

```ruby
# Gemfile
gem "e11y-devtools", group: :development
```

```bash
bundle install
rails server
# → log/e11y_dev.jsonl is created automatically
```

### Manual Configuration

Override Railtie defaults in `config/environments/development.rb`:

```ruby
E11y.configure do |config|
  config.register_adapter :dev_log, E11y::Adapters::DevLog.new(
    path:           Rails.root.join("log", "e11y_dev.jsonl"),
    max_lines:      ENV.fetch("E11Y_MAX_EVENTS",    10_000).to_i,
    max_size:       ENV.fetch("E11Y_MAX_SIZE",           50).to_i * 1024 * 1024,
    keep_rotated:   ENV.fetch("E11Y_KEEP_ROTATED",        5).to_i,
    enable_watcher: true
  )
end
```

---

## 🖥️ TUI — Interactive Log Viewer

**Launch:**
```bash
bundle exec e11y
# or explicitly:
bundle exec e11y tui
```

**What you see:**

```
┌─ INTERACTIONS ──────────────────────────────────────────────┐
│ ● 14:23:01  3 req  ● err                                    │  ← selected
│ ○ 14:22:58  1 req                                           │
│ ○ 14:22:45  2 req                                           │
└─────────────────────────────────────────────────────────────┘

Navigate: j/k or ↑/↓   Drill: Enter   Filter: w=web j=jobs a=all   Quit: q
```

Each row is one **interaction** — all parallel requests from a single user action.
`●` red means at least one request had an error/fatal event.

**Drill into events (Enter):**

```
┌─ abc-123-def ───────────────────────────────────────────────┐
│ # │ Severity │ Event Name           │ Duration │ At         │
│ 1 │ ERROR    │ payment.failed       │ 143ms    │ .231       │
│ 2 │ INFO     │ payment.attempt      │ 12ms     │ .089       │
│ 3 │ DEBUG    │ db.query             │ 3ms      │ .086       │
└─────────────────────────────────────────────────────────────┘
```

**Full keyboard map:**

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Drill in (interactions→events→detail) |
| `Esc` / `b` | Go back |
| `w` | Show web requests only |
| `j` | Show background jobs only |
| `a` | Show all sources |
| `r` | Force reload |
| `q` | Quit |
| `c` | Copy event JSON to clipboard (in detail) |

---

## 🟢 Browser Overlay

The overlay activates automatically when `e11y-devtools` is in your Gemfile
and the Rails Engine is mounted. No configuration needed.

**The badge** (bottom-right corner of every page):

```
┌──────────────┐
│ e11y  12 ● 2 │   ← 12 events, 2 errors
└──────────────┘
```

Red border = at least one error in the current page's events.

**Click to open the panel:**

```
┌─ GET /orders/123 ──────────────────── ✕ ─┐
│ ERRO  payment.failed           143ms     │
│ INFO  order.updated             12ms     │
│ INFO  cache.write                2ms     │
│ DEBU  db.query                   3ms     │
│                                          │
│ [clear log]  [copy trace_id]             │
└──────────────────────────────────────────┘
```

Panel shows events for the **current trace** (the page you just loaded).
Auto-refreshes every 2 seconds.

---

## 🤖 MCP Server — AI-Assisted Debugging

**Start:**
```bash
bundle exec e11y mcp
# HTTP mode (for web-based AI tools):
bundle exec e11y mcp --port 3099
```

**Cursor setup** (`.cursor/mcp.json`):

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

**Claude Code setup** (`.claude/mcp.json`):

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

**Available tools:**

| Tool | What you can ask |
|------|-----------------|
| `recent_events` | "What events were tracked in the last minute?" |
| `errors` | "What errors happened today?" |
| `events_by_trace` | "Show me all events for trace abc-123" |
| `search` | "Find events related to payment" |
| `stats` | "How many events are there by severity?" |
| `interactions` | "Show me the last 5 user interactions" |
| `event_detail` | "Show me the full payload of event <uuid>" |
| `clear` | "Clear the event log" |

---

## ⚙️ Configuration Reference

### ENV Variables (override Railtie defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `E11Y_MAX_EVENTS` | `10000` | Max lines before rotation |
| `E11Y_MAX_SIZE` | `50` | Max file size in MB before rotation |
| `E11Y_KEEP_ROTATED` | `5` | Number of `.N.gz` files to keep |

### What goes into the log

Events from all adapters that have `dev_log` registered. Source is tracked:
- `metadata.source = "web"` — HTTP request (set by DevLogSource middleware)
- `metadata.source = "job"` — background job (set when Thread.current[:e11y_source] = "job")
- `metadata.source = "console"` — rails console / rake task

### Debug buffer interaction

When a request **succeeds**, debug-level events are discarded (buffer flushed nowhere).
When a request **fails**, the debug buffer is flushed to all registered adapters —
including DevLog. This is how debug events appear in the log for failed requests only.

---

## ✅ Acceptance Criteria

- [x] Zero config: `gem 'e11y-devtools'` + `rails server` → events in `log/e11y_dev.jsonl`
- [x] TUI: `bundle exec e11y` opens interactive viewer
- [x] Browser Overlay: badge visible on every dev page without configuration
- [x] MCP Server: `bundle exec e11y mcp` starts stdio server accepting tool calls
- [x] Interaction grouping: parallel requests within 500ms → single TUI row
- [x] Debug-on-failure: debug events appear only for failed requests
- [x] Gzip rotation: log rotates at 50MB / 10K lines, keeps 5 `.gz` files
- [x] Production safe: DevLog not registered in production (Railtie guard)
- [x] No extra services: no Redis, no DB, no separate server required
```

**Step 3: Commit**

```bash
git add docs/use_cases/UC-017-LOCAL-DEVELOPMENT.md
git commit -m "docs: rewrite UC-017 to reflect e11y-devtools (Implemented)"
```

---

## Phase 2: Supporting documents

### Task 3: Update ADR-INDEX

**File:** `docs/ADR-INDEX.md`

The index already shows ADR-010 as `✅ Accepted` (pre-existing) — update the
description text and the "Developer Experience" entry in Key Decisions.

**Step 1: Read the relevant lines**

```bash
grep -n "ADR-010\|Developer Experience" docs/ADR-INDEX.md
```

**Step 2: Update ADR-010 entry description**

Find the line:
```
| [ADR-010](ADR-010-developer-experience.md) | Developer Experience (DX) | ✅ Accepted | 5 |
```

Replace with:
```
| [ADR-010](ADR-010-developer-experience.md) | Developer Experience: DevLog adapter, TUI, Browser Overlay, MCP Server (Hub-and-Spoke) | ✅ Accepted | 5 |
```

**Step 3: Update "Developer Experience" section in Key Decisions**

Find:
```markdown
### Developer Experience
- **ADR-010**: Developer experience priorities (5-min setup, conventions)
- **ADR-011**: Testing strategy (RSpec, integration tests, benchmarks)
```

Replace with:
```markdown
### Developer Experience
- **ADR-010**: Hub-and-Spoke devtools — JSONL adapter + TUI (ratatui_ruby) + Browser Overlay (Rails Engine + Shadow DOM) + MCP Server (8 tools, stdio/HTTP)
- **ADR-011**: Testing strategy (RSpec, integration tests, benchmarks)
```

**Step 4: Commit**

```bash
git add docs/ADR-INDEX.md
git commit -m "docs: update ADR-INDEX entry for ADR-010"
```

---

### Task 4: Update UC-001 — add DevLog flush note

**File:** `docs/use_cases/UC-001-request-scoped-debug-buffering.md`

Add a short paragraph connecting the debug buffer flush behavior to DevLog.

**Step 1: Find the flush section**

```bash
grep -n "Flush debug buffer\|Discard debug buffer\|Error → Flush" \
  docs/use_cases/UC-001-request-scoped-debug-buffering.md | head -5
```

**Step 2: Find context around that line**

Read ±20 lines around the flush mention (use the line number from step 1):

```bash
sed -n '<LINE-20>,<LINE+20>p' docs/use_cases/UC-001-request-scoped-debug-buffering.md
```

**Step 3: Add DevLog note**

In the section that explains what happens when a request fails and the debug
buffer is flushed, add after the existing explanation:

```markdown
> **DevLog integration:** When the debug buffer is flushed on request failure,
> events are delivered to all registered adapters — including `E11y::Adapters::DevLog`
> if active (auto-registered in development/test via Railtie). This means debug
> events from failed requests automatically appear in `log/e11y_dev.jsonl` and
> are visible in the TUI and Browser Overlay. See [UC-017](UC-017-LOCAL-DEVELOPMENT.md).
```

Place it immediately after the "Error → Flush debug buffer" explanation block.

**Step 4: Commit**

```bash
git add docs/use_cases/UC-001-request-scoped-debug-buffering.md
git commit -m "docs: add DevLog flush note to UC-001 debug buffer section"
```

---

### Task 5: Verify CLAUDE.md

**File:** `CLAUDE.md`

Check that Key Modules table already reflects devtools (it was updated on the
`feat/e11y-devtools` branch). If the current worktree branch doesn't have those
updates, add them manually.

**Step 1: Check current state**

```bash
grep -A5 "devtools\|dev_log\|DevLog" CLAUDE.md | head -30
```

**Step 2: Ensure Key Modules table has these rows**

If missing, add them to the Key Modules table:

```markdown
| `lib/e11y/adapters/dev_log.rb` | DevLog adapter — JSONL write+read, shared by all devtools viewers |
| `gems/e11y-devtools/` | Developer tools gem (TUI, Browser Overlay, MCP Server) |
| `gems/e11y-devtools/lib/e11y/devtools/tui/` | ratatui_ruby TUI — interaction-centric log viewer |
| `gems/e11y-devtools/lib/e11y/devtools/overlay/` | Rails Engine — floating badge + slide-in panel |
| `gems/e11y-devtools/lib/e11y/devtools/mcp/` | MCP Server — AI integration for Cursor/Claude Code |
```

**Step 3: Ensure Commands section has devtools commands**

```bash
grep -n "bundle exec e11y\|e11y tui\|e11y mcp" CLAUDE.md
```

If missing, add to the Commands section:

```bash
# Run TUI (interactive log viewer)
bundle exec e11y

# Start MCP server (for Cursor / Claude Code)
bundle exec e11y mcp

# Stream events to stdout
bundle exec e11y tail
```

**Step 4: Commit (only if changes were made)**

```bash
git add CLAUDE.md
git commit -m "docs: add devtools commands and modules to CLAUDE.md"
```

---

## Phase 3: Final verification

### Task 6: Review and push

**Step 1: Verify all files look right**

```bash
# Confirm no conflict markers remain
grep -r "<<<<<<\|>>>>>>>" docs/ CLAUDE.md

# Check line counts on rewritten files
wc -l docs/ADR-010-DEVELOPER-EXPERIENCE.md \
       docs/use_cases/UC-017-LOCAL-DEVELOPMENT.md
```

**Step 2: Run tests to confirm no regressions**

```bash
bundle exec rspec spec/e11y spec/e11y_spec.rb spec/zeitwerk_spec.rb 2>&1 | grep -E "examples|failures" | tail -3
```

Expected: same pre-existing failures only (5: slo_spec ×4, memory_spec ×1).

**Step 3: Push and create PR**

```bash
git push -u origin feat/docs-adr-uc-devtools
gh pr create \
  --title "docs: rewrite ADR-010 and UC-017 to reflect e11y-devtools implementation" \
  --body "$(cat <<'EOF'
## Summary

- **ADR-010** (1956 lines → ~300 lines): Full rewrite from Draft to Accepted. Replaces fictional ConsoleAdapter / unbuilt Web UI with accurate Hub-and-Spoke architecture, DevLog adapter, TUI, Browser Overlay, MCP Server.
- **UC-017** (867 lines → ~200 lines): Full rewrite from MVP Feature/Draft to Implemented. Practical developer guide with actual keyboard map, overlay screenshot, MCP tool list.
- **ADR-INDEX**: Updated ADR-010 description row + Key Decisions section.
- **UC-001**: Added DevLog flush note linking debug buffer flush to devtools visibility.
- **CLAUDE.md**: Verified/added devtools modules and commands.

## Test Plan
- [x] No code changes — docs only
- [x] Tests pass (pre-existing failures only)
- [x] No conflict markers in any file

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" \
  --base feat/logs-ui
```

---

## Summary

| Task | File | Change |
|------|------|--------|
| 1 | `docs/ADR-010-DEVELOPER-EXPERIENCE.md` | Full rewrite: Draft → Accepted, ~300 lines |
| 2 | `docs/use_cases/UC-017-LOCAL-DEVELOPMENT.md` | Full rewrite: Draft → Implemented, ~200 lines |
| 3 | `docs/ADR-INDEX.md` | Update ADR-010 row + Key Decisions |
| 4 | `docs/use_cases/UC-001-request-scoped-debug-buffering.md` | Add DevLog flush note |
| 5 | `CLAUDE.md` | Verify/add devtools entries |
| 6 | PR | Push + create PR |
