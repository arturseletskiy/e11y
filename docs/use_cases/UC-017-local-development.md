# UC-017: Local Development with e11y-devtools

**Status:** Implemented
**Complexity:** Beginner
**Setup Time:** 2 minutes
**Target Users:** All Rails Developers
**Related ADR:** ADR-010

---

## Overview

During local development, e11y automatically registers a **DevLog adapter** that writes all events to a local log file (default: `log/e11y_dev.jsonl`). No configuration is required — the Railtie activates the adapter in `development` and `test` environments on startup.

Three complementary interfaces let you inspect those events:

| Interface | How to access | Best for |
|-----------|--------------|----------|
| TUI (terminal) | `bundle exec e11y` | Browsing interactions, drilling into traces |
| Browser Overlay | Included with `e11y-devtools` gem | Checking events for the page you just loaded |
| MCP Server | `bundle exec e11y mcp` | AI-assisted debugging in Cursor / Claude Code |

**Debug buffer note:** debug-severity events are held in memory during a request and flushed to the DevLog only when the request fails. A successful request discards the debug buffer, keeping the log free of noise. Error events always write immediately.

---

## Setup

Add the devtools gem to your `Gemfile`:

```ruby
# Gemfile
group :development, :test do
  gem "e11y-devtools"
end
```

Run `bundle install`. That is all — no `config/environments/development.rb` changes needed.

The Railtie auto-registers the DevLog adapter and respects three ENV vars:

```bash
bundle exec rails server
# DevLog active: log/e11y_dev.jsonl (max 10 000 events, 50 MB)
```

---

## TUI — Interactive Log Viewer

Launch the terminal UI from your project root:

```bash
bundle exec e11y
```

### Views

The TUI has three nested views. Navigation is always the same two keys: Enter to drill in, Esc or `b` to go back.

```
:interactions  →  :events  →  :detail
```

### Interactions view (default)

Parallel traces that start within 500 ms are grouped into one row. A red dot (●) means the interaction contains at least one error; a gray dot (○) means it is clean.

```
e11y  [w] web  [j] jobs  [a] all                    r=reload  q=quit
────────────────────────────────────────────────────────────────────
  #   time      source   dur     events  status
────────────────────────────────────────────────────────────────────
  1   10:04:12  web      312ms      14   ○  GET /orders
  2   10:03:58  web       89ms       6   ○  GET /orders/123
  3   10:03:41  web      541ms      22   ●  POST /checkout
  4   10:02:15  jobs      2.1s       8   ○  OrderFulfillmentJob
  5   10:01:07  web       73ms       3   ○  GET /products
────────────────────────────────────────────────────────────────────
↓/↑ navigate   Enter drill-in
```

### Events view (after Enter on an interaction)

```
e11y  >  POST /checkout  (trace: f3a9b2c1)
────────────────────────────────────────────────────────────────────
  #   time      severity  event name
────────────────────────────────────────────────────────────────────
  1   10:03:41  info      order.validation.started
  2   10:03:41  info      inventory.checked
  3   10:03:41  debug     db.query  (buffered — shown because request failed)
  4   10:03:42  warn      payment.retry
  5   10:03:42  error     payment.failed
────────────────────────────────────────────────────────────────────
↓/↑ navigate   Enter detail   Esc/b back
```

### Detail view (after Enter on an event)

```
e11y  >  POST /checkout  >  payment.failed
────────────────────────────────────────────────────────────────────
event_name:   payment.failed
severity:     error
timestamp:    2026-03-18T10:03:42.317Z
trace_id:     f3a9b2c1-...
duration_ms:  541

payload:
  order_id:   "ord_8812"
  amount:     99.99
  currency:   "USD"
  reason:     "Card declined"
  attempt:    2
────────────────────────────────────────────────────────────────────
Esc/b back   c=copy JSON
```

### Keyboard reference

| Key | Action |
|-----|--------|
| `↓` / `↑` | Navigate list |
| `Enter` | Drill into interaction or event |
| `Esc` / `b` | Go back one level |
| `w` | Filter: web requests only (default) |
| `j` | Filter: background jobs only |
| `a` | Filter: all sources |
| `r` | Reload from log file |
| `c` | Copy event JSON to clipboard (detail view) |
| `q` | Quit |

File watching polls `mtime` every 250 ms — new events appear without pressing `r`.

---

## Browser Overlay

When `e11y-devtools` is present in the Gemfile, a lightweight JavaScript snippet is injected into every development page response. It requires no route configuration.

### Badge

A small badge appears in the bottom-right corner of every page:

```
╭─────────────╮
│  e11y  14 ● 1│
╰─────────────╯
```

