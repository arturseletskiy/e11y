# AUDIT-010: ADR-013 Reliability & Error Handling - DLQ Mechanism & Replay

**Audit ID:** AUDIT-010  
**Task:** FEAT-4945  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**ADR Reference:** ADR-013 Reliability & Error Handling §4  
**UC Reference:** UC-021 Dead Letter Queue  
**Related Audit:** AUDIT-005 ADR-004 Error Isolation (F-066, F-067)

---

## 📋 Executive Summary

**Audit Objective:** Verify DLQ (Dead Letter Queue) mechanism including storage with metadata, retrieval API, replay functionality, and cleanup.

**Scope:**
- DLQ storage: Failed events stored with error details, timestamp, retry count
- Retrieval: `E11y.dlq.list` returns failed events, filtering works
- Replay: `E11y.dlq.replay(event_id)` re-emits event
- Cleanup: Old DLQ events purged after N days

**Overall Status:** ⚠️ **PARTIAL** (70%)

**Key Findings:**
- ✅ **EXCELLENT**: DLQ storage with comprehensive metadata (JSONL format)
- ✅ **PASS**: Retrieval API exists (`FileStorage#list` with filters)
- ⚠️ **PARTIAL**: Replay API exists but NOT implemented (TODO stub)
- ✅ **PASS**: Cleanup via rotation and retention (30 days default)
- ❌ **NOT_IMPLEMENTED**: No high-level `E11y.dlq` API (low-level FileStorage only)
- ✅ **EXCELLENT**: Comprehensive test coverage (cross-ref AUDIT-005 F-067)

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) DLQ storage: failed events stored** | ✅ PASS | FileStorage#save implemented | ✅ |
| **(1b) DLQ storage: error details (class, message)** | ✅ PASS | metadata[:error_class, :error_message] | ✅ |
| **(1c) DLQ storage: timestamp** | ✅ PASS | failed_at timestamp (ISO8601) | ✅ |
| **(1d) DLQ storage: retry count** | ✅ PASS | metadata[:retry_count] | ✅ |
| **(2a) Retrieval: E11y.dlq.list returns events** | ⚠️ PARTIAL | FileStorage#list exists, no E11y.dlq API | MEDIUM |
| **(2b) Retrieval: filtering works** | ✅ PASS | Filters: event_name, after, before | ✅ |
| **(3a) Replay: E11y.dlq.replay(event_id) re-emits** | ❌ FAIL | Method exists but NOT implemented (TODO) | HIGH |
| **(3b) Replay: respects rate limits** | ❌ N/A | Replay not implemented | HIGH |
| **(4) Cleanup: old events purged after N days** | ✅ PASS | cleanup_old_files (30 days default) | ✅ |

**DoD Compliance:** 6/9 requirements met (67%), 1 partially met, 2 not implemented

---

## 🔍 AUDIT AREA 1: DLQ Storage

### 1.1. File-Based Storage Implementation

**File:** `lib/e11y/reliability/dlq/file_storage.rb:43-67`

**Cross-Reference:** AUDIT-005 F-066 (DLQ File Storage)

```ruby
def save(event_data, metadata: {})
  event_id = SecureRandom.uuid
  timestamp = Time.now.utc

  dlq_entry = {
    id: event_id,  # ← UUID for replay
    timestamp: timestamp.iso8601(3),  # ← ISO8601 timestamp
    event_name: event_data[:event_name],
    event_data: event_data,  # ← Complete event data
    metadata: metadata.merge(
      failed_at: timestamp.iso8601(3),
      retry_count: metadata[:retry_count] || 0,  # ← Retry count
      error_message: metadata[:error]&.message,  # ← Error message
      error_class: metadata[:error]&.class&.name  # ← Error class
    )
  }

  write_entry(dlq_entry)  # ← Append to JSONL file
  # ...
  event_id
end
```

