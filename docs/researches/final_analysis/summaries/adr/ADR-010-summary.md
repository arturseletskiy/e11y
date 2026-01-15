# ADR-010: Developer Experience - Summary

**Document:** ADR-010  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Developer Experience

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Medium |
| **Dependencies** | ADR-001, ADR-011 (Testing), ADR-012 (Event Evolution), UC-017, UC-022 |
| **Contradictions** | 3 identified |

---

## 🎯 Decision Statement

**Decision:** E11y provides **file-based JSONL dev_log adapter** (multi-process safe, zero deps, persistent), **Web UI** (dev/test only, near-realtime polling every 3s), **console adapter** (colored, pretty-printed), **event registry API**, **CLI tools** (rake tasks), and **auto-generated docs**.

**Context:**
Developers need visibility into tracked events (where did event go?), event discovery (what events exist?), debug capabilities (inspect pipeline), and visual tools (not just command-line). Traditional in-memory adapters break with multi-process servers (Puma workers).

**Consequences:**
- **Positive:** Zero-friction dev setup (<1 min), multi-process safe (works with Puma), persistent across restarts (helpful for debugging), beautiful DX (console + Web UI), 100% event discovery (registry API)
- **Negative:** File-based ~50ms read latency (vs. in-memory ~1ms), near-realtime (3s polling) not true realtime (vs. WebSocket), dev-only features (NOT for production)

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **File-Based JSONL Dev_log Adapter (Multi-Process Safe):**
  - JSONL format (one JSON per line, append-only)
  - Multi-process safe (file locking: File::LOCK_EX)
  - Thread-safe (Mutex for writes)
  - Persistent across restarts (events survive server restart)
  - Zero dependencies (just filesystem)
  - Auto-rotation (max 10K events, max 10MB, keeps last 50%)
  - Cache with invalidation (mtime-based, ~50ms read latency)
- [x] **File-Based Chosen Over In-Memory:**
  - In-memory rejected: broken with multi-process (Puma 4 workers → 4 separate stores, Web UI sees only 25% of events)
  - File-based: multi-process safe, persistent, greppable (`tail -f | jq`)
  - Trade-off: ~50ms read latency vs. zero dependencies + multi-process support
- [x] **Web UI Engine (Dev/Test Only):**
  - Mounted at `/e11y` in development/test (Rails::Engine)
  - Event Explorer (browse, filter, search, paginate)
  - Near-realtime polling (JavaScript, every 3s, file mtime check)
  - Auto-refresh on new events (optional checkbox)
  - Export (JSON, CSV)
  - Clear all (delete file)
  - **Production Safety:** before_action raises error if not dev/test
- [x] **Console Adapter (Pretty-Printed, Colored):**
  - Colorized severity (gray:debug, white:info, green:success, yellow:warn, red:error/fatal)
  - Pretty-print payload (truncate long values to 50 chars)
  - Show metadata (trace_id, span_id, adapters)
  - Configurable (colorize, pretty_print, show_payload, show_metadata)
- [x] **Event Registry API (Introspection):**
  - `E11y.events` - List all events
  - `E11y.search(query)` - Search events by name
  - `E11y.inspect(event_class)` - Show schema, version, adapters, severity
  - `E11y.stats` - Statistics (total events, by severity, by adapter, deprecated count)
  - `E11y::Registry.introspect` - Detailed event info (schema extraction, migration rules)
- [x] **CLI Tools (Rake Tasks):**
  - `rake e11y:list` - List all events with versions, severity, adapters
  - `rake e11y:validate` - Validate all event schemas (CI integration)
  - `rake e11y:docs:generate` - Generate markdown docs (auto-generated from schemas)
  - `rake e11y:stats` - Show statistics
- [x] **Auto-Generated Documentation:**
  - Per-event docs (schema, usage examples, version history)
  - Catalog (by severity, by adapter)
  - Always up-to-date (generated from registry)

### Should Have (Important)
- [x] Debug helpers (`E11y::Debug::PipelineInspector.trace_event` - trace pipeline execution)
- [x] Near-realtime polling (JavaScript, 3s interval, file mtime check)
- [x] Dev_log adapter query API (all_events, find_event, events_by_name, events_by_severity, events_by_trace, search)
- [x] Event statistics (total, by severity, by adapter, oldest/newest)

