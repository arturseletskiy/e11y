# E11y Devtools — Design Document

**Date:** 2026-03-18
**Status:** Approved
**Supersedes:** `2026-03-13-devlog-adapter-requirements.md` (draft)
**Branch target:** `feat/e11y-devtools`

---

## 1. Summary

E11y Devtools is a developer-facing observability layer that gives Rails developers
instant, low-noise visibility into what their application is doing — in the terminal,
in the browser, and through AI assistants.

**Core differentiator:** E11y already suppresses ~90% of debug noise via request-scoped
buffering (debug events only flush on failure). Devtools amplifies this: every viewer
defaults to showing only errors and warnings, groups parallel requests into interactions,
and separates web from background jobs. Finding a failed request takes seconds, not minutes.

**Architecture:** Hub-and-Spoke. One JSONL file (`log/e11y_dev.jsonl`) is the single
source of truth. Three thin viewers read from it independently:

```
┌──────────────────────────────────────────────────────────────┐
│  gem 'e11y'  (production-safe)                               │
│                                                              │
│  DevLog Adapter ──write──► log/e11y_dev.jsonl  ◄──read──┐   │
│  (FileStore + Query)        single source of truth        │   │
└───────────────────────────────────────────────────────────┘   │
                                                                │
┌──────────────────────────────────────────────────────────────┐│
│  gem 'e11y-devtools', group: :development                    ││
│                                                              ││
│  ┌──────────────┐  ┌─────────────────┐  ┌───────────────┐  ││
│  │ TUI          │  │ Browser Overlay │  │ MCP Server    │  ││
│  │ ratatui_ruby │  │ Rails Engine    │  │ gem 'mcp'     │  ││
│  │              │  │ Rack middleware │  │ stdio + HTTP  │  ││
│  └──────┬───────┘  └───────┬─────────┘  └───────┬───────┘  ││
│         └──────────────────┴────────────────────-┘          ││
│                   DevLog::Query (shared)                     ││
└──────────────────────────────────────────────────────────────┘│
                        reads JSONL directly                    │
```

---

## 2. Repository Structure (Monorepo, Rails-style)

Two gemspecs in one git repository — same pattern as Rails (`rails/rails`),
RSpec (`rspec/rspec`).

```
e11y/
  e11y.gemspec                          # gem 'e11y'
  lib/
    e11y/
      adapters/
        dev_log.rb                      # public façade (write + read API)
        dev_log/
          file_store.rb                 # JSONL I/O, rotation, locking
          query.rb                      # read API used by all three viewers
  gems/
    e11y-devtools/
      e11y-devtools.gemspec             # gem 'e11y-devtools'
      lib/
        e11y/
          devtools/
            tui/                        # ratatui_ruby TUI
              app.rb                    # top-level RatatuiRuby.run loop
              widgets/
                interaction_list.rb    # left panel: grouped traces
                event_list.rb          # right panel: events in a trace
                event_detail.rb        # full payload overlay
                help_overlay.rb        # [?] help screen
              grouping.rb              # time-window interaction grouping
            overlay/                   # Rails Engine
              engine.rb
              middleware.rb            # HTML injection
              controller.rb            # JSON endpoints (/_e11y/*)
              assets/
                overlay.js             # vanilla JS, Shadow DOM
                overlay.css
            mcp/
              server.rb                # MCP::Server setup
              tools/                   # one file per MCP tool
                recent_events.rb
                events_by_trace.rb
                search.rb
                stats.rb
                interactions.rb
                event_detail.rb
                errors.rb
                clear.rb
      exe/
        e11y                           # CLI entry point (subcommands)
      spec/
        e11y/devtools/
          tui/                         # ratatui_ruby TestHelper specs
          overlay/
          mcp/
```

**Gemfile for the developer's app:**

```ruby
gem 'e11y'
gem 'e11y-devtools', group: :development
```

---

## 3. Noise Reduction Philosophy

Three independent layers, each cutting a different kind of noise:

