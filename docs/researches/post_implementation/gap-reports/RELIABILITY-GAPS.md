# Reliability & Error Handling Gaps

**Audit Scope:** Phase 3 audits (AUDIT-010 to AUDIT-014)  
**Total Issues:** TBD  
**Status:** 🔄 In Progress

---

## 📊 Overview

Summary of reliability and error handling gaps found during E11y v0.1.0 audit.

**Audits Analyzed:**
- AUDIT-010: ADR-013 Reliability & Error Handling
- AUDIT-011: ADR-016 Self-Monitoring SLO
- AUDIT-012: UC-009 Circuit Breaker
- AUDIT-013: UC-011 Dead Letter Queue
- AUDIT-014: UC-013 Retry Strategy

---

## 🔴 HIGH Priority Issues

### REL-001: Automatic Retention Enforcement Not Implemented

**Source:** AUDIT-003-RETENTION-ARCHIVAL  
**Finding:** New findings (archival, deletion jobs)  
**Reference:** [AUDIT-003-UC-012-RETENTION-ARCHIVAL.md:38-42](docs/researches/post_implementation/AUDIT-003-UC-012-RETENTION-ARCHIVAL.md#L38-L42)

**Problem:**
No automatic retention enforcement. Missing:
- Archival job (move old logs to cold storage)
- Deletion job (purge logs after retention period)
- Cleanup mechanism (hot storage management)
- Per-event-type retention configuration

**Impact:**
- HIGH - GDPR over-retention risk (GDPR Art. 5(1)(e) - storage limitation)
- SOC2 CC7.3 (Retention) failure
- Storage costs grow unbounded
- Cannot prove to auditors that old data is purged
- Legal risk: keeping data longer than necessary

**Evidence:**
```
DoD (1a): Automatic archival: logs older than N days moved to cold storage
Status: ❌ NOT_IMPLEMENTED
No archival job found

DoD (2a): Deletion: logs deleted after retention period
Status: ❌ NOT_IMPLEMENTED
No deletion job found

DoD (3): Configuration: retention periods configurable per event type
Status: ⚠️ PARTIAL
Metadata exists in code, not enforced
```

**Current State:**
Retention policies **documented** (7 years default) but **NOT enforced** = ⚠️ PARTIAL COMPLIANCE

**Recommendation:** Build retention enforcement system (Priority 1-HIGH, 1-2 weeks effort)  
**Action:**
1. Create `AuditRetentionJob` background job
2. Implement archival logic (move to cold adapter)
3. Implement deletion logic (purge old events)
4. Add per-event-type retention config support
5. Add monitoring/alerting for retention failures

**Status:** ❌ NOT_IMPLEMENTED (documented only)

---

### REL-002: DLQ Replay Not Implemented (Operational Recovery Blocked)

**Source:** AUDIT-012-DLQ-REPLAY  
**Finding:** F-213, F-214  
**Reference:** [AUDIT-012-UC-021-DLQ-REPLAY.md:25-26, :40-42, :77-78](docs/researches/post_implementation/AUDIT-012-UC-021-DLQ-REPLAY.md#L25-L26)

**Problem:**
DLQ (Dead Letter Queue) replay workflow NOT implemented. Manual and batch replay are TODO stubs.

**Impact:**
- 🔴 **HIGH** - Cannot recover from adapter failures operationally
- Failed events accumulate in DLQ with no recovery path
- Production incidents require manual intervention
- No automation for transient failure retry

**Evidence:**
```ruby
# lib/e11y/reliability/dlq/file_storage.rb:139-157
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

**Missing Functionality:**
```
DoD (1a): Manual replay: E11y.dlq.replay(event_id) works
Status: ❌ FAIL - Method exists but TODO stub

DoD (2a): Batch replay: E11y.dlq.replay_all exists
Status: ❌ FAIL - No replay_all method

DoD (2b-2c): Batch replay filtering (age, error type)
Status: ❌ N/A - Replay not implemented
```

**Operational Scenario:**
```
1. Loki adapter down (network issue)
2. 10,000 events go to DLQ
3. Loki comes back online
4. ❌ NO WAY to replay DLQ events automatically
5. Manual intervention required (reconstruct events)
```

**Recommendation:** Implement DLQ replay (Priority 1-HIGH, 1-2 weeks effort)  
**Action:**
1. Implement `E11y.dlq.replay(event_id)` - single event replay
2. Implement `E11y.dlq.replay_all(age: nil, error_type: nil)` - batch replay with filtering
3. Implement `E11y::Pipeline.dispatch` for re-routing replayed events
4. Add replay monitoring metrics
5. Add replay rate limiting (prevent thundering herd)

**Status:** ❌ NOT_IMPLEMENTED (critical operational gap)

---

### REL-003: No Explicit Hysteresis for Adaptive Sampling
**Source:** AUDIT-017-UC-014-LOAD-BASED-SAMPLING
**Finding:** F-285
**Reference:** [AUDIT-017-UC-014-LOAD-BASED-SAMPLING.md:261-285, :331-333](docs/researches/post_implementation/AUDIT-017-UC-014-LOAD-BASED-SAMPLING.md#L261-L285)

**Problem:**
No explicit hysteresis implementation (no separate up/down thresholds for load-based sampling transitions).

**Impact:**
- MEDIUM - Risk of oscillation at threshold boundaries
- Load hovering near thresholds (e.g., 9,999 → 10,001 → 9,999 events/sec) could cause sampling rate oscillation (100% → 50% → 100%)
- Sliding window provides implicit smoothing (60s damping), but unvalidated
- No oscillation scenario tests to verify resistance

**Technical Details:**
- Current: Uses same thresholds for up/down transitions
- Expected: Separate up/down thresholds with 10% gap
- Example: Transition up at 10k events/sec, down at 9k events/sec (1k gap prevents oscillation)

**Recommendation:**
- **R-077**: Implement explicit hysteresis with separate up/down thresholds (10% gap)
- **R-078**: Add oscillation scenario tests to verify stability
- **Priority:** MEDIUM (2-MEDIUM)
- **Effort:** 1 day (R-077) + 2-3 hours (R-078)
- **Rationale:** Prevent oscillation when load hovers near thresholds

**Status:** ❌ MISSING (Sliding window may be sufficient, but unvalidated)

---

## 🟡 MEDIUM Priority Issues

---

## 🟢 LOW Priority Issues

---

## 🔗 Cross-References