**Finding:**
```
F-167: DLQ Storage with Metadata (PASS) ✅
───────────────────────────────────────────
Component: lib/e11y/reliability/dlq/file_storage.rb
Requirement: Store failed events with error details, timestamp, retry count
Status: EXCELLENT ✅ (CROSS-REFERENCE: AUDIT-005 F-066)

Evidence:
- Storage format: JSONL (JSON Lines) - append-only
- File path: log/e11y_dlq.jsonl (default, configurable)
- Thread-safe: Mutex + file locking

DLQ Entry Structure:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",  // UUID
  "timestamp": "2026-01-21T10:30:45.123Z",       // ISO8601
  "event_name": "Events::PaymentFailed",
  "event_data": {
    "event_name": "Events::PaymentFailed",
    "payload": { "order_id": "123", "amount": 99.99 },
    "severity": "error",
    "version": 1
  },
  "metadata": {
    "failed_at": "2026-01-21T10:30:45.123Z",     // Timestamp ✅
    "retry_count": 3,                             // Retry count ✅
    "error_message": "Connection timeout",        // Error message ✅
    "error_class": "Timeout::Error",              // Error class ✅
    "adapter": "loki_adapter"                     // Which adapter failed
  }
}
```

Metadata Completeness:
✅ Event ID (UUID) for replay
✅ Timestamp (ISO8601 with ms)
✅ Event name (for filtering)
✅ Complete event data (for replay)
✅ Error class (for analysis)
✅ Error message (for debugging)
✅ Retry count (how many retries before DLQ)
✅ Adapter name (which adapter failed)

Storage Features:
✅ JSONL format (append-only, easy to parse)
✅ Thread-safe (Mutex + flock)
✅ File rotation (at 100MB)
✅ Retention (30 days default)

Verdict: EXCELLENT ✅ (comprehensive metadata storage)
```

---

## 🔍 AUDIT AREA 2: Retrieval API

### 2.1. FileStorage#list Method

**File:** `lib/e11y/reliability/dlq/file_storage.rb:70-103`

```ruby
def list(limit: 100, offset: 0, filters: {})
  entries = []

  return entries unless File.exist?(@file_path)

  File.foreach(@file_path).with_index do |line, index|
    next if index < offset  # ← Pagination: skip offset
    break if entries.size >= limit  # ← Pagination: max limit

    entry = JSON.parse(line, symbolize_names: true)

    # Apply filters:
    next if filters[:event_name] && entry[:event_name] != filters[:event_name]
    next if filters[:after] && Time.parse(entry[:timestamp]) < filters[:after]
    next if filters[:before] && Time.parse(entry[:timestamp]) > filters[:before]

    entries << entry
  end

  entries
end
```

**Finding:**
```
F-168: DLQ Retrieval API (PASS) ✅
───────────────────────────────────
Component: FileStorage#list method
Requirement: Retrieve failed events with filtering
Status: PASS ✅

Evidence:
- list() method exists (file_storage.rb:78-102)
- Pagination: limit, offset
- Filters: event_name, after (timestamp), before (timestamp)

API Examples:

**List all DLQ events:**
```ruby
dlq = E11y::Reliability::DLQ::FileStorage.new
events = dlq.list(limit: 100)
# → Returns up to 100 DLQ entries
```

**Filter by event name:**
```ruby
events = dlq.list(filters: { event_name: "Events::PaymentFailed" })
# → Only payment failures
```

**Filter by time range:**
```ruby
events = dlq.list(filters: {
  after: Time.now - 24.hours,
  before: Time.now
})
# → Events from last 24 hours
```

**Pagination:**
```ruby
# Page 1:
page1 = dlq.list(limit: 50, offset: 0)

# Page 2:
page2 = dlq.list(limit: 50, offset: 50)
```

Limitations:
⚠️ No E11y.dlq.list convenience API
✅ Must instantiate FileStorage directly
⚠️ Limited filter options (no severity, adapter filters)

Verdict: PASS ✅ (retrieval API working, basic filters)
```

### 2.2. Missing High-Level E11y.dlq API

**DoD Expectation:** `E11y.dlq.list` (convenience API)

**Actual:** `E11y::Reliability::DLQ::FileStorage.new.list` (low-level)

**Finding:**
```
F-169: No High-Level E11y.dlq API (FAIL) ❌
────────────────────────────────────────────
Component: E11y module
Requirement: E11y.dlq.list convenience method
Status: NOT_IMPLEMENTED ❌

Issue:
DoD expects high-level API:
```ruby
# Expected (DoD):
E11y.dlq.list(limit: 10)
E11y.dlq.replay(event_id)
```

Actual (low-level):
```ruby
# Current:
storage = E11y::Reliability::DLQ::FileStorage.new
storage.list(limit: 10)
storage.replay(event_id)
```

