# Testing Strategy Gaps

**Audit Scope:** Testing-related audits from Phase 6  
**Total Issues:** TBD  
**Status:** 🔄 In Progress

---

## 📊 Overview

Summary of testing strategy gaps found during E11y v0.1.0 audit.

**Audits Analyzed:**
- AUDIT-030: ADR-011 Testing Strategy
- AUDIT-036: UC-018 Testing Events in Test Mode

---

## 🔴 HIGH Priority Issues

---

## 🟡 MEDIUM Priority Issues

### TEST-001: Allocation Count Not Reported in Benchmarks

**Source:** AUDIT-004-ZERO-ALLOCATION  
**Finding:** F-002  
**Reference:** [AUDIT-004-ADR-001-zero-allocation.md:533-536, :553-556](docs/researches/post_implementation/AUDIT-004-ADR-001-zero-allocation.md#L533-L536)

**Problem:**
Existing benchmarks (`e11y_benchmarks.rb`) measure memory in MB but don't report allocation count. DoD requires `allocation_stats` gem usage and per-event allocation reporting.

**Impact:**
- MEDIUM - Cannot track allocation regressions
- Cannot verify zero-allocation pattern effectiveness
- DoD requirement not met

**Evidence:**
```ruby
# benchmarks/e11y_benchmarks.rb
# Current: Reports "Memory: 45.2 MB"
# Missing: Reports "Allocations: 7,850 (7.85/event)"
```

**DoD Requirement:**
```
DoD: Use allocation_stats gem, verify <100 allocations per 1K events
Actual: Benchmark exists but doesn't use allocation_stats
```

**Recommendation:** R-002 - Modify `e11y_benchmarks.rb` to report `total_allocated` count from `memory_profiler` (Priority 2-MEDIUM, 2-3 hours effort)  
**Action:**
```ruby
# Add to benchmark output:
result = MemoryProfiler.report { ... }
puts "Allocations: #{result.total_allocated} (#{result.total_allocated / event_count}/event)"
```
**Status:** ❌ NOT_IMPLEMENTED

---

### TEST-002: No Backward Compatibility Test Suite

**Source:** AUDIT-007-BACKWARD-COMPAT  
**Finding:** F-087  
**Reference:** [AUDIT-007-ADR-012-BACKWARD-COMPAT.md:455, :482, :523-527](docs/researches/post_implementation/AUDIT-007-ADR-012-BACKWARD-COMPAT.md#L455)

**Problem:**
No test suite for backward/forward compatibility. Cannot verify schema evolution safety.

**Impact:**
- HIGH - Schema changes are high-risk operations
- Cannot test v1→v2, v2→v1 scenarios
- No safety net before deployment
- Breaking changes discovered in production

**Missing Test Scenarios:**
```
1. Old consumer + new event (forward compat)
   - V1 consumer reads V2 event with extra fields
   - V1 should ignore unknown fields

2. New consumer + old event (backward compat)
   - V2 consumer reads V1 event missing fields
   - V2 should use default values

3. Mixed versions in pipeline
   - V1 and V2 consumers running simultaneously
   - Both should work without crashes
```

**Evidence:**
```
DoD (3): Mixed versions: pipeline handles simultaneously
Status: ⚠️ UNKNOWN
No tests found

F-087: No Compatibility Tests (FAIL) ❌
Impact: No safety net for schema changes
```

**Recommendation:** R-033 - Add compatibility test suite (Priority 1-HIGH, 1 week effort)  
**Action:**
```ruby
# spec/e11y/schema_evolution_spec.rb
RSpec.describe 'Schema Evolution' do
  describe 'Backward Compatibility' do
    it 'V2 consumer reads V1 event (missing fields use defaults)' do
      # Test new consumer + old event
    end
  end
  
  describe 'Forward Compatibility' do
    it 'V1 consumer reads V2 event (ignores unknown fields)' do
      # Test old consumer + new event
    end
  end
  
  describe 'Mixed Versions' do
    it 'V1 and V2 consumers coexist in pipeline' do
      # Test simultaneous versions
    end
  end
end
```
**Status:** ❌ NOT_IMPLEMENTED

---

## 🟢 LOW Priority Issues

---

## 🔗 Cross-References


---

### TEST-003: No Oscillation Scenario Tests for Adaptive Sampling
**Source:** AUDIT-017-UC-014-LOAD-BASED-SAMPLING
**Finding:** F-288
**Reference:** [AUDIT-017-UC-014-LOAD-BASED-SAMPLING.md:452-488](docs/researches/post_implementation/AUDIT-017-UC-014-LOAD-BASED-SAMPLING.md#L452-L488)

**Problem:**
No oscillation scenario tests (load hovering near threshold boundaries).

**Impact:**
- MEDIUM - Cannot verify oscillation resistance
- No tests for rapid up/down transitions
- Cannot verify that sliding window smoothing prevents oscillation
- Missing validation of stability when load oscillates around thresholds (9,950 → 10,050 → 9,980 → 10,020 events/sec)

**Test Coverage Gaps:**
- ❌ Load oscillating around threshold
- ❌ Rapid up/down transitions
- ❌ Sustained threshold boundary conditions
- ❌ Hysteresis behavior (if implemented)

**Recommendation:**
- **R-078**: Add oscillation scenario tests to `spec/e11y/sampling/load_monitor_spec.rb`
- **Priority:** MEDIUM (2-MEDIUM)
- **Effort:** 2-3 hours
- **Rationale:** Verify oscillation resistance before production deployment

**Status:** ❌ MISSING (critical for production confidence)

---

### TEST-004: No W3C Trace Context Validation Tests
**Source:** AUDIT-022-ADR-005-W3C-COMPLIANCE
**Finding:** F-373
**Reference:** [AUDIT-022-ADR-005-W3C-COMPLIANCE.md:276-318](docs/researches/post_implementation/AUDIT-022-ADR-005-W3C-COMPLIANCE.md#L276-L318)

**Problem:**
Insufficient test coverage for W3C Trace Context validation (only 1/12 scenarios tested, 8%).

**Impact:**
- MEDIUM - Cannot verify invalid traceparent rejection
- No validation tests (malformed headers)
- No edge case tests (missing parts, invalid chars)
- No error logging tests

**Test Coverage Gaps:**
- ✅ Valid traceparent (1 test)
- ❌ Invalid version (`99-...`)
- ❌ Invalid trace_id length (`00-abc-...`)
- ❌ Invalid trace_id chars (`00-ZZZZ...-...`)
- ❌ All-zeros trace_id (`00-00000000...-...`)
- ❌ Invalid span_id length/chars
- ❌ Invalid flags
- ❌ Missing parts (`00-trace_id`)
- ❌ Extra parts (`00-...-...-...-extra`)
- ❌ Empty string
- ❌ Nil handling

**Recommendation:**
- **R-116**: Add comprehensive W3C tests to `spec/e11y/middleware/request_spec.rb`
- **Priority:** MEDIUM (2-MEDIUM)
- **Effort:** 1-2 hours
- **Rationale:** Verify W3C compliance before production

**Status:** ❌ MISSING (8% coverage)

---

### TEST-005: No Latency Accuracy Tests (±1ms)
**Source:** AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY
**Finding:** F-389
**Reference:** [AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY.md:316-368](docs/researches/post_implementation/AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY.md#L316-L368)

**Problem:**
Latency accuracy (±1ms) NOT tested.

**Impact:**
- MEDIUM - Cannot verify ±1ms accuracy requirement
- Theoretical precision: ±0.001ms (microsecond)
- No empirical tests

**Test Coverage Gaps:**
- ❌ Latency calculation accuracy
- ❌ Timestamp precision validation
- ❌ Sub-millisecond precision handling
- ✅ Histogram tests (buckets, not accuracy)

**Recommendation:**
- **R-127**: Add latency accuracy tests to `spec/e11y/slo/latency_accuracy_spec.rb`
- **Priority:** MEDIUM (2-MEDIUM)
- **Effort:** 2-3 hours
- **Rationale:** Verify ±1ms accuracy requirement

**Status:** ❌ MISSING (No accuracy tests)

---

## 🔗 Cross-References
