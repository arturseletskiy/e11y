# UC-017: Local Development

**Status:** MVP Feature  
**Complexity:** Beginner  
**Setup Time:** 5-10 minutes  
**Target Users:** All Developers

---

## 📋 Overview

### Problem Statement

**The local development pain:**
```ruby
# ❌ BEFORE: Poor development experience
# - Events go to production backends (Loki, Sentry)
# - Can't see events in console (hidden in logs)
# - No colored output (hard to read)
# - No pretty-printing (JSON blobs)
# - Debug events flood console
# - Can't easily filter what you see

# Terminal output:
# {"event":"order.created","order_id":"123","timestamp":"2026-01-12T10:00:00Z"}
# {"event":"payment.processing","order_id":"123","timestamp":"2026-01-12T10:00:01Z"}
# {"event":"debug.sql","query":"SELECT...","timestamp":"2026-01-12T10:00:02Z"}
# → Hard to read! 😞
```

### E11y Solution

**Developer-friendly local setup:**
```ruby
# ✅ AFTER: Beautiful, readable output
E11y.configure do |config|
  if Rails.env.development?
    # Beautiful colored console output
    config.adapters = [
      E11y::Adapters::ConsoleAdapter.new(
        colored: true,
        pretty: true,
        show_payload: true,
        show_context: true
      )
    ]
    
    # Show all severities (including debug)
    config.severity = :debug
    
    # No rate limiting in dev
    config.rate_limiting.enabled = false
  end
end

# Terminal output (beautiful! 🎨):
# ╭─────────────────────────────────────────────────────────╮
# │ 🎉 order.created                     [SUCCESS] 10:00:00 │
# ├─────────────────────────────────────────────────────────┤
# │ order_id: 123                                           │
# │ user_id: 456                                            │
# │ amount: $99.99                                          │
# │ trace_id: abc-123-def                                   │
# ╰─────────────────────────────────────────────────────────╯
```

---

## 🎯 Features

