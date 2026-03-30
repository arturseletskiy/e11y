# Design: Unified DevLog Routing in Development

**Date:** 2026-03-30
**Issue:** arturseletskiy/e11y#23
**Status:** Approved

## Problem

`DevLog` adapter is auto-registered under the `:dev_log` key in development, but the default `adapter_mapping` routes events to `:logs` and `:errors_tracker` slots — which are `nil` by default. The routing middleware silently skips nil adapters (`next unless adapter`), so:

- Rails instrumentation events (`adapters: [:logs]`) → silently dropped
- Error events (`adapters: [:logs, :errors_tracker]`) → silently dropped
- Unrouted events → `fallback_adapters = [:stdout]` → terminal output only, not DevLog

Result: DevLog file is effectively empty out of the box, making TUI, Browser Overlay, and MCP useless without manual configuration.

## Solution: Slot Aliasing in Railtie (Approach A)

Alias the standard named slots to the DevLog instance at registration time, respecting user-defined values.

### Railtie Changes

Split the existing `e11y.setup_development` initializer into two independent initializers:

**`e11y.dev_log_adapter`** — registers the DevLog adapter and aliases slots. Development only.

```ruby
initializer "e11y.dev_log_adapter", after: :load_config_initializers do
  next unless Rails.env.development?
  next if E11y.configuration.adapters.key?(:dev_log)

  dev_log = E11y::Adapters::DevLog.new(
    path: Rails.root.join("log", "e11y_dev.jsonl"),
    max_lines: ENV.fetch("E11Y_MAX_EVENTS", "10000").to_i,
    max_size: ENV.fetch("E11Y_MAX_SIZE", "50").to_i * 1024 * 1024,
    keep_rotated: ENV.fetch("E11Y_KEEP_ROTATED", "5").to_i,
    enable_watcher: true
  )

  E11y.configure do |config|
    config.register_adapter :dev_log, dev_log
    config.adapters[:logs]           ||= dev_log  # don't override if user set it
    config.adapters[:errors_tracker] ||= dev_log  # don't override if user set it
    config.fallback_adapters = [:dev_log] if config.fallback_adapters == [:stdout]
  end
end
```

**`e11y.dev_log_middleware`** — inserts DevLogSource middleware. Always runs in development, regardless of whether `:dev_log` was user-provided.

```ruby
initializer "e11y.dev_log_middleware", after: :load_config_initializers do |app|
  next unless Rails.env.development?

  require "e11y/middleware/dev_log_source"
  app.middleware.use E11y::Middleware::DevLogSource
end
```

### What Changes vs. Current Behavior

| Scenario | Before | After |
|---|---|---|
| Rails instrumentation (`adapters: [:logs]`) | Silently dropped | Routes to DevLog |
| Error events (`adapters: [:logs, :errors_tracker]`) | Silently dropped | Routes to DevLog |
| Unrouted events | `stdout` | DevLog |
| User sets `config.adapters[:logs] = Loki.new(...)` | Same | Loki wins (`\|\|=`) |
| User provides own `:dev_log` | DevLogSource skipped (bug) | DevLogSource always inserted |
| Test environment | DevLog registered | No change (no aliasing) |

### Constraints

- `||=` semantics: user-explicitly-set adapters are never overridden
- `fallback_adapters` aliased only if still at default `[:stdout]`; user-modified values respected
- `adapter_mapping` not touched — slots remain named (`:logs`, `:errors_tracker`) for compatibility with routing rules and production config
- Test environment: no DevLog registration, no slot aliasing (unchanged)

## Testing Plan

### Integration tests (development env simulation)

1. Slots aliased — `config.adapters[:logs]` and `config.adapters[:errors_tracker]` point to same object as `:dev_log` after railtie init
2. Slots not overridden — if user set `config.adapters[:logs] = custom` before railtie, `||=` leaves it intact
3. Rails instrumentation event actually written to DevLog file — `E11y::Events::Rails::Log` with severity `:info` (`adapters: [:logs]`) appears in DevLog
4. Test env unaffected — `config.adapters[:logs]` remains `nil` in test environment
5. DevLogSource middleware inserted even when user provides custom `:dev_log`

### Unit tests

6. `fallback_adapters` set to `[:dev_log]` when default `[:stdout]`
7. `fallback_adapters` left unchanged when user already modified it