Impact:
❌ More verbose (must instantiate FileStorage)
❌ Not intuitive (need to know FileStorage class)
⚠️ Acceptable for internal use, poor for public API

Solution (simple delegation):
```ruby
# lib/e11y.rb
module E11y
  def self.dlq
    @dlq ||= DLQApi.new
  end
  
  class DLQApi
    def initialize
      @storage = E11y::Reliability::DLQ::FileStorage.new
    end
    
    def list(limit: 100, offset: 0, filters: {})
      @storage.list(limit:, offset:, filters:)
    end
    
    def replay(event_id)
      @storage.replay(event_id)
    end
    
    def stats
      @storage.stats
    end
  end
end

# Usage:
E11y.dlq.list  # ← Works! ✅
```

Verdict: FAIL ❌ (low-level API only, no convenience wrapper)
```

---

## 🔍 AUDIT AREA 3: Replay Functionality

### 3.1. Replay Method Implementation

**File:** `lib/e11y/reliability/dlq/file_storage.rb:139-157`

```ruby
def replay(event_id)
  entry = find_entry(event_id)
  return false unless entry

  # Re-dispatch event through E11y pipeline
  # TODO: Implement E11y::Pipeline.dispatch  ← NOT IMPLEMENTED!
  # E11y::Pipeline.dispatch(entry[:event_data], metadata: entry[:metadata].merge(replayed: true))

  # For now, just mark as replayed
  increment_metric("e11y.dlq.replayed", event_name: entry[:event_name])
  true
rescue StandardError => e
  increment_metric("e11y.dlq.replay_failed", error: e.class.name)
  false
end
```

**Finding:**
```
F-170: Replay Method NOT Implemented (FAIL) ❌
────────────────────────────────────────────────
Component: FileStorage#replay
Requirement: E11y.dlq.replay(event_id) re-emits event
Status: NOT_IMPLEMENTED ❌

Issue:
Method exists but has TODO comment:
```ruby
# TODO: Implement E11y::Pipeline.dispatch
# E11y::Pipeline.dispatch(entry[:event_data], ...)
```

Current Behavior:
1. Finds DLQ entry by ID ✅
2. Should dispatch to pipeline ❌ (not implemented)
3. Increments metric (fake success)
4. Returns true (misleading!)

Expected Behavior:
```ruby
def replay(event_id)
  entry = find_entry(event_id)
  return false unless entry
  
  # Re-dispatch through pipeline:
  event_class = entry[:event_data][:event_class]
  payload = entry[:event_data][:payload]
  
  # Mark as replayed (prevent DLQ loop):
  event_data = event_class.track(**payload)
  event_data[:metadata] ||= {}
  event_data[:metadata][:replayed] = true
  event_data[:metadata][:original_dlq_id] = event_id
  
  # Send through pipeline:
  E11y::Pipeline.dispatch(event_data)
  
  true
end
```

Risk:
❌ Users calling replay() think it works (returns true)
❌ Events not actually replayed (just metric incremented)
❌ Misleading success indicator

Workaround:
Manually replay from console:
```ruby
# Read DLQ entry:
dlq = E11y::Reliability::DLQ::FileStorage.new
entry = dlq.list(limit: 1).first

# Manually re-emit:
event_class = entry[:event_data][:event_class]
event_class.track(**entry[:event_data][:payload])
```

Verdict: FAIL ❌ (replay exists but not implemented)
```

### 3.2. Batch Replay Implementation

**File:** `lib/e11y/reliability/dlq/file_storage.rb:159-176`

```ruby
def replay_batch(event_ids)
  success_count = 0
  failure_count = 0

  event_ids.each do |event_id|
    if replay(event_id)  # ← Calls replay() (which doesn't work!)
      success_count += 1
    else
      failure_count += 1
    end
  end

  { success_count: success_count, failure_count: failure_count }
end
```

**Finding:**
```
F-171: Batch Replay NOT Implemented (FAIL) ❌
───────────────────────────────────────────────
Component: FileStorage#replay_batch
Requirement: Replay multiple events efficiently
Status: NOT_IMPLEMENTED ❌

Issue:
Depends on replay() method, which is not implemented.

