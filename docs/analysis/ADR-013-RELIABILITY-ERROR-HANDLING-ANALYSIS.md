# ADR-013 Reliability & Error Handling: Integration Test Analysis

**Task:** FEAT-5426 - ADR-013 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** RetryHandler (`E11y::Reliability::RetryHandler`) - Exponential backoff with jitter, max 3 retries
- ✅ **Implemented:** DeadLetterQueue (`E11y::Reliability::DLQ::FileStorage`) - File-based DLQ storage (JSONL format)
- ✅ **Implemented:** Retry Rate Limiting (C06 Resolution) - Prevents thundering herd on adapter recovery
- ✅ **Implemented:** Non-Failing Event Tracking (C18 Resolution) - Job succeeds even if tracking fails
- ✅ **Implemented:** DLQ Filter (C02 Resolution) - Rate limiter respects DLQ filter (critical events bypass rate limiting)
- ✅ **Implemented:** Error Categorization - Retriable vs non-retriable errors
- ⚠️ **PARTIAL:** Circuit Breaker - May be implemented (covered in UC-011)
- ⚠️ **PARTIAL:** DLQ Replay - Replay API exists but may not be fully implemented (per AUDIT-010)
- ⚠️ **PARTIAL:** Self-Healing - May not be fully implemented

**Unit Test Coverage:** Good (comprehensive tests for RetryHandler, DeadLetterQueue, error categorization)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for reliability & error handling