| Layer | Mechanism | Where |
|-------|-----------|-------|
| **1. Buffer flush** | debug events reach JSONL only when request fails | `e11y` core (existing) |
| **2. Viewer defaults** | show error + warn by default; `[a]` to show all | TUI, Overlay, MCP |
| **3. Interaction grouping** | parallel traces from one user action → one row | TUI, Overlay |

Additional signal boosters:
- `[w]` / `[j]` / `[a]` tabs separate web requests from background jobs
- Errors in any trace of a group make the entire group row red
- Clean (all-green) interactions are compact; error interactions are expanded by default

---

## 4. DevLog Adapter (`gem 'e11y'`)

The only part that lives in the production-safe gem. Write path is called from the
E11y pipeline on every event. Read path (`Query`) is used by all three devtools viewers.

### 4.1 JSONL Event Schema

One JSON object per line, newline-terminated:

```json
{
  "id":         "01958c3e-abc1-7000-8000-0123456789ab",
  "timestamp":  "2026-03-18T12:34:01.092Z",
  "event_name": "payment.charge_failed",
  "severity":   "error",
  "trace_id":   "abc123def456",
  "span_id":    "789xyz",
  "payload":    { "code": "card_declined", "amount": 99.99, "order_id": "ORD-7821" },
  "metadata": {
    "request_id": "req-1",
    "path":       "/orders",
    "method":     "POST",
    "duration_ms": 234,
    "source":     "web"
  }
}
```

`metadata.source` — `"web"` | `"job"` | `"console"`. Set by Railtie from request context.
Used by TUI and Overlay for `[w]`/`[j]`/`[a]` filtering.

### 4.2 FileStore — Write Path

Thread-safe: `Mutex` (in-process) + `File::LOCK_EX` (multi-process / Puma workers).
Append is a single `IO#write` call — no parsing on the write path.

```ruby
# lib/e11y/adapters/dev_log/file_store.rb
class E11y::Adapters::DevLog::FileStore
  def append(json_line)
    @mutex.synchronize do
      @file.flock(File::LOCK_EX)
      @file.write(json_line + "\n")
      @file.flock(File::LOCK_UN)
      rotate_if_needed!
    end
  end
end
```

### 4.3 Rotation

| Parameter | Default | ENV override |
|-----------|---------|-------------|
| `max_size` | **50 MB** | `E11Y_MAX_SIZE` (MB) |
| `max_lines` | 10,000 | `E11Y_MAX_EVENTS` |
| `keep_rotated` | **5** | `E11Y_KEEP_ROTATED` |
| Compression | **gzip** (Zlib, stdlib) | — |

Rotation scheme (triggered on write when threshold exceeded):

```
e11y_dev.jsonl.5.gz  → deleted
e11y_dev.jsonl.4.gz  → e11y_dev.jsonl.5.gz
e11y_dev.jsonl.3.gz  → e11y_dev.jsonl.4.gz
e11y_dev.jsonl.2.gz  → e11y_dev.jsonl.3.gz
e11y_dev.jsonl.1.gz  → e11y_dev.jsonl.2.gz
e11y_dev.jsonl       → gzip → e11y_dev.jsonl.1.gz
                     → new empty e11y_dev.jsonl
```

Current file is always plain text — zero overhead on the write path.
Gzip compression happens synchronously at rotation time (rare event).

### 4.4 Query — Read Path

`Query` is a standalone class: constructed with a file path, no Rails dependency.
Used directly by TUI, Overlay, and MCP Server.

```ruby
q = E11y::Adapters::DevLog::Query.new("log/e11y_dev.jsonl")

# Core API
q.stored_events(limit: 100, severity: nil, source: nil)
q.find_event(id)
q.search(query, limit: 500)
q.events_by_name(name, limit: 500)
q.events_by_severity(severity, limit: 500)
q.events_by_trace(trace_id)
q.interactions(window_ms: 500, limit: 50, source: nil)
q.stats
q.updated_since?(timestamp)
q.clear!
```

`interactions(window_ms:)` — groups traces started within `window_ms` of each other.
Returns `Array<Interaction>` where each `Interaction` has `#traces`, `#started_at`,
`#has_error?`, `#source`.

