# UC-002: Business Event Tracking - Summary

**Document:** UC-002  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Core

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Medium |
| **Dependencies** | ADR-001 (Extension Points, Performance), UC-001, UC-003, UC-007 |
| **Contradictions** | 2 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Unstructured Rails.logger logs are hard to parse/query, manual metrics tracking creates duplication/bugs, no schema causes typos/inconsistencies, no type safety causes runtime errors.

**Who is affected?**
Ruby/Rails Developers

**Expected outcome:**
Structured events with schema validation, event metrics, adapter routing (global registry + per-event override), performance SLOs (<1ms p99, <100MB memory, 1000 events/sec).

---

## 📝 Key Requirements (Configuration Patterns for Simplification)

### Must Have (Critical)
- [x] **Event-Level DSL (Class-Level Configuration):**
  - `schema(&block)` - Dry::Schema validation (required/optional fields, types)
  - `severity(symbol)` - Default severity (:debug, :info, :success, :warn, :error, :fatal)
  - `adapters(array)` - Override global adapters (reference by name: `:loki`, `:sentry`)
  - `version(integer)` - Event version (for schema evolution)
- [x] **Global Adapter Registry (DRY Configuration):**
  - `config.register_adapter(name, instance)` - Register once, reference by name everywhere
  - `config.default_adapters = [:loki, :file]` - Default for all events (unless overridden)
  - Adapters created once with connections (no duplication, connection reuse)
- [x] **Adapter Reference by Name (Not Instance):**
  - Events use `:loki`, `:sentry` (symbols), NOT `E11y::Adapters::LokiAdapter.new(...)`
  - Prevents duplication, enables DRY principle
- [x] **Adapters_Strategy:** `:append` or `:replace`
  - `:append` - Add to default_adapters (inherit + extend)
  - `:replace` - Replace default_adapters entirely (override)
- [x] **Environment-Specific Adapter Routing:**
  - Production: `[:loki, :s3_archive]`
  - Staging: `[:loki]`
  - Development: `[:console]` (colorized output)
  - Test: `[:memory]` (in-memory adapter for testing)
- [x] **Custom Middleware Extension Points:**
  - Extend pipeline with custom middleware (tenant isolation, A/B test tracking, custom rate limiting)
  - Order matters (see ADR-015: enrichment → validation → security → business logic → routing)

### Should Have (Important)
- [x] Event naming conventions (`<entity>.<past_tense_verb>`)
- [x] Duration measurement (block syntax: `Events::PaymentProcessed.track(...) do ... end`)
- [x] In-memory test adapter (for unit testing without external services)
- [x] Self-monitoring (E11y tracks its own performance: latency, memory, throughput)
- [x] Performance SLOs (p99 <1ms, memory <100MB, throughput 1000 events/sec)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-001:** Request-Scoped Debug Buffering (debug vs. business events)
- **UC-003:** Pattern-Based Metrics (auto-generate metrics)
- **UC-007:** PII Filtering (secure event data)

### Related ADRs
- **ADR-001 Section 7:** Extension Points (custom middleware architecture)
- **ADR-001 Section 8:** Performance Requirements (SLOs: <1ms p99, <100MB memory)

---

## ⚡ Technical Constraints

### Performance SLOs (CRITICAL)
| Metric | Target | Critical? |
|--------|--------|-----------|
| **Event Track Latency (p99)** | <1ms | ✅ Critical |
| **Memory @ Steady State** | <100MB | ✅ Critical |
| **Sustained Throughput** | 1000 events/sec | ✅ Critical |
| **Burst Throughput** | 5000 events/sec (5s) | ⚠️ Important |
| **CPU @ 1000 evt/s** | <5% | ⚠️ Important |

---

## 🎭 User Story

**As a** Rails Developer  
**I want** structured event tracking with automatic metrics and flexible adapter routing  
**So that** I avoid Rails.logger unstructured logs, eliminate manual metrics duplication, and get schema validation + type safety

**Rationale:**
Traditional Rails.logger approach:
- ❌ Free-form text → hard to parse/query
- ❌ Manual metrics → boilerplate + duplication + bugs
- ❌ No schema → typos, inconsistencies
- ❌ No type safety → runtime errors

E11y solves this with:
- ✅ Structured events (JSON) → queryable
- ✅ Event metrics → zero duplication
- ✅ Schema validation (Dry::Schema) → catch typos at boot time
- ✅ Type safety → fail fast