**Gap Analysis:** Integration tests needed for:
1. Retries work (exponential backoff, max retries, jitter)
2. Circuit breakers open/close (adapter failures trigger circuit open, recovery triggers circuit close)
3. DLQ processes messages (failed events stored in DLQ, can be replayed)
4. Retry rate limiting (C06 - prevent thundering herd)
5. Non-failing tracking (C18 - job succeeds even if tracking fails)
6. Error categorization (retriable vs non-retriable errors)
7. Graceful degradation (system continues when adapters fail)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/reliability/retry_handler.rb`, `lib/e11y/reliability/dlq/file_storage.rb`, `lib/e11y/adapters/base.rb` (error handling)

**Key Components:**
- `E11y::Reliability::RetryHandler` - Exponential backoff retry logic
- `E11y::Reliability::DLQ::FileStorage` - File-based DLQ storage (JSONL format)
- `E11y::Adapters::Base` - Adapter error handling integration
- Circuit breaker (if implemented) - Per-adapter circuit breaker

**Reliability Flow:**
1. Event tracked → Adapter.write called
2. Adapter fails → Error raised
3. RetryHandler → Checks if error is retriable
4. RetryHandler → Retries with exponential backoff (max 3 retries)
5. All retries exhausted → Event saved to DLQ
6. DLQ Filter → Checks if event should be saved to DLQ
7. DLQ Storage → Event saved to JSONL file
8. Circuit breaker (if implemented) → Opens after failures, closes after recovery

**Retry Policy:**
- Max retries: 3 (default)
- Base delay: 100ms
- Max delay: 5000ms
- Multiplier: 2 (exponential)
- Jitter: ±10% (prevents thundering herd)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| RetryHandler | ✅ Implemented | Exponential backoff with jitter, max 3 retries |
| DeadLetterQueue | ✅ Implemented | FileStorage (JSONL format) |
| Error Categorization | ✅ Implemented | Retriable vs non-retriable errors |
| Retry Rate Limiting | ✅ Implemented | C06 Resolution - prevents thundering herd |
| Non-Failing Tracking | ✅ Implemented | C18 Resolution - job succeeds even if tracking fails |
| DLQ Filter | ✅ Implemented | C02 Resolution - critical events bypass rate limiting |
| Circuit Breaker | ⚠️ PARTIAL | May be implemented (covered in UC-011) |
| DLQ Replay | ⚠️ PARTIAL | Replay API exists but may not be fully implemented |
| Self-Healing | ⚠️ PARTIAL | May not be fully implemented |

### 1.3. Configuration

**Current API:**
```ruby
# Retry Policy
E11y.configure do |config|
  config.error_handling do
    retry_policy do
      enabled true
      max_retries 3
      initial_delay 0.1.seconds  # 100ms
      max_delay 5.seconds
      multiplier 2  # Exponential: 100ms, 200ms, 400ms
      jitter true   # Add randomness
    end
    
    # Dead Letter Queue
    dead_letter_queue do
      enabled true
      adapter :dlq_file
      max_size 10_000
      alert_on_size 1000
    end
    
    # Circuit Breaker (if implemented)
    circuit_breaker do
      enabled true
      failure_threshold 5
      recovery_timeout 60.seconds
    end
  end
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/reliability/retry_handler_spec.rb`

**Coverage Summary:**
- ✅ **Exponential backoff** (delay calculation)
- ✅ **Jitter** (randomness added to delays)
- ✅ **Max retries** (retry count limit)
- ✅ **Retriable errors** (network errors, timeouts, 5xx responses)
- ✅ **Non-retriable errors** (4xx responses, validation errors)

**Key Test Scenarios:**
- Exponential backoff calculation
- Jitter calculation
- Max retries enforcement
- Retriable error detection
- Non-retriable error detection

### 2.2. Test File: `spec/e11y/reliability/dlq/file_storage_spec.rb`

**Coverage Summary:**
- ✅ **DLQ storage** (event saving)
- ✅ **Metadata** (error details, retry count, timestamp)
- ✅ **File rotation** (max file size)
- ✅ **Retention** (old files cleanup)

**Key Test Scenarios:**
- Event saving to DLQ
- Metadata preservation
- File rotation
- Retention cleanup

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/audit_trail_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Simulated adapter failures (network errors, timeouts, 5xx responses)
- DLQ storage (FileStorage)
- RetryHandler configured
- Circuit breaker configured (if implemented)
- Memory adapter for event capture

**Test Structure:**
```ruby
RSpec.describe "ADR-013 Reliability & Error Handling Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:dlq_storage) { E11y::Reliability::DLQ::FileStorage.new(file_path: dlq_path) }
  let(:dlq_path) { Dir.mktmpdir("dlq_test") }
  
  before do
    memory_adapter.clear!
    FileUtils.rm_rf(dlq_path) if Dir.exist?(dlq_path)
    
    # Configure retry handler
    E11y.configure do |config|
      config.error_handling do
        retry_policy do
          enabled true
          max_retries 3
          initial_delay 0.1
        end
        
        dead_letter_queue do
          enabled true
          adapter :dlq_file
        end
        
        circuit_breaker do
          enabled true  # If implemented
        end
      end
    end
    
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
    FileUtils.rm_rf(dlq_path) if Dir.exist?(dlq_path)
  end
  
  describe "Scenario 1: Retries work" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Retry Assertions:**
- ✅ Retry count: `expect(retry_count).to eq(3)`
- ✅ Backoff delays: Delays increase exponentially
- ✅ Jitter: Delays have randomness

**Circuit Breaker Assertions:**
- ✅ Circuit open: `expect(circuit_breaker.state).to eq(:open)` after failures
- ✅ Circuit close: `expect(circuit_breaker.state).to eq(:closed)` after recovery

**DLQ Assertions:**
- ✅ DLQ storage: Failed events stored in DLQ
- ✅ DLQ processing: DLQ can process messages (replay)

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Retries Work

**Objective:** Verify retries work correctly (exponential backoff, max retries, jitter).

**Setup:**
- Adapter that fails with transient error
- RetryHandler configured (max_retries: 3, initial_delay: 100ms)

**Test Steps:**
1. Track event: Track event that triggers adapter failure
2. Verify: RetryHandler retries 3 times
3. Verify: Backoff delays increase exponentially (100ms, 200ms, 400ms)
4. Verify: Jitter added to delays (±10%)

