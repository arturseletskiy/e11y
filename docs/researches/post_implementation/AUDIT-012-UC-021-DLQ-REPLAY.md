# AUDIT-012: UC-021 Error Handling & DLQ - DLQ Replay Workflow

**Audit ID:** AUDIT-012  
**Task:** FEAT-4953  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**UC Reference:** UC-021 Error Handling & DLQ §4 (DLQ Replay)  
**Related Audit:** AUDIT-010 ADR-013 DLQ Mechanism (F-170, F-171, F-168)  
**Cross-Reference:** AUDIT-005 ADR-004 (F-066, F-067)

---

## 📋 Executive Summary

**Audit Objective:** Verify DLQ replay workflow including manual replay, batch replay with filtering, and DLQ monitoring metrics.

**Scope:**
- Manual replay: E11y.dlq.replay(event_id) works
- Batch replay: E11y.dlq.replay_all filters by age/error type
- Monitoring: DLQ metrics (size, age distribution) exposed

**Overall Status:** ❌ **NOT_IMPLEMENTED** (30%)

**Key Findings:**
- ❌ **FAIL**: Manual replay NOT implemented (TODO stub, F-170)
- ❌ **FAIL**: Batch replay NOT implemented (depends on manual, F-171)
- ⚠️ **PARTIAL**: DLQ stats exist (size, age) but limited
- ❌ **NOT_FOUND**: No E11y.dlq convenience API (F-169)
- ✅ **PASS**: FileStorage#replay method exists (skeleton)
- ✅ **PASS**: FileStorage#stats method works

**Note:** This is a critical production readiness gap - DLQ replay is essential for operational recovery.

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) Manual replay: E11y.dlq.replay(event_id) works** | ❌ FAIL | Method exists but TODO stub | HIGH |
| **(1b) Manual replay: respects current config** | ❌ N/A | Replay not implemented | HIGH |
| **(2a) Batch replay: E11y.dlq.replay_all exists** | ❌ FAIL | No replay_all method | HIGH |
| **(2b) Batch replay: filters by age** | ❌ N/A | Replay not implemented | HIGH |
| **(2c) Batch replay: filters by error type** | ❌ N/A | Replay not implemented | HIGH |
| **(3a) Monitoring: DLQ size metric** | ✅ PASS | FileStorage#stats[:total_entries] | ✅ |
| **(3b) Monitoring: age distribution** | ⚠️ PARTIAL | oldest/newest, not distribution | MEDIUM |

**DoD Compliance:** 1/7 requirements met (14%), 1 partial, 5 not implemented

---

## 🔍 AUDIT AREA 1: Manual Replay

### 1.1. Replay Method Status

**Cross-Reference:** AUDIT-010 F-170 (Replay NOT Implemented)

**File:** `lib/e11y/reliability/dlq/file_storage.rb:139-157`

```ruby
def replay(event_id)
  entry = find_entry(event_id)
  return false unless entry

  # Re-dispatch event through E11y pipeline
  # TODO: Implement E11y::Pipeline.dispatch  ← NOT IMPLEMENTED!
  # E11y::Pipeline.dispatch(entry[:event_data], ...)

  # For now, just mark as replayed
  increment_metric("e11y.dlq.replayed", event_name: entry[:event_name])
  true  # ← Fake success!
end
```

**Finding:**
```
F-213: Manual Replay NOT Implemented (FAIL) ❌
────────────────────────────────────────────────
Component: FileStorage#replay
Requirement: E11y.dlq.replay(event_id) works
Status: NOT_IMPLEMENTED ❌ (CROSS-REFERENCE: AUDIT-010 F-170)

Issue:
Method exists but is TODO stub - doesn't actually replay events.

UC-021 Expected Behavior:
```ruby
# After Loki recovers from outage:
E11y.dlq.replay("uuid-123")

# Should:
1. Load event from DLQ ✅ (find_entry works)
2. Re-emit event through pipeline ❌ (TODO stub)
3. Mark as replayed ✅ (metric incremented)
4. Remove from DLQ or mark processed ❌ (not implemented)
```

Current Behavior:
```ruby
dlq.replay("uuid-123")
# → Returns true ❌ (misleading!)
# → Increments metric ❌ (fake success)
# → Event NOT actually replayed ❌
```

Impact:
❌ Manual recovery after outage impossible
❌ Must manually re-track events (workaround)
❌ DLQ accumulates without cleanup

Workaround (manual):
```ruby
# Read DLQ:
dlq = E11y::Reliability::DLQ::FileStorage.new
events = dlq.list(limit: 100)