### 4.5 Performance Strategy

Three techniques — no Rust required at this stage:

**Tail-read for recent events:**
`stored_events(limit: N)` reads backward from end of file until N lines collected.
Parses only N objects, regardless of total file size. Startup cost: ~2ms for N=100.

**Incremental read for real-time TUI:**
Query tracks `@last_position` (byte offset). On each TUI tick, reads only bytes
appended since last position. New events appear in TUI within one render cycle.

**In-memory cache with mtime invalidation:**
Full file parse is cached. Cache is invalidated when `File.mtime` changes.
`search` / `events_by_trace` pay the full parse cost only once per file change.
Subsequent calls on the same file state are instant Ruby enumeration.

**JSON parser:** `oj` if available (2–5× faster, C extension), stdlib `JSON` as fallback.
Transparent via `E11y::Adapters::DevLog::JSON_PARSER = defined?(Oj) ? ... : ...`.

**Rust path (future):**
If benchmarks show bottleneck on large files, the JSONL scanner can be extracted to
a Rust native extension inside `e11y-devtools` (where ratatui_ruby already adds the
Rust build dependency). Target: `DevLog::RustScanner` as optional accelerator with
pure-Ruby fallback. No Rust in `gem 'e11y'` — ever.

### 4.6 Railtie Auto-Registration

```ruby
# lib/e11y/railtie.rb
initializer "e11y.setup_development", after: :load_config_initializers do
  next unless Rails.env.development? || Rails.env.test?
  next if E11y.configuration.adapters.key?(:dev_log)

  E11y.configure do |config|
    config.register_adapter :dev_log, E11y::Adapters::DevLog.new(
      path:           Rails.root.join("log", "e11y_dev.jsonl"),
      max_lines:      ENV.fetch("E11Y_MAX_EVENTS",    10_000).to_i,
      max_size:       ENV.fetch("E11Y_MAX_SIZE",          50).to_i.megabytes,
      keep_rotated:   ENV.fetch("E11Y_KEEP_ROTATED",       5).to_i,
      enable_watcher: !Rails.env.test?
    )
  end
end
```

`metadata.source` is set by a separate Rack middleware (included in Railtie):

```ruby
# Rack middleware sets source on each request
env["e11y.source"] = "web"
Thread.current[:e11y_source] = "web"  # picked up by pipeline
```

---

## 5. CLI (`exe/e11y` in `e11y-devtools`)

Single binary, subcommand architecture. `bundle exec e11y` without arguments
launches TUI — zero friction for the primary use case.

```bash
bundle exec e11y              # → TUI (default)
bundle exec e11y tui          # → TUI (explicit)
bundle exec e11y mcp          # → MCP server (stdio)
bundle exec e11y mcp --port 3099  # → MCP server (HTTP/SSE)
bundle exec e11y tail         # → plain JSONL tail to stdout (pipe-friendly)
bundle exec e11y help         # → list subcommands
```

Auto-detect log path: walks up from `Dir.pwd` looking for `log/e11y_dev.jsonl`,
same as `git` looks for `.git`. Works from any subdirectory of the Rails project.

Override: `bundle exec e11y --file log/e11y_dev.jsonl.1.gz` (reads rotated/compressed).

---

## 6. TUI (`ratatui_ruby`)

### 6.1 Library Choice

**ratatui_ruby** (not charm-ruby). Reasons:
- Built-in test framework (`RatatuiRuby::TestHelper`) — snapshot, event injection, style assertions
- All required widgets out of the box: Table, List, Block, Tabs, Scrollbar, Center, Overlay, Clear
- Single GC (no Go runtime), one process
- Pre-compiled binaries — no Rust toolchain needed at `bundle install`
- Flexible programming style (OOP, not forced Elm Architecture)
- v1.4.2, 44 versions, endorsed by Mike Perham (Sidekiq)

charm-ruby (bubbletea-ruby) is promising but has 10 commits as of 2026-03-18 — too early.