Expected Use Case:
```ruby
# After service recovers from outage:
dlq = E11y::Reliability::DLQ::FileStorage.new

# Find failed events from outage window:
failed_events = dlq.list(filters: {
  after: Time.now - 1.hour,
  event_name: "Events::PaymentProcessed"
})

# Replay all payment events:
event_ids = failed_events.map { |e| e[:id] }
result = dlq.replay_batch(event_ids)
# → success_count: 150, failure_count: 0 ✅
```

Current Behavior:
❌ replay_batch() calls replay()
❌ replay() doesn't actually replay
❌ Returns success counts (fake!)

Verdict: FAIL ❌ (batch replay not functional)
```

---

## 🔍 AUDIT AREA 4: Cleanup and Rotation

### 4.1. File Rotation Implementation

**File:** `lib/e11y/reliability/dlq/file_storage.rb:222-236`

```ruby
def rotate_if_needed
  return unless File.exist?(@file_path)
  return if File.size(@file_path) < @max_file_size_bytes

  @mutex.synchronize do
    # Rotate: log/e11y_dlq.jsonl → log/e11y_dlq.2026-01-21T10:30:45Z.jsonl
    timestamp = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    rotated_path = @file_path.sub(/\.jsonl$/, ".#{timestamp}.jsonl")

    FileUtils.mv(@file_path, rotated_path)

    increment_metric("e11y.dlq.rotated", new_file: rotated_path)
  end
end
```

**Finding:**
```
F-172: DLQ File Rotation (PASS) ✅
───────────────────────────────────
Component: FileStorage#rotate_if_needed
Requirement: Rotate files to prevent unbounded growth
Status: PASS ✅

Evidence:
- Rotation trigger: file size >= 100MB (default, configurable)
- Rotation strategy: timestamp-based naming
- Atomic: FileUtils.mv (atomic rename)

Rotation Example:
```
Current file: log/e11y_dlq.jsonl (99MB)
  ↓ Add events... (size reaches 100MB)
  ↓ rotate_if_needed called
  ↓
Rotated: log/e11y_dlq.2026-01-21T10:30:45Z.jsonl (100MB)
New file: log/e11y_dlq.jsonl (0MB)
```

Benefits:
✅ Prevents single file from growing too large
✅ Timestamp-based naming (easy to identify)
✅ Active file stays small (fast list operations)
✅ Old files can be archived/compressed

Configuration:
```ruby
FileStorage.new(max_file_size_mb: 50)  # ← Rotate at 50MB
```

Verdict: PASS ✅ (rotation working correctly)
```

### 4.2. Cleanup of Old Files

**File:** `lib/e11y/reliability/dlq/file_storage.rb:238-256`

```ruby
def cleanup_old_files
  dir = File.dirname(@file_path)
  base_name = File.basename(@file_path, ".jsonl")

  # Find all rotated files: e11y_dlq.*.jsonl
  pattern = File.join(dir, "#{base_name}.*.jsonl")

  Dir.glob(pattern).each do |file|
    next unless File.file?(file)

    file_age_days = (Time.now - File.mtime(file)) / 86_400

    if file_age_days > @retention_days  # ← Retention: 30 days default
      File.delete(file)
      increment_metric("e11y.dlq.cleaned_up", file: file)
    end
  end
end
```

**Finding:**
```
F-173: DLQ Cleanup and Retention (PASS) ✅
───────────────────────────────────────────
Component: FileStorage#cleanup_old_files
Requirement: Old DLQ events purged after N days
Status: PASS ✅

Evidence:
- Cleanup method: cleanup_old_files()
- Retention: 30 days (default, configurable)
- Called automatically: on each save() operation

Cleanup Logic:
1. Find rotated files: e11y_dlq.*.jsonl
2. Calculate age: (now - mtime) / 86400
3. Delete if age > retention_days

Example:
```
Files:
- log/e11y_dlq.jsonl (current, 10MB, 1 day old)
- log/e11y_dlq.2026-01-20T10:00:00Z.jsonl (100MB, 2 days old)
- log/e11y_dlq.2025-12-15T08:00:00Z.jsonl (100MB, 37 days old)

cleanup_old_files():
- Current file: KEEP (active)
- 2 days old: KEEP (< 30 days)
- 37 days old: DELETE (> 30 days) ✅
```

Configuration:
```ruby
FileStorage.new(retention_days: 90)  # ← Keep for 90 days
```