- The first number is the total event count for the current page's trace.
- The second number (after ●) is the error count.
- The badge border turns red when errors are present.

### Slide-in panel

Clicking the badge opens a panel on the right side of the screen:

```
╔══════════════════════════════════════════╗
║  e11y — trace: f3a9b2c1                  ║
╠══════════════════════════════════════════╣
║  10:03:41  info   order.validation.start ║
║  10:03:41  info   inventory.checked      ║
║  10:03:42  warn   payment.retry          ║
║  10:03:42  error  payment.failed         ║
╠══════════════════════════════════════════╣
║  [clear log]          [copy trace_id]    ║
╚══════════════════════════════════════════╝
```

The panel shows only events that share the current page's trace ID. It auto-polls every 2 seconds.

The overlay endpoint returns 404 outside the `development` environment, so it cannot leak into staging or production.

---

## MCP Server — AI-Assisted Debugging

The MCP server exposes the DevLog over the Model Context Protocol so AI assistants can query your local events directly.

### Start the server

```bash
# Default port 3099
bundle exec e11y mcp

# Custom port
bundle exec e11y mcp --port 3099
```

### Available tools

| Tool | Description |
|------|-------------|
| `recent_events` | Return the N most recent events (default 50) |
| `events_by_trace` | Return all events for a given `trace_id` |
| `search` | Full-text search across event names and payload fields |
| `stats` | Event counts by severity and source for a time window |
| `interactions` | List grouped interactions (same view as TUI :interactions) |
| `event_detail` | Return full JSON for a single event by ID |
| `errors` | Return all error/fatal events since a given timestamp |
| `clear` | Truncate the DevLog (useful before reproducing a bug) |

### Cursor configuration

Create or update `.cursor/mcp.json` in your project root:

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

### Claude Code configuration

Create or update `.claude/mcp.json` in your project root:

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

### Example prompts

- "What errors happened in the last request?"
- "Show me all events for trace f3a9b2c1"
- "Why is the checkout slow? Look at recent interactions."
- "Compare event counts from the last two POST /checkout traces."

---

## Configuration Reference

All settings are controlled via ENV vars. No code changes are needed for the defaults.

| ENV var | Default | Description |
|---------|---------|-------------|
| `E11Y_MAX_EVENTS` | `10000` | Maximum number of events retained in the DevLog (oldest are dropped) |
| `E11Y_MAX_SIZE` | `52428800` (50 MB) | Maximum DevLog file size in bytes before rotation |
| `E11Y_KEEP_ROTATED` | `5` | Number of rotated log files to retain |

Example: raise the cap for a long debugging session:

```bash
E11Y_MAX_EVENTS=50000 bundle exec rails server
```

The DevLog file is written to `log/e11y_dev.jsonl` by default. Add it to `.gitignore`:

```
# .gitignore
log/e11y_dev*.log
```

---

## Acceptance Criteria

- [x] Railtie auto-registers DevLog adapter in `development` and `test` — no manual configuration required
- [x] DevLog respects `E11Y_MAX_EVENTS`, `E11Y_MAX_SIZE`, and `E11Y_KEEP_ROTATED` ENV vars
- [x] TUI launches with `bundle exec e11y` and shows the `:interactions` view by default
- [x] Interactions group parallel traces within a 500 ms window into a single row
- [x] Red dot (●) on interactions that contain at least one error; gray dot (○) otherwise
- [x] Source filter toggles: web requests (`w`), background jobs (`j`), all (`a`)
- [x] TUI supports drill-down: `:interactions` → `:events` → `:detail`
- [x] Detail view provides `c` to copy event JSON to clipboard
- [x] TUI polls log `mtime` every 250 ms and refreshes automatically
- [x] Browser overlay badge appears in bottom-right corner with event count and error count
- [x] Badge border turns red when the current trace contains errors
- [x] Panel shows only events for the current page's trace ID
- [x] Panel auto-polls every 2 seconds
- [x] Browser overlay endpoint returns 404 outside `development`
- [x] MCP server starts with `bundle exec e11y mcp` (default port 3099)
- [x] MCP server exposes 8 tools: `recent_events`, `events_by_trace`, `search`, `stats`, `interactions`, `event_detail`, `errors`, `clear`
- [x] Cursor and Claude Code JSON configs work with `command: "bundle", args: ["exec", "e11y", "mcp"]`
- [x] Debug events are buffered per-request and flushed to DevLog only on request failure

---

**Related:** [ADR-010: Developer Experience](../ADR-010-developer-experience.md) | [UC-018: Testing Events](./UC-018-testing-events.md)
