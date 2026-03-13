# UC-021 Error Handling/Retry/DLQ: Integration Test Analysis

**Task:** FEAT-5418 - UC-021 Phase 1: Analysis Complete  
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

**Unit Test Coverage:** Good (comprehensive tests for RetryHandler, DeadLetterQueue, error categorization)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for error handling/retry/DLQ

**Gap Analysis:** Integration tests needed for:
1. Retry policies (exponential backoff, max retries, jitter)
2. Exponential backoff (delay increases with each retry)
3. DLQ (failed events stored in DLQ after retries exhausted)
4. Circuit breaker (adapter failures trigger circuit open)
5. Timeout handling (timeouts trigger retries)
6. Error categorization (retriable vs non-retriable errors)
7. Retry rate limiting (C06 - prevent thundering herd)
8. Non-failing tracking (C18 - job succeeds even if tracking fails)
9. DLQ filter (C02 - critical events bypass rate limiting)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/reliability/retry_handler.rb`, `lib/e11y/reliability/dlq/file_storage.rb`, `lib/e11y/adapters/base.rb` (error handling)

**Key Components:**
- `E11y::Reliability::RetryHandler` - Exponential backoff retry logic
- `E11y::Reliability::DLQ::FileStorage` - File-based DLQ storage (JSONL format)
- `E11y::Adapters::Base` - Adapter error handling integration
- Circuit breaker (if implemented) - Per-adapter circuit breaker

**Error Handling Flow:**
1. Event tracked → Adapter.write called
2. Adapter fails → Error raised
3. RetryHandler → Checks if error is retriable
4. RetryHandler → Retries with exponential backoff (max 3 retries)
5. All retries exhausted → Event saved to DLQ
6. DLQ Filter → Checks if event should be saved to DLQ
7. DLQ Storage → Event saved to JSONL file

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
    
    # Retryable errors
    retryable_errors [
      Timeout::Error,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Net::OpenTimeout,
      Net::ReadTimeout
    ]
    
    # Non-retryable errors
    non_retryable_errors [
      E11y::ValidationError,
      E11y::RateLimitError
    ]
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
- Memory adapter for event capture

**Test Structure:**
```ruby
RSpec.describe "Error Handling/Retry/DLQ Integration", :integration do
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
      end
    end
    
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
    FileUtils.rm_rf(dlq_path) if Dir.exist?(dlq_path)
  end
  
  describe "Scenario 1: Retry policies" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Retry Assertions:**
- ✅ Retry count: `expect(retry_count).to eq(3)`
- ✅ Backoff delays: Delays increase exponentially
- ✅ Jitter: Delays have randomness (±10%)

**DLQ Assertions:**
- ✅ DLQ storage: Failed events stored in DLQ
- ✅ Metadata: Error details, retry count, timestamp preserved
- ✅ DLQ filter: Critical events saved, non-critical events dropped

**Error Handling Assertions:**
- ✅ Retriable errors: Network errors, timeouts retried
- ✅ Non-retriable errors: Validation errors, 4xx responses go to DLQ immediately
- ✅ Circuit breaker: Adapter failures trigger circuit open (if implemented)

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Retry Policies

**Objective:** Verify retry policies work correctly (exponential backoff, max retries).

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

### Scenario 2: Exponential Backoff

**Objective:** Verify exponential backoff delays increase correctly.

**Setup:**
- Adapter that fails with transient error
- RetryHandler configured

**Test Steps:**
1. Track event: Track event that triggers adapter failure
2. Measure delays: Measure delays between retries
3. Verify: Delay 1 ≈ 100ms, Delay 2 ≈ 200ms, Delay 3 ≈ 400ms

**Assertions:**
- Delay 1: `expect(delay1).to be_within(20).of(100)` (±20ms tolerance)
- Delay 2: `expect(delay2).to be_within(40).of(200)` (±40ms tolerance)
- Delay 3: `expect(delay3).to be_within(80).of(400)` (±80ms tolerance)

---

### Scenario 3: DLQ

**Objective:** Verify failed events stored in DLQ after retries exhausted.

**Setup:**
- Adapter that always fails
- DLQ storage configured
- RetryHandler configured (max_retries: 3)

**Test Steps:**
1. Track event: Track event that triggers adapter failure
2. Verify: All retries exhausted
3. Verify: Event saved to DLQ
4. Verify: DLQ contains event with metadata (error, retry_count, timestamp)

**Assertions:**
- DLQ storage: `expect(dlq_storage.list.size).to eq(1)`
- Metadata: `expect(dlq_event[:error_class]).to eq("Timeout::Error")`
- Retry count: `expect(dlq_event[:retry_count]).to eq(3)`

---

### Scenario 4: Circuit Breaker

**Objective:** Verify circuit breaker opens after adapter failures (if implemented).

**Setup:**
- Adapter that fails repeatedly
- Circuit breaker configured (if implemented)

**Test Steps:**
1. Track events: Track multiple events that trigger adapter failures
2. Verify: Circuit breaker opens after threshold
3. Verify: Subsequent events fail fast (no retries)

**Assertions:**
- Circuit open: `expect(circuit_breaker.state).to eq(:open)`
- Fast fail: Events fail immediately without retries

**Note:** Circuit breaker may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Timeout Handling

**Objective:** Verify timeouts trigger retries.

**Setup:**
- Adapter that times out
- RetryHandler configured

**Test Steps:**
1. Track event: Track event that triggers timeout
2. Verify: Timeout error detected as retriable
3. Verify: RetryHandler retries timeout errors
4. Verify: Event retried with exponential backoff

**Assertions:**
- Timeout retried: `expect(retry_count).to be > 0`
- Retriable: `expect(retriable_error?(Timeout::Error)).to be(true)`

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