Trigger:
Called on each save() → incremental cleanup (no batch job needed).

Verdict: PASS ✅ (automatic cleanup with retention)
```

---

## 🔍 AUDIT AREA 5: Test Coverage

### 5.1. DLQ Storage Tests

**Cross-Reference:** AUDIT-005 F-067 (DLQ Test Coverage)

**Test Coverage Summary (from AUDIT-005):**
- Save with metadata: 3 tests ✅
- List with pagination: 2 tests ✅
- List with filters: 3 tests ✅
- File rotation: 2 tests ✅
- Cleanup: 2 tests ✅
- Thread safety: 1 test ✅
- **Total:** 13+ comprehensive tests

**Finding:**
```
F-174: DLQ Test Coverage (PASS) ✅
───────────────────────────────────
Component: spec/e11y/reliability/dlq/file_storage_spec.rb
Requirement: Test DLQ storage, retrieval, cleanup
Status: EXCELLENT ✅ (CROSS-REFERENCE: AUDIT-005 F-067)

Test Scenarios (from AUDIT-005):

**Storage Tests:**
✅ Save with error metadata
✅ Save with retry count
✅ UUID generation
✅ JSONL format

**Retrieval Tests:**
✅ List all events
✅ Pagination (limit, offset)
✅ Filter by event_name
✅ Filter by timestamp range

**Rotation Tests:**
✅ Rotate at max_file_size
✅ Timestamp-based naming

**Cleanup Tests:**
✅ Delete old files (> retention_days)
✅ Keep recent files (< retention_days)

**Thread Safety:**
✅ Concurrent save operations

Verdict: EXCELLENT ✅ (13+ tests, comprehensive coverage)
```

### 5.2. Missing Replay Tests

**Finding:**
```
F-175: No Replay Tests (FAIL) ❌
─────────────────────────────────
Component: spec/e11y/reliability/dlq/
Requirement: Test replay functionality
Status: NOT_TESTED ❌

Issue:
Replay method exists but is not implemented → no tests possible.

Expected Tests (if replay implemented):
```ruby
RSpec.describe "DLQ Replay" do
  it "re-emits event through pipeline" do
    # 1. Save to DLQ:
    event_id = dlq.save(event_data, metadata: {...})
    
    # 2. Replay:
    expect(E11y::Pipeline).to receive(:dispatch).with(
      hash_including(
        event_name: "Events::OrderPaid",
        metadata: hash_including(replayed: true)
      )
    )
    
    dlq.replay(event_id)
  end
  
  it "respects rate limits during replay" do
    # Verify replay doesn't flood adapters
  end
  
  it "marks replayed events to prevent DLQ loop" do
    # Verify replayed events don't go back to DLQ if they fail again
  end
end
```

Current State:
❌ Replay not implemented → can't test