### 6.2 Three-Level Navigation

Breadcrumb navigation (k9s pattern). `Esc` goes up one level, `Enter` drills down.

```
e11y  >  Interactions  >  12:34:01 [3 req]  >  abc123  >  Events
```

**Level 1 — Interactions (default view):**

```
┌─ INTERACTIONS ──────────────────┬─ DETAIL ────────────────────────────────┐
│ ● 12:34:01  3 req  1 err        │  Interaction: 12:34:01 · 3 requests     │
│ ○ 12:33:45  1 req               │  ────────────────────────────────────── │
│ ● 12:33:20  1 req  422          │  ● POST /orders    abc123  234ms  ERROR  │
│ ○ 12:32:58  2 req               │  ○ GET  /cart       def456   89ms        │
│ ○ 12:31:10  1 req               │  ○ POST /analytics  ghi789   12ms        │
│                                 │                                          │
│ [w]eb [j]obs [a]ll              │  → Enter: open trace  · [?]: help       │
└─────────────────────────────────┴──────────────────────────────────────────┘
● = has error/warn   ○ = clean
```

Interaction grouping: traces started within `window_ms` (default 500ms) → one group.
If any trace in a group has error/warn → entire group row is red (`●`).

**Level 2 — Events in a trace:**

```
┌─ abc123 · POST /orders · 234ms · ERROR ───────────────────────────────────┐
│  #  Severity  Event Name              Duration   At                       │
│  1  INFO      order.validation        2ms        12:34:01.001             │
│  2  INFO      payment.charge_started  89ms       12:34:01.003             │
│  3  ERROR     payment.charge_failed   —          12:34:01.092  ◄          │
│  4  INFO      order.rollback          1ms        12:34:01.094             │
│                                                                           │
│  [f]ilter  [/]search  [e]xpand  [b]ack  [c]opy trace_id                  │
└───────────────────────────────────────────────────────────────────────────┘
```

**Level 3 — Event payload:**

```
┌─ payment.charge_failed · ERROR ───────────────────────────────────────────┐
│  timestamp:  2026-03-18T12:34:01.092Z                                    │
│  trace_id:   abc123def456                                                 │
│  span_id:    789xyz                                                       │
│                                                                           │
│  payload:                                                                 │
│    error:      "Card declined"                                            │
│    code:       "card_declined"                                            │
│    amount:     99.99                                                      │
│    order_id:   "ORD-7821"                                                 │
│    user_id:    [FILTERED]          ← PII auto-masked by pipeline          │
│                                                                           │
│  [c]opy JSON  [r]eplay (curl)  [b]ack                                    │
└───────────────────────────────────────────────────────────────────────────┘
```

### 6.3 Keyboard Bindings

| Key | Action |
|-----|--------|
| `Enter` | Drill down |
| `Esc` | Back one level |
| `/` | Fuzzy search (event_name + payload) |
| `f` | Cycle severity filter: error → warn → info → debug → all |
| `w` / `j` / `a` | Filter source: Web / Jobs / All |
| `i` | Toggle Interaction View ↔ Trace View (flat chronological list) |
| `r` | Force refresh (re-read JSONL) |
| `c` | Copy trace_id to clipboard |
| `C` | Copy full event JSON to clipboard |
| `q` | Quit |
| `?` | Help overlay |

### 6.4 Real-Time Updates

TUI uses incremental reads (tracked byte offset). New lines appended to JSONL
appear in the interaction list on the next render cycle without resetting cursor
position. No manual `r` needed during normal development.

File watching:
- macOS: `kqueue` via rb-kqueue (or polling fallback)
- Linux: `inotify` directly
- Fallback: 250ms polling interval

### 6.5 Testing