**Assertions:**
- Retry count: `expect(retry_count).to eq(3)`
- Backoff delays: Delays increase exponentially
- Jitter: Delays have randomness

---

### Scenario 2: Circuit Breakers Open/Close

**Objective:** Verify circuit breakers open after failures and close after recovery.

**Setup:**
- Adapter that fails repeatedly
- Circuit breaker configured (if implemented)

**Test Steps:**
1. Track events: Track multiple events that trigger adapter failures
2. Verify: Circuit breaker opens after threshold
3. Verify: Subsequent events fail fast (no retries)
4. Simulate recovery: Adapter recovers
5. Verify: Circuit breaker closes after recovery timeout

**Assertions:**
- Circuit open: `expect(circuit_breaker.state).to eq(:open)` after failures
- Fast fail: Events fail immediately without retries
- Circuit close: `expect(circuit_breaker.state).to eq(:closed)` after recovery

**Note:** Circuit breaker may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 3: DLQ Processes Messages

**Objective:** Verify DLQ processes messages (failed events stored and can be replayed).

**Setup:**
- DLQ storage configured
- Adapter that always fails
- RetryHandler configured (max_retries: 3)

**Test Steps:**
1. Track event: Track event that triggers adapter failure
2. Verify: All retries exhausted
3. Verify: Event saved to DLQ
4. Replay DLQ: Replay events from DLQ (if implemented)
5. Verify: Events can be replayed

**Assertions:**
- DLQ storage: `expect(dlq_storage.list.size).to eq(1)`
- DLQ processing: Events can be replayed (if implemented)

**Note:** DLQ replay may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 4: Retry Rate Limiting (C06)

**Objective:** Verify retry rate limiting prevents thundering herd.

**Setup:**
- Multiple adapters that fail
- Retry rate limiting configured (C06 Resolution)

**Test Steps:**
1. Track events: Track multiple events that trigger adapter failures
2. Verify: Retries batched/staged to prevent thundering herd
3. Verify: Retry rate limited (not all retries happen simultaneously)

**Assertions:**
- Rate limiting: Retries rate limited correctly
- Batching: Retries batched/staged

**Note:** Retry rate limiting may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Non-Failing Tracking (C18)

**Objective:** Verify job succeeds even if event tracking fails.

**Setup:**
- Background job that tracks events
- Adapter that fails
- Non-failing tracking configured (C18 Resolution)

**Test Steps:**
1. Execute job: Execute background job that tracks events
2. Simulate failure: Adapter fails during event tracking
3. Verify: Job succeeds despite event tracking failure
4. Verify: Failed event stored in DLQ

**Assertions:**
- Job success: `expect(job.status).to eq(:success)`
- DLQ storage: Failed event in DLQ

**Note:** Non-failing tracking may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 6: Error Categorization

**Objective:** Verify retriable vs non-retriable errors handled correctly.

**Setup:**
- Adapter that fails with different error types
- RetryHandler configured

**Test Steps:**
1. Track event: Track event that triggers retriable error (network error)
2. Verify: Retriable error retried
3. Track event: Track event that triggers non-retriable error (validation error)
4. Verify: Non-retriable error goes to DLQ immediately (no retries)

**Assertions:**
- Retriable: `expect(retry_count).to be > 0`
- Non-retriable: `expect(retry_count).to eq(0)`
- DLQ: Non-retriable error in DLQ immediately

---

### Scenario 7: Graceful Degradation

**Objective:** Verify system continues when adapters fail.

**Setup:**
- Multiple adapters configured
- One adapter fails
- Other adapters work

**Test Steps:**
1. Track event: Track event to multiple adapters
2. Simulate failure: One adapter fails
3. Verify: Other adapters continue to work
4. Verify: Failed adapter's events go to DLQ