Verdict: FAIL ❌ (no replay tests because replay not implemented)
```

---

## 🎯 Findings Summary

### Implemented Features

```
F-167: DLQ Storage with Metadata (PASS) ✅
F-168: DLQ Retrieval API (PASS) ✅
F-172: DLQ File Rotation (PASS) ✅
F-173: DLQ Cleanup and Retention (PASS) ✅
F-174: DLQ Test Coverage (PASS) ✅
```
**Status:** 5/7 storage/retrieval features working

### Not Implemented

```
F-169: No High-Level E11y.dlq API (FAIL) ❌
F-170: Replay Method NOT Implemented (FAIL) ❌
F-171: Batch Replay NOT Implemented (FAIL) ❌
F-175: No Replay Tests (FAIL) ❌
```
**Status:** Replay functionality incomplete

---

## 🎯 Conclusion

### Overall Verdict

**DLQ Mechanism & Replay Status:** ⚠️ **PARTIAL** (70%)

**What Works:**
- ✅ DLQ storage with comprehensive metadata (UUID, timestamp, error details, retry count)
- ✅ JSONL format (append-only, easy to parse)
- ✅ Retrieval API with pagination and filtering
- ✅ File rotation (at 100MB, timestamp-based)
- ✅ Automatic cleanup (30 days retention)
- ✅ Thread-safe (Mutex + file locking)
- ✅ Comprehensive test coverage for storage (13+ tests)

**What's Missing:**
- ❌ Replay functionality (method exists but TODO stub)
- ❌ High-level `E11y.dlq` convenience API
- ❌ Rate limit respect during replay
- ❌ Replay test coverage

### DoD Compliance Analysis

**DoD Requirements Breakdown:**

1. **DLQ Storage (4/4):** ✅ 100%
   - Error details: ✅ error_class, error_message
   - Timestamp: ✅ failed_at (ISO8601)
   - Retry count: ✅ metadata[:retry_count]
   - Complete event data: ✅ event_data

2. **Retrieval (1/2):** ⚠️ 50%
   - list() method: ✅ Works with filters
   - E11y.dlq.list API: ❌ Not implemented

3. **Replay (0/2):** ❌ 0%
   - replay() method: ❌ TODO stub
   - Rate limit respect: ❌ N/A (not implemented)

4. **Cleanup (1/1):** ✅ 100%
   - Purge after N days: ✅ cleanup_old_files

**Overall Compliance: 6/9 requirements (67%)**

### Production Readiness

**For Event Storage:** ✅ Production-ready
- Failed events captured with complete metadata
- JSONL format is industry standard
- Rotation and cleanup prevent disk exhaustion

**For Event Replay:** ❌ NOT production-ready
- Replay method is placeholder
- No way to recover from outages automatically
- Manual replay required (read DLQ, re-track events)

**Use Case Impact:**

**Scenario: Adapter Outage**
```
14:00 - Loki goes down
14:00-15:00 - 1000 payment events fail
  → All saved to DLQ ✅
  → Metadata complete ✅

15:00 - Loki recovers

Option A (with replay):
  E11y.dlq.replay_batch(event_ids)  # ← Not working!
  → Should replay 1000 events ❌

Option B (manual workaround):
  events = dlq.list(filters: { after: 14:00 })
  events.each do |entry|
    event_class = entry[:event_data][:event_class]
    event_class.track(**entry[:event_data][:payload])
  end
  → Manual replay required ⚠️
```

---

## 📋 Recommendations

### Priority: HIGH (Replay is Critical for Reliability)

**R-044: Implement DLQ Replay Functionality** (HIGH)
- **Urgency:** HIGH (production readiness gap)
- **Effort:** 2-3 days
- **Impact:** Enables automatic recovery from outages
- **Action:** Complete FileStorage#replay implementation

**Implementation Template (R-044):**
```ruby
# lib/e11y/reliability/dlq/file_storage.rb
def replay(event_id, rate_limit: nil)
  entry = find_entry(event_id)
  return false unless entry
  
  # Rate limiting (prevent replay storm):
  if rate_limit
    sleep_time = 1.0 / rate_limit  # events per second → delay
    sleep(sleep_time)
  end
  
  # Extract event data:
  event_class_name = entry[:event_data][:event_name]
  payload = entry[:event_data][:payload]
  
  # Re-track event (goes through full pipeline):
  event_class = event_class_name.constantize
  event_data = event_class.track(**payload)
  
  # Mark as replayed (prevent DLQ loop):
  event_data[:metadata] ||= {}
  event_data[:metadata][:replayed] = true
  event_data[:metadata][:original_dlq_id] = event_id
  event_data[:metadata][:replayed_at] = Time.now.utc.iso8601(3)
  
  # Dispatch through pipeline:
  E11y::Middleware::Routing.new(final_app).call(event_data)
  
  increment_metric("e11y.dlq.replayed", event_name: event_class_name)
  true
rescue StandardError => e
  increment_metric("e11y.dlq.replay_failed", error: e.class.name)
  E11y.logger.error "[E11y] DLQ replay failed for #{event_id}: #{e.message}"
  false
end

# Batch replay with rate limiting:
def replay_batch(event_ids, rate_limit: 100)
  success_count = 0
  failure_count = 0

  event_ids.each do |event_id|
    if replay(event_id, rate_limit: rate_limit)
      success_count += 1
    else
      failure_count += 1
    end
  end

  { success_count: success_count, failure_count: failure_count }