```ruby
# spec/e11y/devtools/tui/interaction_list_spec.rb
RSpec.describe E11y::Devtools::Tui::InteractionListWidget do
  include RatatuiRuby::TestHelper

  it "marks interaction red when any trace has error" do
    traces = [build_trace(:error, path: "/orders"),
              build_trace(:info,  path: "/cart")]

    with_test_terminal(80, 10) do
      RatatuiRuby.draw { |f| f.render_widget(described_class.new(traces), f.area) }
      assert_cell_style 0, 0, char: "●", fg: :red
    end
  end

  it "groups traces within 500ms window into one interaction" do
    t0 = Time.now
    traces = [build_trace(started_at: t0),
              build_trace(started_at: t0 + 0.3),   # 300ms — within window
              build_trace(started_at: t0 + 1.2)]   # 1200ms — new group
    groups = described_class.group_by_time_window(traces, window_ms: 500)
    expect(groups.size).to eq(2)
    expect(groups.first.traces.size).to eq(2)
  end
end
```

---

## 7. Browser Overlay (Rails Engine)

### 7.1 Concept

Sentry Spotlight / rack-mini-profiler pattern: floating badge injected into every
HTML response in development. No separate tab, no `localhost:3001` — the overlay
lives inside the developer's own application.

### 7.2 User Experience

**Default state — minimal badge (bottom-right corner):**

```
                                          ┌──────────────┐
  [application content]                  │  e11y  3 ● 1 │
                                          └──────────────┘
```

`3` = events on last request. `●1` = one error. Red if error present, grey if clean.
Click → slide-in panel from right.

**Expanded panel:**

```
┌─────────────────────────── e11y devtools ──── [×] ──┐
│  POST /orders · abc123 · 234ms · ● ERROR            │
│  ──────────────────────────────────────────────────  │
│  [Events]  [Payload]  [Stats]                        │
│                                                      │
│  #  sev    event_name                ms    at        │
│  1  info   order.validation           2    .001      │
│  2  info   payment.charge_started    89    .003      │
│  3  error  payment.charge_failed      —    .092  ◄   │
│  4  info   order.rollback             1    .094      │
│                                                      │
│  ──────────────────────────────────────────────────  │
│  [clear log]  [copy trace_id]  [open in TUI ↗]      │
└──────────────────────────────────────────────────────┘
```

**"Open in TUI ↗"** deep-link: copies `trace_id` and launches TUI filtered to that
trace — coherent experience between the two viewers.

### 7.3 Implementation

**Rack middleware** (`E11y::Devtools::Overlay::Middleware`) injects `<script>` + `<style>`
before `</body>` only when:

1. `Rails.env.development?`
2. `Content-Type: text/html`
3. Not an XHR request (`HTTP_X_REQUESTED_WITH != XMLHttpRequest`)
4. Not an asset path (`/assets/`, `/packs/`)

`trace_id` of the current request is passed via `env["e11y.trace_id"]` (set by E11y's
existing Rack middleware).

**JSON endpoints** (mounted by the Rails Engine, no `routes.rb` change needed):

```
GET    /_e11y/events?trace_id=abc123    → events for current trace
GET    /_e11y/events/recent?limit=50    → recent events (Stats tab)
DELETE /_e11y/events                    → clear log
```

All endpoints: respond only in `Rails.env.development?`, otherwise 404.

**CSS isolation:** overlay renders inside a `<e11y-overlay>` custom element with
Shadow DOM. Application styles cannot bleed in; overlay styles cannot leak out.

**Vanilla JS only.** No React, Vue, or build step. The overlay must not conflict with
the application's own JavaScript dependencies.

### 7.4 SPA / Turbo Support

In Turbo/SPA apps the page doesn't reload between navigations.
Badge updates via polling `/_e11y/events/recent` every 2 seconds.
When a new trace_id appears (new request completed), the badge updates automatically.

### 7.5 Scope