> **Implementation:** See [ADR-010: Developer Experience](../ADR-010-developer-experience.md) for complete architecture, including [Section 3: Console Output](../ADR-010-developer-experience.md#3-console-output), [Section 4: Web UI](../ADR-010-developer-experience.md#4-web-ui), [Section 5: Event Registry](../ADR-010-developer-experience.md#5-event-registry), and [Section 6: Debug Helpers](../ADR-010-developer-experience.md#6-debug-helpers).

### 1. Console Adapter (Pretty Output)

**Beautiful colored terminal output:**
```ruby
# config/environments/development.rb
Rails.application.configure do
  config.after_initialize do
    E11y.configure do |config|
      config.adapters = [
        E11y::Adapters::ConsoleAdapter.new(
          # Colors
          colored: true,
          color_scheme: :solarized,  # :default, :solarized, :monokai
          
          # Formatting
          pretty: true,
          compact: false,
          
          # What to show
          show_payload: true,
          show_context: true,
          show_metadata: false,  # timestamps, etc.
          show_trace_id: true,
          
          # Filtering
          severity_filter: :debug,  # Show all
          event_filter: nil,  # Show all events
          
          # Grouping
          group_by_trace_id: true,  # Group events with same trace_id
          
          # Performance
          max_payload_length: 1000,  # Truncate long payloads
          max_array_items: 10  # Limit array display
        )
      ]
    end
  end
end

# Output examples:
# ✅ SUCCESS event (green)
# 🎉 order.created [SUCCESS] 10:00:00
#    order_id: 123
#    amount: $99.99
#    ⚡ Duration: 45ms

# ⚠️  WARN event (yellow)
# ⚠️  payment.retry [WARN] 10:00:05
#    order_id: 123
#    attempt: 2
#    reason: "Card declined"

# ❌ ERROR event (red)
# ❌ payment.failed [ERROR] 10:00:10
#    order_id: 123
#    error: "Insufficient funds"
#    trace_id: abc-123-def
```

---

### 2. Event Inspector (Interactive)

**Interactive console for exploring events:**
```ruby
# rails console
> E11y::Inspector.start
E11y Inspector started. Type 'help' for commands.

# Watch events in real-time
e11y> watch
Watching events... (Ctrl+C to stop)
[10:00:00] order.created { order_id: 123 }
[10:00:01] payment.processing { order_id: 123 }
[10:00:02] payment.succeeded { transaction_id: 'tx_123' }

# Filter by pattern
e11y> watch pattern: 'order.*'
Watching events matching 'order.*'...
[10:00:00] order.created { order_id: 123 }
[10:00:05] order.shipped { order_id: 123, tracking: 'TRACK123' }

# Filter by severity
e11y> watch severity: :error
Watching ERROR events...
[10:00:10] payment.failed { error: "Card declined" }

# Show last N events
e11y> last 10
Showing last 10 events:
1. [10:00:00] order.created
2. [10:00:01] payment.processing
3. [10:00:02] payment.succeeded
...

# Search events
e11y> search order_id: '123'
Found 5 events:
1. [10:00:00] order.created
2. [10:00:01] payment.processing
3. [10:00:02] payment.succeeded
4. [10:00:05] order.shipped
5. [10:00:10] order.delivered

# Show event details
e11y> show 1
Event: order.created
Severity: SUCCESS
Timestamp: 2026-01-12 10:00:00
Trace ID: abc-123-def
Payload:
  order_id: 123
  user_id: 456
  amount: 99.99
  currency: USD
Context:
  request_id: req-789
  user_agent: Mozilla/5.0...
Duration: 45ms
```

---

### 3. Debug Helper

**Quick debugging methods:**
```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    # Quick debug (only in development!)
    E11y.debug("Creating order", order_params)
    # → Pretty-printed to console immediately
    
    order = Order.create!(order_params)
    
    # Breakpoint with context
    E11y.breakpoint(
      "Order created",
      order: order.attributes,
      user: current_user.attributes
    )
    # → Pauses execution, shows data, waits for Enter
    
    # Measure block
    result = E11y.measure("Payment processing") do
      process_payment(order)
    end
    # → Logs duration automatically
    
    render json: order
  end
end

# Console output:
# 🔍 [DEBUG] Creating order
#    user_id: 456
#    items: [...]
#    total: 99.99
#
# ⏸️  [BREAKPOINT] Order created
#    order: { id: 123, status: "pending", ... }
#    user: { id: 456, email: "user@example.com", ... }
#    Press Enter to continue...
#
# ⏱️  [MEASURE] Payment processing → 1.2s
```

---

### 4. Event Recorder (Playback)

**Record and replay events for testing:**
```ruby
# Record events during a request
# rails console
> recorder = E11y::Recorder.new
> recorder.start
Recording events...

# Make request
> app.post '/orders', params: { order: {...} }

> recorder.stop
Recorded 15 events
Saved to tmp/e11y_recordings/2026-01-12_10-00-00.json

# Replay events
> recorder.replay('tmp/e11y_recordings/2026-01-12_10-00-00.json')
Replaying 15 events...
[1/15] order.creation.started
[2/15] inventory.checked
[3/15] payment.processing
...
[15/15] order.created

# Compare recordings (regression testing)
> diff = E11y::Recorder.diff(
    'recordings/baseline.json',
    'recordings/current.json'
  )
> puts diff
+ payment.retry (NEW in current)
- payment.succeeded (MISSING in current)
~ payment.processing.duration_ms: 120ms → 1500ms (12.5x slower!)
```

---

### 5. Visual Timeline (Web UI)

**Mini web UI for development:**
```ruby
# config/routes.rb (development only)
Rails.application.routes.draw do
  if Rails.env.development?
    mount E11y::Web => '/e11y'
  end
end

# Visit: http://localhost:3000/e11y
# Features:
# - Real-time event stream
# - Timeline view (Gantt chart)
# - Filtering by severity, pattern
# - Trace visualization
# - Event details modal
# - Export to JSON/CSV
# - Search & filter

# Example UI:
# ╔══════════════════════════════════════════════════════════╗
# ║ E11y Event Dashboard                    🔄 Auto-refresh ║
# ╠══════════════════════════════════════════════════════════╣
# ║ Filters: [All Severities ▾] [All Events ▾] [Search...] ║
# ╠══════════════════════════════════════════════════════════╣
# ║ Timeline (Last 5 minutes)                                ║
# ║ ┌────────────────────────────────────────────────────┐ ║
# ║ │ 10:00:00 ████ order.created                        │ ║
# ║ │ 10:00:01   ███████ payment.processing              │ ║
# ║ │ 10:00:02          ██ payment.succeeded             │ ║
# ║ │ 10:00:05             ████ shipment.created         │ ║
# ║ └────────────────────────────────────────────────────┘ ║
# ╠══════════════════════════════════════════════════════════╣
# ║ Recent Events                                            ║
# ║ ✅ order.created      10:00:00  trace: abc-123          ║
# ║ ⏳ payment.processing 10:00:01  trace: abc-123          ║
# ║ ✅ payment.succeeded  10:00:02  trace: abc-123          ║
# ╚══════════════════════════════════════════════════════════╝
```

---

## 💻 Implementation Examples

### Example 1: Full Development Config

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.after_initialize do
    E11y.configure do |config|
      # === CONSOLE OUTPUT ===
      config.adapters = [
        E11y::Adapters::ConsoleAdapter.new(
          colored: true,
          pretty: true,
          show_payload: true,
          show_context: true,
          show_trace_id: true,
          group_by_trace_id: true
        )
      ]
      
      # === SEVERITY ===
      # Show everything in development
      config.severity = :debug
      
      # === FEATURES ===
      # Disable production features
      config.rate_limiting.enabled = false
      config.sampling.enabled = false
      config.pii_filtering.enabled = false  # Easier debugging
      
      # === DEBUGGING ===
      # Enable debug helpers
      config.debug_mode = true
      
      # === BUFFERING ===
      # Immediate flush (no buffering)
      config.buffer.enabled = false  # Or flush_interval: 0.1.seconds
      
      # === WEB UI ===
      config.web_ui do
        enabled true
        port 3001  # Or use Rails server
        auto_refresh true
        refresh_interval 2.seconds
      end
      
      # === RECORDING ===
      config.recording do
        enabled true
        save_path Rails.root.join('tmp', 'e11y_recordings')
        auto_save_on_error true
      end
      
      # === PERFORMANCE ===
      # Verbose self-monitoring
      config.self_monitoring do
        enabled true
        log_internal_events true
      end
    end
  end
end
```

---

### Example 2: Debug Helpers in Code

```ruby
# app/services/order_processing_service.rb
class OrderProcessingService
  def call(order_id)
    # Debug checkpoint
    E11y.debug("Starting order processing", order_id: order_id)
    
    order = Order.find(order_id)
    
    # Show complex data structure
    E11y.inspect(order, depth: 2)
    # → Pretty-printed with colors, max depth 2
    
    # Measure performance
    inventory_result = E11y.measure("Inventory check") do
      check_inventory(order)
    end
    
    # Conditional breakpoint
    E11y.breakpoint_if(
      -> { inventory_result.low_stock? },
      "Low stock detected!",
      order: order.attributes,
      inventory: inventory_result
    )
    
    # Trace execution
    E11y.trace("Processing payment") do
      process_payment(order)
    end
    # → Logs entry/exit automatically
    
    # Count invocations
    E11y.count("order_processing")
    # → Logs: "order_processing called 5 times"
    
    # Diff objects
    before = order.attributes
    order.update!(status: 'processed')
    E11y.diff(before, order.attributes)
    # → Shows: { status: "pending" → "processed" }
    
    order
  end
end

# Console output:
# 🔍 [DEBUG] Starting order processing
#    order_id: 123
#
# 📦 [INSPECT] Order #123
#    id: 123
#    status: "pending"
#    items: [
#      { id: 1, product_id: 456, quantity: 2 },
#      { id: 2, product_id: 789, quantity: 1 }
#    ]
#    total: 99.99
#
# ⏱️  [MEASURE] Inventory check → 45ms
#
# ⏸️  [BREAKPOINT] Low stock detected!
#    order: { ... }
#    inventory: { low_stock: true, product_id: 456 }
#    Press Enter to continue...
#
# 🔀 [TRACE] Processing payment
#    → Entered at 10:00:01
#    → Exited at 10:00:02 (1.2s)
#
# 📊 [COUNT] order_processing called 5 times
#
# 🔄 [DIFF] Order #123
#    - status: "pending"
#    + status: "processed"
```

---

### Example 3: Event Filtering

```ruby
# config/environments/development.rb
E11y.configure do |config|
  config.adapters = [
    E11y::Adapters::ConsoleAdapter.new(
      colored: true,
      pretty: true,
      
      # === FILTERING ===
      # Only show events matching patterns
      event_filter: ->(event) {
        # Show orders & payments, hide everything else
        event.event_name.match?(/^(order|payment)\./)
      },
      
      # Only show warn/error/success
      severity_filter: [:warn, :error, :fatal, :success],
      
      # Hide noisy events
      ignore_events: [
        'health_check',
        'heartbeat',
        'metrics.collected'
      ],
      
      # Hide debug SQL queries
      ignore_patterns: [
        /^debug\./,
        /\.sql$/
      ]
    )
  ]
end

# Result:
# ✅ Shows: order.created, payment.succeeded
# ❌ Hides: debug.sql, health_check, heartbeat
```

---

## 🔧 Configuration

### Development Config Template

```ruby
# config/environments/development.rb
Rails.application.configure do
  config.after_initialize do
    E11y.configure do |config|
      # === OUTPUT ===
      config.adapters = [
        E11y::Adapters::ConsoleAdapter.new(
          colored: true,
          pretty: true,
          color_scheme: :solarized,
          show_payload: true,
          show_context: true,
          show_trace_id: true,
          group_by_trace_id: true,
          max_payload_length: 1000
        )
      ]
      
      # === LEVEL ===
      config.severity = :debug
      
      # === FEATURES ===
      config.rate_limiting.enabled = false
      config.sampling.enabled = false
      config.buffering.enabled = false
      
      # === DEBUG ===
      config.debug_mode = true
      config.debug_helpers.enabled = true
      
      # === WEB UI ===
      config.web_ui.enabled = true
      config.web_ui.auto_refresh = true
      
      # === RECORDING ===
      config.recording.enabled = true
      config.recording.auto_save_on_error = true
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use colored console output**
```ruby
# ✅ GOOD: Easy to read
config.adapters = [
  E11y::Adapters::ConsoleAdapter.new(
    colored: true,
    pretty: true
  )
]
```

**2. Filter noise in development**
```ruby
# ✅ GOOD: Hide irrelevant events
config.adapters = [
  E11y::Adapters::ConsoleAdapter.new(
    ignore_events: ['health_check', 'heartbeat']
  )
]
```

**3. Use debug helpers**
```ruby
# ✅ GOOD: Quick debugging
E11y.debug("User logged in", user_id: user.id)
E11y.breakpoint("Check this", data: complex_data)
```

---

### ❌ DON'T

**1. Don't use production adapters**
```ruby
# ❌ BAD: Production adapters in development
config.adapters = [
  E11y::Adapters::LokiAdapter.new(...)  # Slow!
]

# ✅ GOOD: Console adapter
config.adapters = [
  E11y::Adapters::ConsoleAdapter.new(...)
]
```

**2. Don't forget to disable features**
```ruby
# ❌ BAD: Production features enabled
config.rate_limiting.enabled = true  # Annoying in dev!
config.sampling.enabled = true       # Lose events!

# ✅ GOOD: Disable in development
config.rate_limiting.enabled = false
config.sampling.enabled = false
```

---

## 📚 Related Use Cases

- **[UC-016: Rails Logger Migration](./UC-016-rails-logger-migration.md)** - Migration guide
- **[UC-018: Testing Events](./UC-018-testing-events.md)** - Testing helpers

---

## 🎯 Summary

### Development Experience

| Feature | Before | After |
|---------|--------|-------|
| **Output** | JSON blobs | Colored, pretty |
| **Filtering** | None | By severity, pattern |
| **Debugging** | `puts` | Debug helpers |
| **Inspection** | Manual | Interactive inspector |
| **Recording** | None | Record & replay |
| **Visualization** | None | Web UI |

**Setup Time:** 5-10 minutes (one-time config)

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete
