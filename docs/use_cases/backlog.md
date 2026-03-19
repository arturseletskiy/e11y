# Backlog (Future Enhancements)

**Status:** Draft  
**Priority:** Low (v1.1+)  
**Category:** Future Ideas

---

## Overview

This document captures promising ideas for future versions of `e11y` that are not planned for v1.0 but may provide significant value in subsequent releases.

---

## Status: What's Already Done (as of v0.2.0)

| Backlog Item | Status | Notes |
|--------------|--------|-------|
| **§1 Sampling Budget** | ❌ Not done | |
| **§2 Global Async** | ❌ Not done | |
| **§3 Ring Buffer** | ⚠️ Implemented, not integrated | `E11y::Buffers::RingBuffer` exists; Loki uses `[]` + Mutex |
| **§4 Multi-Tenant** | ⚠️ Partial | Loki adapter has `tenant_id` (X-Scope-OrgID); baggage allows `tenant` key. No full multi-tenant isolation |

---

## 1. Sampling Budget

> **Related (implemented):** Adaptive sampling (error-spike, load-based), value-based (`sample_by_value`), per-event `sample_rate`. No budget/cap, no Redis state.

### Problem

Current sampling is reactive (based on load). Hard to predict costs. Organizations need predictable telemetry budgets.

### Proposal

Proactive budget-based sampling:

```ruby
E11y.configure do |config|
  config.cost_optimization do
    sampling_budget do
      enabled true
      
      # Set a daily event budget
      daily_budget 10_000_000  # 10M events/day
      
      # Budget allocation by event type
      allocate_by_pattern do
        pattern 'payment.*', percent: 20  # 2M events/day
        pattern 'order.*',   percent: 15  # 1.5M events/day
        pattern 'error.*',   percent: 10  # 1M events/day (always track)
        pattern 'debug.*',   percent: 5   # 500K events/day
        pattern '*',         percent: 50  # 5M events/day (everything else)
      end
      
      # Dynamic adjustment
      rebalance_interval 1.hour  # Recalculate sample rates every hour
      
      # Overflow strategy
      on_budget_exceeded :reduce_low_value  # or :stop_sampling, :alert_only
      
      # Alert when budget is 80% consumed
      alert_threshold 0.8
      alert_to :slack  # or :pagerduty, :email
    end
  end
end
```

### How It Works

#### 1. Budget Calculation

```ruby
# At start of each hour:
hourly_budget = daily_budget / 24  # 416,666 events/hour

# Per-pattern budget:
payment_budget = hourly_budget * 0.20  # 83,333 events/hour
```

#### 2. Dynamic Sample Rate Adjustment

```ruby
# If payment events are at 50% of budget after 30 min:
current_rate = 41,666 / (83,333 / 2)  # = 1.0 (100% sampling)

# If payment events are at 90% of budget after 30 min:
current_rate = 74,999 / (83,333 / 2)  # = 1.8 (need to reduce)
new_sample_rate = 1.0 / 1.8  # = 55% sampling for next 30 min
```

#### 3. Cost Predictability

```ruby
# Known daily cost:
cost_per_event = $0.0001  # e.g., Datadog pricing
daily_cost = 10_000_000 * $0.0001 = $1,000/day
monthly_cost = $1,000 * 30 = $30,000/month
```

### Benefits

- ✅ Predictable costs (no surprises)
- ✅ Budget enforcement (hard cap on events)
- ✅ Intelligent allocation (high-value events get more budget)
- ✅ Real-time alerts (before overspending)

### Trade-offs

- ⚠️ Complexity (requires Redis for distributed state)
- ⚠️ Potential data loss (if budget exceeded)
- ⚠️ Tuning required (optimal allocation per app)

### Priority

**Low (v1.2+)**

### Alternative Approach

- Use cloud cost management tools (AWS Cost Anomaly Detection, Datadog Cost Management)
- Set alerts on actual billing, not event counts
- Simpler, but less proactive

---

## 2. Global Async Mode and Queue

### Problem

Current pipeline is **synchronous**: `Event.track() → Pipeline → Routing → Adapter.write()`. Batching happens only inside individual adapters (Loki, OTel). There is no global async layer between `track()` and adapters.

The [01-SCALE-REQUIREMENTS.md](../prd/01-SCALE-REQUIREMENTS.md) document specifies a global async configuration that is **not implemented**:

```ruby
# Specified but NOT implemented
E11y.configure do |config|
  config.async do
    queue_size 10_000        # 10k events buffer
    batch_size 500           # Moderate batching
    flush_interval 200       # ms
    worker_threads 1         # Single worker
  end
end
```

### Missing Self-Monitoring Metrics