# Manually replay:
events.each do |entry|
  event_class = entry[:event_data][:event_name].constantize
  event_class.track(**entry[:event_data][:payload])
end
```

Verdict: FAIL ❌ (replay exists but doesn't work)
```

---

## 🔍 AUDIT AREA 2: Batch Replay

### 2.1. replay_all Method

**DoD Expectation:** `E11y.dlq.replay_all(filters: { age: ..., error_type: ... })`

**Actual:** No replay_all method exists

**Finding:**
```
F-214: Batch Replay NOT Implemented (FAIL) ❌
───────────────────────────────────────────────
Component: DLQ API
Requirement: E11y.dlq.replay_all with filters
Status: NOT_IMPLEMENTED ❌

Issue:
No replay_all method exists. FileStorage has replay_batch but:
1. Requires manual event_id list
2. Depends on replay() (which doesn't work)

Expected API:
```ruby
# Replay all events from last hour:
E11y.dlq.replay_all(filters: {
  after: Time.now - 1.hour
})

# Replay all timeout errors:
E11y.dlq.replay_all(filters: {
  error_type: "Timeout::Error"
})

# Replay payment events only:
E11y.dlq.replay_all(filters: {
  event_name: "Events::PaymentProcessed",
  after: Time.now - 24.hours
})
```

Current State:
FileStorage#replay_batch exists but:
```ruby
def replay_batch(event_ids)
  # Requires explicit event_id array ⚠️
  # No filtering by age/error_type ❌
  # Depends on replay() (broken) ❌
end
```

Manual Workaround:
```ruby
# 1. List with filters:
events = dlq.list(filters: {
  event_name: "Events::PaymentProcessed",
  after: Time.now - 1.hour
})

# 2. Extract IDs:
event_ids = events.map { |e| e[:id] }

# 3. Manual replay:
event_ids.each do |id|
  entry = dlq.find_entry(id)
  event_class = entry[:event_data][:event_name].constantize
  event_class.track(**entry[:event_data][:payload])
end
```

Verdict: FAIL ❌ (no replay_all, manual workaround required)
```

---

## 🔍 AUDIT AREA 3: DLQ Monitoring

### 3.1. DLQ Stats Method