end
```

**R-045: Add High-Level E11y.dlq API** (MEDIUM)
- **Urgency:** MEDIUM (developer experience)
- **Effort:** 1-2 days
- **Impact:** Simplifies DLQ usage
- **Action:** Create delegation wrapper

**Implementation Template (R-045):**
```ruby
# lib/e11y.rb
module E11y
  def self.dlq
    @dlq_api ||= DLQApi.new
  end
  
  class DLQApi
    def initialize
      @storage = config.dlq_storage || E11y::Reliability::DLQ::FileStorage.new
    end
    
    # Delegate to storage:
    delegate :list, :replay, :replay_batch, :stats, to: :@storage
  end
end

# Usage becomes simpler:
E11y.dlq.list(limit: 10)  # ← Clean! ✅
E11y.dlq.replay(event_id)
E11y.dlq.stats
```

**R-046: Add Replay Test Coverage** (HIGH)
- **Urgency:** HIGH (after R-044 implemented)
- **Effort:** 2-3 days
- **Impact:** Verifies replay functionality
- **Action:** Create comprehensive replay tests

**Test Template (R-046):**
```ruby
# spec/e11y/reliability/dlq/replay_spec.rb
RSpec.describe "DLQ Replay" do
  let(:dlq) { E11y::Reliability::DLQ::FileStorage.new }
  
  describe "#replay" do
    it "re-emits event through pipeline" do
      # Save to DLQ:
      event_id = dlq.save(
        { event_name: "Events::OrderPaid", payload: { order_id: 123 } },
        metadata: { error: StandardError.new("Timeout"), retry_count: 3 }
      )
      
      # Replay:
      expect(Events::OrderPaid).to receive(:track).with(order_id: 123)
      expect(dlq.replay(event_id)).to be true
    end
    
    it "marks replayed events" do
      event_id = dlq.save(event_data, metadata: {...})
      
      allow(E11y::Middleware::Routing).to receive(:call) do |event_data|
        expect(event_data[:metadata][:replayed]).to be true
        expect(event_data[:metadata][:original_dlq_id]).to eq(event_id)
      end
      
      dlq.replay(event_id)
    end
    
    it "respects rate limits during replay" do
      event_ids = 10.times.map { dlq.save(event_data) }
      
      start = Time.now
      dlq.replay_batch(event_ids, rate_limit: 10)  # 10 events/sec
      duration = Time.now - start
      
      expect(duration).to be >= 1.0  # 10 events @ 10/sec = 1s minimum
    end
    
    it "handles replay failures gracefully" do
      event_id = dlq.save(event_data)
      
      allow(Events::OrderPaid).to receive(:track).and_raise(StandardError)
      
      expect(dlq.replay(event_id)).to be false
      expect(E11y::Metrics).to have_received(:increment).with("e11y.dlq.replay_failed")
    end
  end
end
```

---

## 📚 References

### Internal Documentation
- **ADR-013:** Reliability & Error Handling §4 (DLQ)
- **UC-021:** Dead Letter Queue
- **Implementation:** lib/e11y/reliability/dlq/file_storage.rb
- **Tests:** spec/e11y/reliability/dlq/file_storage_spec.rb

### Related Audits
- **AUDIT-005:** ADR-004 Error Isolation
  - F-066: DLQ File Storage (EXCELLENT)
  - F-067: DLQ Test Coverage (EXCELLENT)

### External Standards
- **AWS SQS Dead Letter Queues:** Industry standard
- **Kafka Dead Letter Topics:** Alternative approach
- **JSONL Format:** JSON Lines specification

---

**Audit Completed:** 2026-01-21  
**Status:** ⚠️ **PARTIAL** (70% - storage excellent, replay not implemented)

**Critical Assessment:**  
E11y's DLQ storage mechanism is **production-grade** with comprehensive metadata capture (error details, timestamps, retry counts), efficient JSONL format, automatic file rotation (100MB), and retention-based cleanup (30 days). The retrieval API works well with pagination and filtering. However, the **replay functionality is a critical gap** - the `replay()` method exists but is just a TODO stub that doesn't actually re-emit events. This limits operational recovery capabilities after outages. Manual replay is possible by reading DLQ and manually calling `.track()`, but automatic replay via `E11y.dlq.replay(event_id)` is not functional. Additionally, there's no high-level `E11y.dlq` convenience API (must use low-level `FileStorage` class directly). Storage is excellent (100%), but replay needs implementation (0%) to be fully production-ready.

**Auditor Signature:**  
AI Assistant (Claude Sonnet 4.5)  
Audit ID: AUDIT-010