### Could Have (Nice to have)
- [ ] Query Loki from Web UI (deferred to v1.1+: requires Loki setup in dev, slow queries)
- [ ] WebSocket realtime (rejected: too complex for dev, polling sufficient)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-014:** Adaptive Sampling (C05 trace-aware, C11 stratified)
- **UC-015:** Cost Optimization (7 strategies, deduplication rejected)
- **UC-017:** Local Development
- **UC-022:** Event Registry

### Related ADRs
- **ADR-001:** Core Architecture
- **ADR-004:** Adapter Architecture
- **ADR-011:** Testing Strategy
- **ADR-012:** Event Evolution
- **ADR-014:** Adaptive Sampling

---

## ⚡ Technical Constraints

### Performance (Dev_log Adapter)
- Write: ~0.1ms (file append)
- Read: ~50ms (parse JSONL, cache)
- Cache hit: ~1ms (mtime check)
- Multi-process write contention: file locking adds overhead

### Disk Usage
- Typical: 10,000 events × 500 bytes = ~5MB
- Max: 10MB (auto-rotation)

### Web UI
- Polling interval: 3s (near-realtime)
- Max events displayed: 1000 (paginated 50/page)
- Export: JSON/CSV (max 10,000 events)

---

## 🎭 Rationale & Alternatives

**Decision:** File-based JSONL + Web UI (dev/test only) + Console adapter

**Rationale:**

**1. File-Based JSONL (Multi-Process Safe):**
- In-memory rejected: broken with Puma (4 workers → 4 separate stores → Web UI sees 25% of events)
- File-based: append-only (atomic), file locking (LOCK_EX), multi-process safe, persistent, greppable

**2. Web UI Dev-Only:**
- Production Web UI rejected: security risk, infrastructure overhead
- Dev-only: zero friction, auto-mounted, near-realtime (3s polling sufficient)

**3. JSONL Format:**
- Zero dependencies (vs. Redis, Database, Loki)
- CLI-friendly (`tail -f | jq`)
- Auto-rotation (prevents infinite growth)

**Alternatives Rejected:**
1. **In-Memory adapter** - Rejected: broken with multi-process (Puma 4 workers)
2. **Query Loki/ES** - Rejected: requires infrastructure in dev, slow, complex setup
3. **Redis storage** - Rejected: extra dependency (Redis required in dev)
4. **Database storage** - Rejected: pollutes app DB, migration needed
5. **WebSocket realtime** - Rejected: too complex (Action Cable, Redis), polling sufficient (3s)

**Trade-offs:**
- ✅ Zero friction, multi-process safe, persistent, greppable, beautiful DX
- ❌ ~50ms read latency (vs. in-memory ~1ms), 3s polling delay (vs. WebSocket instant)

---

## ⚠️ Potential Contradictions

### Contradiction 1: File-Based JSONL (Multi-Process Safe) vs. Read Latency (~50ms)
**Conflict:** File-based adapter is multi-process safe (append-only file) BUT read latency ~50ms (parse JSONL) vs. in-memory ~1ms
**Impact:** Low (acceptable for development)
**Related to:** ADR-001 (Performance Requirements)
**Notes:** Lines 97-104 show trade-off table:
```
| E) File (JSONL) | Multi-process, zero deps, persistent | Read overhead (~50ms) | ✅ CHOSEN |
```
Lines 1932-1945 show comparison: File-based read ~50ms, Redis ~5ms, in-memory ~1ms.

**Trade-off:** ~50ms read latency is acceptable for dev (Web UI loads events once, then caches). Multi-process support (works with Puma) outweighs latency.

**Alternative:** In-memory would be faster (~1ms) BUT breaks with Puma (4 workers → Web UI sees only 25% of events).

### Contradiction 2: Web UI Near-Realtime (3s Polling) vs. Developer Expectation of Instant Updates
**Conflict:** Web UI uses polling every 3 seconds (near-realtime) BUT developers might expect instant updates (true realtime)
**Impact:** Low (3s delay acceptable for dev)
**Related to:** Developer expectations
**Notes:** Lines 947-1030 describe JavaScript polling:
- Interval: 3000ms (3 seconds)
- Check file mtime (updated_since?)
- Show badge with "N new events"
- Auto-refresh if checkbox enabled