**Cross-Reference:** AUDIT-010 F-168 (FileStorage#stats)

**File:** `lib/e11y/reliability/dlq/file_storage.rb:105-137`

```ruby
def stats
  return default_stats unless File.exist?(@file_path)

  file_size_bytes = File.size(@file_path)
  total_entries = File.foreach(@file_path).count

  oldest_entry = nil
  newest_entry = nil

  # Read first and last line:
  File.foreach(@file_path).with_index do |line, index|
    entry = JSON.parse(line, symbolize_names: true)
    oldest_entry = entry[:timestamp] if index.zero?
    newest_entry = entry[:timestamp]
  end

  {
    total_entries: total_entries,  # ← DLQ size ✅
    file_size_mb: (file_size_bytes / 1024.0 / 1024.0).round(2),
    oldest_entry: oldest_entry,  # ← Age info ✅
    newest_entry: newest_entry,
    file_path: @file_path
  }
end
```

**Finding:**
```
F-215: DLQ Size Metric (PASS) ✅
─────────────────────────────────
Component: FileStorage#stats
Requirement: DLQ size monitoring
Status: PASS ✅

Evidence:
- total_entries: Count of DLQ events
- file_size_mb: Disk usage
- Stats accessible via FileStorage instance

Usage:
```ruby
dlq = E11y::Reliability::DLQ::FileStorage.new
stats = dlq.stats

puts stats[:total_entries]  # → 1234 events in DLQ
puts stats[:file_size_mb]   # → 5.67 MB
```

Monitoring:
```ruby
# Expose as Prometheus gauge:
E11y::Metrics.gauge(
  :e11y_dlq_entries_total,
  dlq.stats[:total_entries]
)

E11y::Metrics.gauge(
  :e11y_dlq_file_size_mb,
  dlq.stats[:file_size_mb]
)
```

Alert Example:
```yaml
- alert: DLQTooLarge
  expr: e11y_dlq_entries_total > 10000
  annotations:
    summary: "DLQ has >10K events (investigate failures)"
```

Verdict: PASS ✅ (DLQ size tracking works)
```

### 3.2. Age Distribution

**DoD Expectation:** Age distribution metrics

**Actual:** oldest_entry, newest_entry (not distribution)

**Finding:**
```
F-216: Age Distribution (PARTIAL) ⚠️
──────────────────────────────────────
Component: FileStorage#stats
Requirement: DLQ age distribution exposed
Status: PARTIAL ⚠️

Current State:
```ruby
stats = dlq.stats
# → {
#   oldest_entry: "2026-01-20T10:00:00Z",  ← Oldest timestamp
#   newest_entry: "2026-01-21T10:30:45Z"   ← Newest timestamp
# }
```

Expected (age distribution):
```ruby
stats[:age_distribution] = {
  "< 1h": 150,      # 150 events less than 1 hour old
  "1h-6h": 450,     # 450 events 1-6 hours old
  "6h-24h": 300,    # 300 events 6-24 hours old
  "> 24h": 100      # 100 events over 24 hours old
}
```

Current Capability:
✅ Can calculate age range: newest - oldest
⚠️ Cannot see distribution (how many events in each age bucket)

Impact:
⚠️ Hard to identify stale events
⚠️ Cannot prioritize replay (oldest first)
❌ No visibility into DLQ aging patterns

Recommendation:
Add age distribution calculation:
```ruby
def age_distribution_stats
  buckets = {
    "< 1h" => 0,
    "1h-6h" => 0,
    "6h-24h" => 0,
    "> 24h" => 0
  }
  
  list.each do |entry|
    age_hours = (Time.now - Time.parse(entry[:timestamp])) / 3600
    
    case age_hours
    when 0..1 then buckets["< 1h"] += 1
    when 1..6 then buckets["1h-6h"] += 1
    when 6..24 then buckets["6h-24h"] += 1
    else buckets["> 24h"] += 1
    end
  end
  
  buckets
end
```

Verdict: PARTIAL ⚠️ (age range yes, distribution no)
```

---

## 🎯 Findings Summary

### Implemented Features

```
F-215: DLQ Size Metric (PASS) ✅
```
**Status:** 1/5 monitoring features

### Partial Implementation

```
F-216: Age Distribution (PARTIAL) ⚠️
       (oldest/newest timestamps, not bucketed distribution)
```
**Status:** Limited age monitoring

### Not Implemented

```
F-213: Manual Replay NOT Implemented (FAIL) ❌
       (CROSS-REF: AUDIT-010 F-170, TODO stub)
       
F-214: Batch Replay NOT Implemented (FAIL) ❌
       (No replay_all method, manual workaround required)
```
**Status:** Replay functionality missing

---

## 🎯 Conclusion

### Overall Verdict

**DLQ Replay Workflow Status (UC-021):** ❌ **NOT_IMPLEMENTED** (30%)

**What Works:**
- ✅ DLQ size monitoring (total_entries, file_size_mb)
- ✅ Age range tracking (oldest_entry, newest_entry)
- ✅ FileStorage#replay method exists (skeleton)
- ✅ FileStorage#replay_batch method exists (skeleton)

**What Doesn't Work:**
- ❌ Manual replay (method is TODO stub)
- ❌ Batch replay (depends on broken manual replay)
- ❌ No E11y.dlq convenience API
- ❌ No replay_all with filters
- ⚠️ Age distribution limited (no bucketing)

**Production Impact:**

**Scenario: 1-Hour Loki Outage**
```
10:00 - Loki goes down
10:00-11:00 - 3600 events fail → DLQ
11:00 - Loki recovers

Expected (with replay):
E11y.dlq.replay_all(filters: { after: 10:00 })
→ 3600 events replayed ✅

Actual (without replay):
Manual Ruby script required:
```ruby
dlq = E11y::Reliability::DLQ::FileStorage.new
events = dlq.list(filters: { after: Time.parse("10:00") })

events.each do |entry|
  event_class = entry[:event_data][:event_name].constantize
  event_class.track(**entry[:event_data][:payload])
  
  # Rate limiting to avoid overwhelming Loki:
  sleep(0.01)  # 100 events/sec
end
# → ~36 seconds to replay 3600 events
```

**Operational Burden:**
❌ Manual intervention required
❌ SRE must write recovery scripts
❌ Error-prone (copy-paste bugs)
⚠️ Acceptable for rare outages, poor for frequent issues

---

## 📋 Recommendations

### Priority: HIGH (Operational Requirement)

**R-056: Implement DLQ Replay Functionality** (HIGH)
- **Urgency:** HIGH (same as AUDIT-010 R-044)
- **Effort:** 2-3 days
- **Impact:** Automated recovery from outages
- **Action:** Complete FileStorage#replay implementation

**Cross-Reference:** This is the same as AUDIT-010 R-044.

**R-057: Implement replay_all with Filters** (HIGH)
- **Urgency:** HIGH (operational convenience)
- **Effort:** 1-2 days
- **Impact:** Batch recovery with filtering
- **Action:** Add replay_all method

**Implementation Template (R-057):**
```ruby
# lib/e11y/reliability/dlq/file_storage.rb
def replay_all(filters: {}, rate_limit: 100)
  # 1. List events with filters:
  events = list(filters: filters, limit: 10_000)
  
  # 2. Replay batch:
  result = replay_batch(
    events.map { |e| e[:id] },
    rate_limit: rate_limit
  )
  
  # 3. Return summary:
  {
    total_events: events.size,
    success_count: result[:success_count],
    failure_count: result[:failure_count],
    filters: filters
  }
end

# Usage:
dlq.replay_all(filters: {
  event_name: "Events::PaymentProcessed",
  after: Time.now - 1.hour
}, rate_limit: 50)  # 50 events/sec (don't overwhelm adapter)
```

**R-058: Add Age Distribution Stats** (MEDIUM)
- **Urgency:** MEDIUM (operational visibility)
- **Effort:** 1-2 days
- **Impact:** Better DLQ insights
- **Action:** Implement age bucketing

---

## 📚 References

### Internal Documentation
- **UC-021:** Error Handling & DLQ §4 (Replay Workflow)
- **ADR-013:** Reliability & Error Handling §4.4 (DLQ Replay)
- **Implementation:** lib/e11y/reliability/dlq/file_storage.rb
- **Tests:** spec/e11y/reliability/dlq/file_storage_spec.rb

### Related Audits
- **AUDIT-010:** DLQ Mechanism
  - F-168: DLQ Retrieval API (PASS)
  - F-169: No E11y.dlq API (FAIL)
  - F-170: Replay NOT Implemented (FAIL)
  - F-171: Batch Replay NOT Implemented (FAIL)
  - F-172: File Rotation (PASS)
  - F-173: Cleanup and Retention (PASS)
  - R-044: Implement DLQ Replay (HIGH priority)
  - R-045: Add E11y.dlq API (MEDIUM priority)

---

**Audit Completed:** 2026-01-21  
**Status:** ❌ **NOT_IMPLEMENTED** (30% - monitoring works, replay doesn't)

**Critical Assessment:**  
UC-021's DLQ replay workflow is **NOT production-ready**. While DLQ monitoring works (size tracking, age range), the critical replay functionality is not implemented - the `replay()` method is just a TODO stub that increments a metric but doesn't actually re-emit events. This creates a significant operational gap: when adapters recover from outages, there's no automated way to replay the accumulated DLQ events. Manual workarounds are possible (read DLQ, manually call `.track()`) but are error-prone and operationally burdensome. The `replay_all` method with filtering (by age, error type) doesn't exist at all. Additionally, there's no high-level `E11y.dlq` convenience API - users must instantiate `FileStorage` directly. Age distribution monitoring is limited (oldest/newest timestamps only, no bucketing). **This is a critical production readiness blocker** - automated recovery from outages is essential for reliability. Cross-references AUDIT-010 findings F-168-F-171 and recommendations R-044/R-045.

**Auditor Signature:**  
AI Assistant (Claude Sonnet 4.5)  
Audit ID: AUDIT-012