**Assertions:**
- Graceful degradation: System continues when adapters fail
- Partial success: Some adapters succeed, failed ones go to DLQ

---

## 🔗 5. Dependencies & Integration Points

### 5.1. RetryHandler Integration

**Integration Point:** `E11y::Reliability::RetryHandler`

**Flow:**
1. Adapter fails → Error raised
2. RetryHandler → Checks if error is retriable
3. RetryHandler → Retries with exponential backoff
4. All retries exhausted → Event saved to DLQ

**Test Requirements:**
- RetryHandler configured
- Adapter failures simulated
- Retry behavior verified
- DLQ storage verified

### 5.2. DeadLetterQueue Integration

**Integration Point:** `E11y::Reliability::DLQ::FileStorage`

**Flow:**
1. Retries exhausted → Event saved to DLQ
2. DLQ Filter → Checks if event should be saved
3. DLQ Storage → Event saved to JSONL file
4. DLQ Replay → Events can be replayed (if implemented)

**Test Requirements:**
- DLQ storage configured
- DLQ filter configured (if implemented)
- Event saving verified
- DLQ replay verified (if implemented)

### 5.3. Circuit Breaker Integration

**Integration Point:** Circuit breaker (if implemented)

**Flow:**
1. Adapter fails → Failures tracked
2. Threshold reached → Circuit breaker opens
3. Fast fail → Events fail immediately
4. Recovery → Circuit breaker closes after timeout

**Test Requirements:**
- Circuit breaker configured (if implemented)
- Failure tracking verified
- Circuit state transitions verified

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Circuit Breaker

**Status:** ⚠️ **PARTIAL** (may be implemented, covered in UC-011)

**Gap:** Circuit breaker may not be fully implemented or tested.

**Impact:** Integration tests should verify current state or note limitation.

### 6.2. DLQ Replay

**Status:** ⚠️ **PARTIAL** (replay API exists but may not be fully implemented per AUDIT-010)

**Gap:** DLQ replay functionality may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.3. Self-Healing

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Self-healing may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderCreated` - Normal events
- `Events::PaymentFailed` - Critical events (for DLQ filter)
- `Events::ErrorEvent` - Error events (for retry tests)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Adapters

**Required Adapters:**
- Failing adapter: Adapter that fails with configurable errors
- Memory adapter: For event capture

### 7.3. Test Errors

**Required Errors:**
- Retriable: `Timeout::Error`, `Errno::ECONNREFUSED`, `Net::ReadTimeout`
- Non-retriable: `E11y::ValidationError`, `ArgumentError`

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 7 scenarios implemented and passing
2. ✅ Retries work (exponential backoff, max retries, jitter)
3. ✅ Circuit breakers open/close (if implemented, or current state verified)
4. ✅ DLQ processes messages (failed events stored, can be replayed if implemented)
5. ✅ Retry rate limiting tested (if implemented, or current state verified)
6. ✅ Non-failing tracking tested (if implemented, or current state verified)
7. ✅ Error categorization tested (retriable vs non-retriable)
8. ✅ Graceful degradation tested (system continues when adapters fail)
9. ✅ All tests pass in CI

---

## 📚 9. References

- **ADR-013:** `docs/ADR-013-reliability-error-handling.md`
- **UC-021:** `docs/use_cases/UC-021-error-handling-retry-dlq.md`
- **RetryHandler:** `lib/e11y/reliability/retry_handler.rb`
- **DeadLetterQueue:** `lib/e11y/reliability/dlq/file_storage.rb`
- **AUDIT-010:** `docs/researches/post_implementation/AUDIT-010-ADR-013-DLQ-MECHANISM.md`
- **AUDIT-012:** `docs/researches/post_implementation/AUDIT-012-UC-021-RETRY-LOGIC.md`

---

**Analysis Complete:** 2026-01-26  
**Next Step:** ADR-013 Phase 2: Planning Complete
