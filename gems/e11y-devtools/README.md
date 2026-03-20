# e11y-devtools

Developer tools for [e11y](https://github.com/aseletskiy/e11y) — the Rails observability gem.

Three complementary viewers for the same JSONL log:

| Viewer | How to use |
|--------|-----------|
| **TUI** (terminal) | `bundle exec e11y` |
| **Browser Overlay** | Automatic in development — floating badge in bottom-right |
| **MCP Server** | `bundle exec e11y mcp` — AI integration for Cursor / Claude Code |

## Installation

Add to your Gemfile (development group only):

```ruby
# Gemfile
gem "e11y", "~> 1.0"
gem "e11y-devtools", "~> 0.1.0", group: :development
```

Then run `bundle install`.

## TUI — Interactive Log Viewer

```bash
bundle exec e11y           # Open TUI (default)
bundle exec e11y tui       # Same as above
bundle exec e11y tail      # Stream events to stdout
bundle exec e11y help      # Show help
```

### TUI Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `k` | Move up |
| `↓` / `j` | Move down |
| `Enter` | Drill in (interactions → events → detail) |
| `Esc` / `b` | Go back |
| `w` | Filter: web requests only |
| `j` | Filter: background jobs only |
| `a` | Filter: all sources |
| `r` | Reload manually |
| `c` | Copy event JSON to clipboard (in detail view) |
| `q` | Quit |

## Browser Overlay

When `gem "e11y-devtools"` is in your Gemfile, the overlay badge appears automatically in development. No configuration needed — the Railtie mounts it.

The badge shows:
- Total event count for the current request
- Error count (red badge when errors present)
- Click to expand the slide-in panel with full event list

## MCP Server — AI Integration

Start the server:

```bash
# stdio (for Cursor / Claude Code)
bundle exec e11y mcp

# HTTP (for direct integration)
bundle exec e11y mcp --port 3099
```

Add to `.cursor/mcp.json` or `~/.claude/mcp.json`:

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

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `recent_events` | Get latest N events (filterable by severity) |
| `events_by_trace` | Get all events for a trace ID |
| `search` | Full-text search across event names and payloads |
| `stats` | Aggregate statistics (total, by severity, oldest/newest) |
| `interactions` | Time-grouped interactions (parallel requests) |
| `event_detail` | Full payload for a single event by ID |
| `errors` | Recent error/fatal events only — fastest way to see what went wrong |
| `clear` | Clear the dev log |

## Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.register_adapter :dev_log, E11y::Adapters::DevLog.new(
    path:         Rails.root.join("log", "e11y_dev.jsonl"),
    max_size:     ENV.fetch("E11Y_MAX_SIZE", 50).to_i * 1024 * 1024,  # 50 MB
    max_lines:    ENV.fetch("E11Y_MAX_EVENTS", 10_000).to_i,
    keep_rotated: ENV.fetch("E11Y_KEEP_ROTATED", 5).to_i
  )
end
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `E11Y_MAX_EVENTS` | `10000` | Max lines before rotation |
| `E11Y_MAX_SIZE` | `50` | Max log size in MB before rotation |
| `E11Y_KEEP_ROTATED` | `5` | Number of compressed `.gz` files to keep |

## Log Format

Events are stored as JSONL (one JSON object per line) at `log/e11y_dev.jsonl`.
Rotated files are numbered and gzip-compressed: `e11y_dev.jsonl.1.gz`, `.2.gz`, etc.

## Architecture

```
log/e11y_dev.jsonl  ←  E11y::Adapters::DevLog (write)
         ↓
E11y::Adapters::DevLog::Query (read, cache, search, grouping)
         ↓
   ┌─────┴──────┬──────────────┬──────────────┐
   TUI          Browser        MCP Server
(ratatui_ruby)  Overlay       (gem 'mcp')
                (Rack)
```

The JSONL file is the single source of truth. All viewers are stateless readers — they never write.