The scale requirements also specify metrics that are not wired:

- `E11y.stats.drops_total` — total dropped events
- `E11y.stats.events_processed_total` — total events processed
- `e11y_internal_queue_utilization_ratio` — buffer fill level (0–1)
- `e11y_internal_queue_size` / `e11y_internal_queue_capacity`

### Proposal

1. **Add global async config** — optional `config.async` block with `queue_size`, `batch_size`, `flush_interval`, `worker_threads`
2. **Use `RingBuffer`** — `E11y::Buffers::RingBuffer` exists but is unused; it could be the backing store for the global queue
3. **Worker thread(s)** — background consumer that pops from `RingBuffer` and writes to adapters in batches
4. **Self-monitoring** — expose `e11y_internal_*` metrics for queue health, drops, throughput

### Architecture Options

| Option | Description | Complexity |
|--------|-------------|------------|
| **A: Keep current** | Batching stays in adapters only | None |
| **B: Global queue** | Single RingBuffer before routing, worker threads | Medium |
| **C: Per-adapter queues** | Each adapter has its own RingBuffer + worker | High |

### Benefits

- ✅ Decouples `track()` from I/O (network, disk)
- ✅ Predictable latency under load (<1ms p99 for track)
- ✅ Backpressure handling (drop_oldest when full)
- ✅ Self-monitoring (queue utilization, drops)

### Trade-offs

- ⚠️ Complexity (thread management, shutdown)
- ⚠️ Data loss window (events in buffer on crash)
- ⚠️ Memory overhead (buffer capacity × avg event size)

### Priority

**Medium (v1.1)** — Required for small teams at scale; optional for MVP

---

## 3. In-Memory Ring Buffer (Integration)

### Problem

`E11y::Buffers::RingBuffer` is **fully implemented** (`lib/e11y/buffers/ring_buffer.rb`) but **not used** anywhere in the pipeline:

- **Loki adapter** uses `@buffer = []` + `Mutex` (not RingBuffer)
- **EphemeralBuffer** uses `Concurrent::Array` in `Thread.current`
- **RingBuffer** exists only in unit tests and benchmarks

PRD Phase 1 (00-ICP-AND-TIMELINE.md) specifies "In-memory ring buffer (SPSC)" as a Week 1–2 deliverable, but it was never integrated.

### RingBuffer Spec

- Lock-free SPSC (Single-Producer, Single-Consumer)
- 100K events capacity (default)
- Overflow strategies: `:drop_oldest`, `:drop_newest`, `:block`
- Target: 100K+ events/sec, <10μs p99 per push/pop

### Proposal

1. **Option A: Integrate into global async** — Use RingBuffer as the backing store when `config.async` is enabled (see §2)
2. **Option B: Replace Loki buffer** — Swap `[]` + Mutex for RingBuffer in Loki adapter for better throughput
3. **Option C: Remove from PRD** — Document that RingBuffer is "future-ready" for async mode; adapter-level batching is sufficient for MVP

### Recommendation

**Option A** — RingBuffer is the natural choice for global async queue. Integrate when implementing §2 (Global Async Mode).

### Priority

**Medium (v1.1)** — Depends on §2 (Global Async Mode)

---

## 4. Additional Ideas (Placeholder)

Future ideas to be added:

- **ML-Based Anomaly Detection:** Automatically detect unusual patterns in events
- **Event Replay from Storage:** Replay events from cold storage for debugging
- **Multi-Tenant Support:** Isolate events by tenant/customer — *Loki has `tenant_id`; baggage allows `tenant`*
- **Event Transformation Rules:** Transform events before sending to adapters — *routing + PII filter exist*
- **Custom Retention Policies:** More granular control over data lifecycle — *`retention_period` per event exists*

---

## Related Use Cases

- [UC-009: Cost Optimization](UC-015-cost-optimization.md) - Current cost optimization strategies
- [UC-014: Adaptive Sampling](UC-014-adaptive-sampling.md) - Current sampling approach

---

## Related ADRs

- [ADR-009: Cost Optimization](../architecture/ADR-009-cost-optimization.md) - Current implementation
- [ADR-001: Architecture](../architecture/ADR-001-architecture.md) - RingBuffer specification (§3.3.1)

## Related Documents

- [01-SCALE-REQUIREMENTS.md](../prd/01-SCALE-REQUIREMENTS.md) - Specifies `config.async`, self-monitoring metrics
- [00-ICP-AND-TIMELINE.md](../prd/00-ICP-AND-TIMELINE.md) - Phase 1 "In-memory ring buffer (SPSC)"

---

**Status:** ✅ Draft Complete  
**Next Review:** After v1.0 release  
**Estimated Value:** High (for enterprise customers)