### Scenario 7: Retry Rate Limiting (C06)

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

### Scenario 8: Non-Failing Tracking (C18)

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

### Scenario 9: DLQ Filter (C02)

**Objective:** Verify critical events bypass rate limiting and go to DLQ.

**Setup:**
- Rate limiting configured
- DLQ filter configured (critical events bypass rate limiting)
- Critical event class

**Test Steps:**
1. Track critical event: Track critical event (e.g., payment event)
2. Simulate rate limit: Rate limit exceeded
3. Verify: Critical event bypasses rate limiting
4. Verify: Critical event goes to DLQ if adapter fails

**Assertions:**
- Bypass: Critical event bypasses rate limiting
- DLQ: Critical event in DLQ if adapter fails

**Note:** DLQ filter may not be fully implemented. Tests should verify current state or note limitation.

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

**Test Requirements:**
- DLQ storage configured
- DLQ filter configured (if implemented)
- Event saving verified
- Metadata preservation verified

### 5.3. Adapter Integration

**Integration Point:** `E11y::Adapters::Base`

**Flow:**
1. Event tracked → Adapter.write called
2. Adapter fails → Error raised
3. RetryHandler → Handles retries
4. DLQ → Stores failed events

**Test Requirements:**
- Adapters configured
- Adapter failures simulated
- Error handling verified

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

### 6.3. Retry Rate Limiting

**Status:** ⚠️ **PARTIAL** (C06 Resolution may not be fully implemented)

**Gap:** Retry rate limiting may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.4. Non-Failing Tracking

**Status:** ⚠️ **PARTIAL** (C18 Resolution may not be fully implemented)

**Gap:** Non-failing event tracking in jobs may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.5. DLQ Filter

**Status:** ⚠️ **PARTIAL** (C02 Resolution may not be fully implemented)

**Gap:** DLQ filter (critical events bypass rate limiting) may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderCreated` - Normal events
- `Events::PaymentFailed` - Critical events (for DLQ filter)
- `Events::HealthCheck` - Non-critical events (for DLQ filter)

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
1. ✅ All 9 scenarios implemented and passing
2. ✅ Retry policies tested (exponential backoff, max retries, jitter)
3. ✅ Exponential backoff tested (delays increase correctly)
4. ✅ DLQ tested (failed events stored correctly)
5. ✅ Circuit breaker tested (if implemented, or current state verified)
6. ✅ Timeout handling tested (timeouts trigger retries)
7. ✅ Error categorization tested (retriable vs non-retriable)
8. ✅ Retry rate limiting tested (if implemented, or current state verified)
9. ✅ Non-failing tracking tested (if implemented, or current state verified)
10. ✅ DLQ filter tested (if implemented, or current state verified)
11. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-021:** `docs/use_cases/UC-021-error-handling-retry-dlq.md`
- **ADR-013:** `docs/ADR-013-reliability-error-handling.md`
- **RetryHandler:** `lib/e11y/reliability/retry_handler.rb`
- **DeadLetterQueue:** `lib/e11y/reliability/dlq/file_storage.rb`
- **AUDIT-010:** `docs/researches/post_implementation/AUDIT-010-ADR-013-DLQ-MECHANISM.md`
- **AUDIT-012:** `docs/researches/post_implementation/AUDIT-012-UC-021-RETRY-LOGIC.md`

---

**Analysis Complete:** 2026-01-26
**Next Step:** UC-021 Phase 2: Planning Complete

---

## 🔍 Production Readiness Audit — 2026-03-10

**Audit Date:** 2026-03-10
**Status:** ⚠️ PARTIALLY PRODUCTION-READY — те же критические баги что в ADR-013

### Обновлённый статус (пересекается с ADR-013)

UC-021 полностью перекрывается с ADR-013 по реализации. Все находки ADR-013 применимы здесь:
- **BUG-001:** DLQ Filter signature mismatch — см. ADR-013 Audit Section
- **BUG-002:** RetryRateLimiter not integrated — см. ADR-013 Audit Section

### ⚠️ Покрытие интеграционных тестов UC-021

Из 9 сценариев UC-021:

| Сценарий | Статус |
|----------|--------|
| 1. Retry policies (exponential backoff) | ✅ Tested (5 retry tests) |
| 2. Exponential backoff delays | ✅ Tested |
| 3. DLQ (failed events stored after retries) | ✅ Tested (4 DLQ tests) |
| 4. Circuit breaker (failures trigger open) | ✅ Tested (5 CB tests) |
| 5. Timeout handling | ❌ Missing — `Timeout::Error` не покрыт в integration |
| 6. Non-failing tracking (C18 E2E) | ⚠️ PARTIAL — unit-уровень, не full job context |
| 7. DLQ Replay | ❌ Missing — unit tests есть, integration нет |
| 8. DLQ Filter + Rate Limiter (C02) | ❌ Missing + BROKEN (BUG-001) |
| 9. Retry Rate Limiting (C06) | ❌ Missing + NOT INTEGRATED (BUG-002) |

### Требуемые исправления (TODO)

1. **BUG-001:** Исправить сигнатуру `should_save?` в `DLQ::Filter` или в `Adapters::Base`
2. **BUG-002:** Интегрировать `RetryRateLimiter` в `RetryHandler` или `Adapters::Base`
3. **Добавить integration tests:**
   - Timeout handling (Timeout::Error → retry → DLQ)
   - DLQ Replay E2E (replay event → reaches adapter)
   - C02: critical event bypasses rate limiter → saved to DLQ
   - C06: retry rate is limited (after BUG-002 fix)
   - C18: background job succeeds when tracking fails