**Trade-offs:**
- ✅ **Pros:** Structured, queryable, auto-metrics, schema validation, adapter flexibility (per-event override)
- ❌ **Cons:** More verbose (schema definition), learning curve (Dry::Schema syntax), global registry requires discipline (register once, reference everywhere)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Global Adapter Registry (DRY) vs. Per-Event Configuration Flexibility
**Conflict:** Global adapter registry (configure once, reference by name) encourages DRY BUT reduces flexibility for per-event custom adapter configuration (e.g., different batch_size for different events)
**Impact:** Medium (DRY vs. flexibility)
**Related to:** ADR-004 (Adapter Architecture - Contradiction #1)
**Notes:** Lines 452-483 show global adapter registry:
- Register adapters once: `config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(url: ...)`
- Reference by name in events: `adapters [:loki]` (symbol, not instance)
- Benefit: DRY (configure once, reuse everywhere)
- Limitation: All events using `:loki` share SAME Loki instance (same batch_size, same timeout)

**Real Evidence:**
```
Lines 452-482: "Step 1: Define adapters in global config (one place!):
config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(
  url: ENV['LOKI_URL']
)

Step 2: Reference adapters by name in events:
class CriticalError < E11y::Event::Base
  adapters [:sentry]  # Reference by name!
end"

Lines 1152-1165: "❌ Bad: Creating adapter instances (defeats the purpose!)
class MyEvent < E11y::Event::Base
  adapters [
    E11y::Adapters::LokiAdapter.new(url: ...)  # ← NO!
  ]
end

✅ Good: Reference by name (adapters created once in config)
class MyEvent < E11y::Event::Base
  adapters [:loki]  # ← YES!
end"
```

**Problem:** If Event A needs Loki with `batch_size: 100` and Event B needs Loki with `batch_size: 10`, they CANNOT use different configs. They must use the SAME `:loki` instance.

**Workaround:** Register multiple Loki instances (`:loki_fast`, `:loki_slow`), but this defeats DRY principle and creates configuration duplication.

**This is the SAME contradiction identified in ADR-004 summary (Contradiction #1).**

### Contradiction 2: Adapter Override Per Event (Flexibility) vs. Default Adapters (DRY)
**Conflict:** Per-event adapter override (`adapters [:loki, :sentry]`) provides flexibility BUT encourages duplication if many events override to same adapters
**Impact:** Low (acceptable trade-off)
**Related to:** ADR-004 (Adapter Architecture)
**Notes:** Lines 1126-1150 show anti-pattern (repetitive adapter references) vs. best practice (use default_adapters):
- ❌ Bad: Every event declares `adapters [:loki]` (duplication)
- ✅ Good: `config.default_adapters = [:loki]` (global), only override when needed

**Real Evidence:**
```
Lines 1126-1150: "❌ Bad: Repetitive adapter references
class OrderCreated < E11y::Event::Base
  adapters [:loki]  # Same as default!
end

class OrderPaid < E11y::Event::Base
  adapters [:loki]  # Duplication!
end

✅ Good: Use default_adapters, override only when needed
config.default_adapters = [:loki]

# Most events just use defaults (no adapters line needed!)
class OrderCreated < E11y::Event::Base
  # Uses default_adapters automatically ✅
end

# Override only for special cases
class CriticalError < E11y::Event::Base
  adapters [:sentry]  # Different from default!
end"
```

**Trade-off:** This is actually GOOD design (encouraging DRY via defaults). Flexibility is still available (per-event override), but discouraged for common cases.

**Guidance:** Document encourages default_adapters for 90% of events, override only for special cases (e.g., critical errors to Sentry, debug events to file_only).

---

## 📊 Complexity Assessment

**Overall Complexity:** Medium

**Reasoning:**
- Event-level DSL is simple (schema, severity, adapters, version - 4 main fields)
- Global adapter registry reduces configuration (register once, reference everywhere)
- Pattern-based auto-metrics eliminate manual metrics duplication
- Custom middleware requires understanding of pipeline order (ADR-015)
- Environment-specific routing adds conditional logic (case Rails.env)

**Estimated Implementation Time:**
- Junior dev: 5-8 days (event DSL, adapter registry, event metrics, testing)
- Senior dev: 3-5 days (familiar with Rails, Dry::Schema)

---

## 📚 References

### Related Documentation
- [UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)
- [UC-003: Event Metrics](../../../../use_cases/UC-003-event-metrics.md)
- [UC-007: PII Filtering](./UC-007-pii-filtering.md)
- [ADR-001 Section 7: Extension Points](../ADR-001-architecture.md#7-extension-points)
- [ADR-001 Section 8: Performance Requirements](../ADR-001-architecture.md#8-performance-requirements)

### Research Notes
- **Event-level DSL fields (key for simplification):**
  - schema (Dry::Schema)
  - severity (symbol)
  - adapters (array of symbols - reference by name!)
  - version (integer)
  - adapters_strategy (`:append` or `:replace`)
- **Performance SLOs:**
  - p99 track latency: <1ms
  - Memory @ steady state: <100MB
  - Throughput: 1000 events/sec sustained, 5000 burst
- **Adapter routing patterns:**
  - Global registry (DRY): register once, reference by name
  - Per-event override: `adapters [:sentry]` (special cases only!)
  - Environment-specific: production (loki, s3), dev (console), test (memory)

---

## 🏷️ Tags

`#critical` `#core` `#event-dsl` `#schema-validation` `#adapter-routing` `#global-registry`  `#performance-slos`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3 - Consolidated Analysis)