**Real Evidence:**
```
Lines 956-969: "this.interval = 3000;  // Poll every 3 seconds

this.pollerId = setInterval(() => {
  this.poll();
}, this.interval);"

Lines 1889-1890: "❌ REJECTED: Too complex for dev
✅ CHOSEN: Polling every 3 seconds (simple, good enough)"
```

**Trade-off:** 3s delay vs. WebSocket complexity (Action Cable, Redis, WebSocket setup). Decision: 3s is "good enough" for development (line 1890).

**Alternative:** WebSocket would be instant BUT requires Action Cable, Redis (extra dependencies), WebSocket setup (complex).

### Contradiction 3: Auto-Rotation (Max 10K Events, 10MB) vs. Debugging Long-Running Issues
**Conflict:** Auto-rotation keeps last 10K events or 10MB (prevents infinite growth) BUT limits history for debugging long-running issues (>10K events)
**Impact:** Low (configurable, 10K sufficient for 99% cases)
**Related to:** Development workflow
**Notes:** Lines 470-473 show defaults:
```
max_lines: config[:max_lines] || 10_000
max_size: config[:max_size] || 10.megabytes
```

Lines 644-666 show rotation logic (keep last 50% of lines).

**Trade-off:** Auto-rotation prevents infinite file growth (disk space) BUT limits history to last 10K events.

**Mitigation:** Lines 2012-2022 show limits are configurable (can increase to 50K events, 50MB). Document states "10K events is sufficient for 99% dev use cases" (line 2022).

**Clarification Needed:** What if developer needs to debug issue that requires >10K events history (e.g., tracking down rare event that occurs once per 50K requests)?

---

## 🔍 Implementation Notes

### Key Components
- E11y::Adapters::DevLog (file-based JSONL adapter)
- E11y::Adapters::Console (pretty-printed console output)
- E11y::WebUI::Engine (Rails engine, dev/test only)
- E11y::WebUI::EventsController (index, show, trace, clear, export, poll)
- E11y::Registry (introspection API)
- E11y::Console (console helper methods)
- E11y::Debug::PipelineInspector (trace pipeline)
- E11y::Documentation::Generator (auto-generate docs)

---

## 🧪 Testing Considerations

### Test Scenarios
1. File-based adapter: Track 100 events, verify all written to JSONL file
2. Multi-process: Start 4 Puma workers, track events, verify Web UI shows all events (not just 25%)
3. Auto-rotation: Fill file to 11MB (>10MB limit), verify rotation (keep last 50%)
4. Near-realtime polling: Track event, wait 3s, verify Web UI shows new event badge
5. Console adapter: Track event, verify colored output (green for success, red for error)
6. Event registry: Call `E11y.events`, verify all events listed
7. Production safety: Access `/e11y` in production, verify raises error

---

## 📊 Complexity Assessment

**Overall Complexity:** Medium

**Reasoning:**
- File-based adapter is straightforward (append to file, parse JSONL)
- Web UI is standard Rails engine (controller, views, routes)
- Near-realtime polling is simple (JavaScript setInterval, 3s)
- Event registry is basic introspection (extract schema, count by severity/adapter)
- CLI tools are standard rake tasks

**Estimated Implementation Time:**
- Junior dev: 10-12 days
- Senior dev: 6-8 days

---

## 📚 References

### Related Documentation
- [UC-017: Local Development](../use_cases/UC-017-local-development.md)
- [UC-022: Event Registry](../use_cases/UC-022-event-registry.md)
- [ADR-001: Core Architecture](./ADR-001-architecture.md)
- [ADR-011: Testing Strategy](./ADR-011-testing-strategy.md)
- [ADR-012: Event Evolution](./ADR-012-event-evolution.md)

### Research Notes
- **File-based JSONL choice:** Multi-process safe (Puma 4 workers), persistent (survives restart), zero deps, greppable, ~50ms read latency acceptable
- **In-memory rejected:** Broken with Puma (4 workers → 4 separate stores → Web UI sees 25% of events)
- **WebSocket rejected:** Too complex (Action Cable, Redis), 3s polling sufficient for dev
- **Production safety:** before_action :ensure_development_environment! prevents Web UI in production

---

## 🏷️ Tags

`#critical` `#developer-experience` `#file-based-jsonl` `#web-ui-dev-only` `#multi-process-safe` `#near-realtime-polling` `#console-adapter` `#event-registry`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3)