| Included (Phase 1) | Excluded |
|--------------------|----------|
| Floating badge (count + error dot) | WebSocket / ActionCable (polling sufficient) |
| Slide-in panel with Events + Payload + Stats | Full request history (that's TUI) |
| JSON payload tree view | Charts / analytics |
| Clear log button | Auth / protection (dev-only) |
| "Open in TUI" deep-link | Custom themes |
| Shadow DOM CSS isolation | |
| SPA / Turbo polling support | |

---

## 8. MCP Server

### 8.1 Library

**`gem 'mcp'`** — official Ruby SDK, maintained by Anthropic + Shopify.

Reasons over `fast-mcp`:
- Full MCP spec compliance (2025-06-18 + 2026-01-26 draft)
- StreamableHTTP transport (SSE is deprecated since 2025-03-26)
- RSpec testing utilities built-in
- Zero Rails dependency — pure Ruby server

### 8.2 Launch

```bash
bundle exec e11y mcp              # stdio transport (Cursor, Claude Code)
bundle exec e11y mcp --port 3099  # HTTP/StreamableHTTP (multiple clients)
```

`.cursor/mcp.json` (one-time setup):

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

### 8.3 Tools

| Tool | Parameters | Description |
|------|-----------|-------------|
| `e11y_recent_events` | `limit`, `severity` | Last N events, optional severity filter |
| `e11y_events_by_trace` | `trace_id` | All events for one request in chronological order |
| `e11y_search` | `query`, `limit` | Full-text search across event_name and payload |
| `e11y_stats` | — | Total counts, by_severity, by_event_name, file size |
| `e11y_interactions` | `limit`, `window_ms` | Time-grouped interaction list (same as TUI Level 1) |
| `e11y_event_detail` | `event_id` | Full payload of a single event |
| `e11y_errors` | `limit` | error + fatal events only, newest first |
| `e11y_clear` | — | Clear the JSONL log file |

### 8.4 Tool Definition Pattern

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/tools/recent_events.rb
class E11y::Devtools::Mcp::Tools::RecentEvents < MCP::Tool
  description "Get recent E11y events from the development log"

  input_schema(
    type: :object,
    properties: {
      limit:    { type: :integer, description: "Max events to return", default: 50 },
      severity: { type: :string,  description: "Filter by severity",
                  enum: %w[debug info warn error fatal] }
    }
  )

  def self.call(limit: 50, severity: nil, server_context:)
    server_context[:store].stored_events(limit: limit, severity: severity)
  end
end
```

### 8.5 Server Setup

```ruby
# gems/e11y-devtools/lib/e11y/devtools/mcp/server.rb
class E11y::Devtools::Mcp::Server
  TOOLS = [
    Tools::RecentEvents, Tools::EventsByTrace, Tools::Search,
    Tools::Stats, Tools::Interactions, Tools::EventDetail,
    Tools::Errors, Tools::Clear
  ].freeze

  def initialize(log_path: auto_detect_log_path)
    @store = E11y::Adapters::DevLog::Query.new(log_path)
  end

  def run(transport: :stdio, port: nil)
    server = MCP::Server.new(
      name:           "e11y",
      version:        E11y::Devtools::VERSION,
      tools:          TOOLS,
      server_context: { store: @store }
    )
    # stdio or StreamableHTTP based on transport param
    start_transport(server, transport, port)
  end

  private

  def auto_detect_log_path
    # Walk up from Dir.pwd looking for log/e11y_dev.jsonl (git-style)
    dir = Pathname.new(Dir.pwd)
    loop do
      candidate = dir.join("log", "e11y_dev.jsonl")
      return candidate.to_s if candidate.exist?
      parent = dir.parent
      break if parent == dir
      dir = parent
    end
    "log/e11y_dev.jsonl"  # fallback: relative to cwd
  end
end
```

### 8.6 AI Workflow Example

```
Developer: "Почему последний запрос упал?"

AI calls:
  1. e11y_errors(limit: 1)
     → { trace_id: "abc123", event_name: "payment.charge_failed",
         payload: { code: "card_declined", amount: 99.99 } }

  2. e11y_events_by_trace(trace_id: "abc123")
     → [order.validation ✓, payment.charge_started ✓, payment.charge_failed ✗,
        order.rollback ✓]

AI: "В trace abc123 (POST /orders, 234ms) упал шаг payment.charge_failed.
     Предшествующие шаги прошли успешно. Payload: code=card_declined.
     Stripe отклонил карту. Рекомендую проверить retry-логику в PaymentService."
```

---

## 9. Interaction Grouping (shared logic)

Used identically in TUI Level 1, Overlay badge, and `e11y_interactions` MCP tool.
Implemented in `DevLog::Query#interactions` — single source, three consumers.

```ruby
# Algorithm
def interactions(window_ms: 500, limit: 50, source: nil)
  traces = traces_from_cache(source: source)
  groups = []
  current_group = nil

  traces.sort_by { |t| t[:started_at] }.each do |trace|
    if current_group.nil? ||
       (trace[:started_at] - current_group.last_started_at) * 1000 > window_ms
      current_group = Interaction.new(started_at: trace[:started_at])
      groups << current_group
    end
    current_group.add_trace(trace)
  end

  groups.last(limit)
end
```

`Interaction` is a plain value object: `started_at`, `traces`, `has_error?`, `source`.

Edge case — background jobs: `source: "job"` traces are excluded from web interaction
grouping by default. `[a]ll` mode shows them separately below web interactions.

---

## 10. Dependencies

### `gem 'e11y'` — no new dependencies

| Dep | Status | Note |
|-----|--------|------|
| Ruby 3.2+ | existing | |
| `Zlib` | stdlib | gzip compression on rotation |
| `json` | stdlib | fallback JSON parser |
| `oj` | **optional** | faster JSON (2–5×); loaded if present |

### `gem 'e11y-devtools'`

| Dep | Required? | Note |
|-----|-----------|------|
| `e11y` (same repo) | yes | core gem |
| `ratatui_ruby` ~> 1.4 | yes | TUI; pre-compiled binaries, no Rust toolchain needed |
| `mcp` ~> 1.0 | yes | MCP server; Anthropic + Shopify official SDK |
| `rb-kqueue` | optional | macOS file watching; polling fallback if absent |
| `rb-inotify` | optional | Linux file watching; polling fallback if absent |

---

## 11. Phased Delivery

| Phase | Scope | Key milestone |
|-------|-------|---------------|
| **P1** | DevLog Adapter (`FileStore` + `Query`) + Railtie | `tail -f log/e11y_dev.jsonl` works |
| **P2** | TUI (ratatui_ruby) + `exe/e11y` CLI | `bundle exec e11y` opens TUI |
| **P3** | Browser Overlay (Rails Engine) | Badge appears in dev app |
| **P4** | MCP Server | `bundle exec e11y mcp` works in Cursor |
| **P5** (future) | Rust JSONL scanner in devtools | Only if P1–P4 benchmarks show need |

---

## 12. Open Questions (deferred)

| Question | Decision |
|----------|----------|
| Rust JSONL scanner | Implement only after profiling shows bottleneck |
| `oj` as hard vs optional dependency | Optional with stdlib fallback (see §10) |
| `rb-kqueue` / `rb-inotify` | Optional; 250ms polling fallback is acceptable for dev |
| VS Code extension | Post-P4; JSONL format compatible with existing Log Viewer extensions |
| ActionCable live stream in Overlay | Post-P4; polling at 2s is sufficient for Phase 1 |

---

## 13. References

### Libraries
- [ratatui_ruby](https://www.ratatui-ruby.dev/) — TUI framework, Ruby + Rust
- [charm-ruby](https://github.com/charmbracelet) — considered, rejected (bubbletea-ruby: 10 commits)
- [gem 'mcp'](https://github.com/modelcontextprotocol/ruby-sdk) — official MCP Ruby SDK, Anthropic + Shopify
- [Sentry Spotlight](https://spotlightjs.com/) — Browser Overlay inspiration
- [rack-mini-profiler](https://github.com/MiniProfiler/rack-mini-profiler) — floating badge pattern

### Prior Art in E11y
- `docs/plans/2026-03-13-devlog-adapter-requirements.md` — superseded draft
- `docs/ADR-010-developer-experience.md` — DX requirements (§4.0)
- `lib/e11y/adapters/base.rb` — adapter contract
- `lib/e11y/railtie.rb` — Rails integration entry point
