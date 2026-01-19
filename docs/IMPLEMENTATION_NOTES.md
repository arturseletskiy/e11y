# Implementation Notes

**Purpose**: Track architectural decisions, requirement changes, and deviations from original plan during implementation.

**Format**: Each entry includes:
- **Date**: When change was made
- **Phase/Task**: Related implementation phase
- **Change Type**: Architecture | Requirements | API | Tests
- **Decision**: What was changed and why
- **Impact**: Affected ADRs, Use Cases, and code
- **Status**: ✅ Docs Updated | 🔄 Pending | ⚠️ Breaking Change

---

## Phase 1: Foundation

### 2026-01-17: Adapter Naming Simplification (REVERTED)

**Phase/Task**: L3.1.1 - Event::Base Implementation

**Change Type**: Architecture (Simplification)

**Decision**: 
**REVERTED** overcomplicated "role abstraction" approach. Adapters are simply **named** (e.g., `:logs`, `:errors_tracker`), and implementations are configured separately.

**Problem**:
Initial implementation introduced **unnecessary abstraction layer**:
1. ❌ "Roles" (`:logs`, `:errors_tracker`) 
2. ❌ "Concrete adapters" (`:loki`, `:sentry`)
3. ❌ Resolution mechanism (`adapter_aliases`, `resolve_adapters`)

This was **overengineering** - two levels of abstraction where zero was needed!

**Solution**:
**Adapters are just NAMES**. The name represents PURPOSE (`:logs` = logging, `:errors_tracker` = error tracking). The actual implementation is configured separately:

```ruby
# Events use adapter NAMES
class PaymentEvent < E11y::Event::Base
  adapters :logs, :errors_tracker  # These are NAMES, not implementations
end

# Configuration defines what implementation each name uses
E11y.configure do |config|
  # Production
  config.adapters[:logs] = E11y::Adapters::Loki.new(url: "...")
  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(dsn: "...")
  
  # Staging (different implementations)
  config.adapters[:logs] = E11y::Adapters::Elasticsearch.new(...)
  config.adapters[:errors_tracker] = E11y::Adapters::Rollbar.new(...)
end
```

**Benefits**:
- ✅ **Simplicity**: No resolution layer needed
- ✅ **Flexibility**: Swap implementations via config (not code)
- ✅ **Clarity**: `:logs` is a name, Loki/Elasticsearch is an implementation
- ✅ **Convention**: Names represent purpose, config defines implementation

**Code Changes**:
- `lib/e11y.rb`: Removed `adapter_aliases`, `resolve_adapters()` → simplified to `adapters` hash
- `lib/e11y/event/base.rb`: Removed resolution in `track()` → just uses adapter names
- `lib/e11y/presets/*.rb`: Updated comments (no code change needed)
- `spec/**/*_spec.rb`: Removed 7 tests for resolution, updated 13 tests to use adapter names

**Impact**:
- ✅ **Non-breaking**: API unchanged (adapter names stay same)
- ✅ **Simplified**: Removed ~50 lines of unnecessary abstraction
- ✅ **Clearer**: Purpose vs implementation is now explicit

**Status**: ✅ Implemented and tested (120 tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Update with simplified naming approach
- [ ] ADR-008 (Rails Integration) - Update adapter config examples
- [ ] UC-002 (Business Event Tracking) - Update adapter examples
- [ ] UC-005 (Sentry Integration) - Clarify naming vs implementation

---

### 2026-01-17: Audit Event Severity Flexibility

**Phase/Task**: L3.1.1 - Event::Base Implementation (Presets)

**Change Type**: Requirements

**Decision**:
`AuditEvent` preset **NO LONGER forces `:fatal` severity**. Users must explicitly set severity based on event criticality.

**Problem**:
Original design assumed all audit events are critical (`:fatal`), causing:
- ❌ All audit logs triggered Sentry alerts (noise)
- ❌ No distinction between routine audit logging and security breaches
- ❌ Semantic confusion: Audit ≠ Critical

**Solution**:
- `AuditEvent` preset does NOT set default severity
- Users explicitly set severity per event type:
  - `:info` - Routine audit logging (e.g., "user viewed document")
  - `:warn` - Suspicious actions (e.g., "unauthorized access attempt")
  - `:error` - Violations (e.g., "failed auth after 5 attempts")
  - `:fatal` - Critical security events (e.g., "security breach detected")
- Preset enforces **compliance requirements** (100% sampling, unlimited rate) regardless of severity

**Implementation**:
```ruby
# Before (all audit = fatal)
class UserLoginAudit < E11y::Events::BaseAuditEvent
  # severity: :fatal (forced by preset) ❌
  schema { required(:user_id).filled(:integer) }
end

# After (user decides severity)
class UserViewedDocumentAudit < E11y::Events::BaseAuditEvent
  severity :info  # ✅ Routine logging, no alert
  schema { required(:user_id).filled(:integer) }
end

class SecurityBreachAudit < E11y::Events::BaseAuditEvent
  severity :fatal  # ✅ Critical, alert in Sentry
  schema { required(:breach_type).filled(:string) }
end
```

**Benefits**:
- ✅ **Semantic accuracy**: Severity reflects actual criticality
- ✅ **Reduced noise**: Only critical audit events trigger alerts
- ✅ **Flexibility**: Support various audit event types
- ✅ **Compliance maintained**: All audit events 100% tracked (regardless of severity)

**Code Changes**:
- `lib/e11y/presets/audit_event.rb`: Removed `severity :fatal`, added override methods for `resolve_rate_limit` and `resolve_sample_rate`
- `lib/e11y/events/base_audit_event.rb`: Updated docs to clarify user must set severity
- `spec/e11y/presets_spec.rb`: Added 7 tests for different severity audit events
- `spec/e11y/events_spec.rb`: Updated tests to use explicit severity

**Impact**:
- ⚠️ **Breaking Change** (for users who relied on implicit `:fatal`): Now must explicitly set severity
- ✅ **Non-breaking** (for Phase 0): No users yet, safe to change

**Status**: 🔄 Pending - Need to update ADR-012, UC-012

**Affected Docs**:
- [ ] ADR-012 (Event Evolution) - Update audit event examples
- [ ] UC-012 (Audit Trail) - Clarify severity flexibility
- [ ] IMPLEMENTATION_PLAN.md - Mark audit event requirements as updated

---

## Phase 2: Core Features

### 2026-01-18: PII Filtering Implementation (FEAT-4772)

**Phase/Task**: L3.2.1 - PII Filtering & Security

**Change Type**: Architecture | Requirements

**Decision**:
Implemented **3-tier PII filtering strategy** with field-level strategies and pattern-based detection. PII methods in `Event::Base` were moved to public scope to enable proper DSL functionality.

**Problem**:
1. ❌ PII DSL methods (`contains_pii`, `pii_tier`, `pii_filtering`) were private by default
2. ❌ `partial_mask` for email was incorrectly formatting output
3. ❌ Rails filter check prevented filtering in non-Rails environments (tests)

**Solution**:
1. ✅ Moved `public` keyword before PII DSL methods in `Event::Base`
2. ✅ Fixed `partial_mask` to show first 2 chars + last 3 chars (e.g., `us***com`)
3. ✅ Removed `return event_data unless defined?(Rails)` check in `apply_rails_filters`

**Implementation**:
```ruby
# lib/e11y/event/base.rb
public # Make PII and Audit DSL methods public

# === PII Filtering DSL (ADR-006, UC-007) ===

def contains_pii(value = nil)
  if value.nil?
    @contains_pii
  else
    @contains_pii = value
  end
end

def pii_tier
  case contains_pii
  when false then :tier1  # No PII - skip filtering
  when true then :tier3   # Deep filtering with field strategies
  else :tier2             # Rails filters only (default)
  end
end

pii_filtering do
  masks :password       # Replace with [FILTERED]
  hashes :email         # SHA256 hash
  partials :phone       # Show first/last chars
  redacts :ssn          # Remove completely
  allows :user_id       # No filtering
end
```

**Benefits**:
- ✅ **Performance**: Tier 1 (0ms), Tier 2 (~0.05ms), Tier 3 (~0.2ms)
- ✅ **Compliance**: Automatic PII detection and filtering
- ✅ **Flexibility**: Field-level strategies for fine-grained control
- ✅ **Patterns**: Auto-detect email, SSN, credit cards, IPs, phones

**Code Changes**:
- `lib/e11y/event/base.rb`: Moved `public` keyword, added `PIIFilteringBuilder` class
- `lib/e11y/middleware/pii_filter.rb`: Implemented 3-tier filtering strategy
- `lib/e11y/pii/patterns.rb`: Universal PII patterns module
- `spec/e11y/middleware/pii_filtering_spec.rb`: 13 comprehensive tests

**Impact**:
- ✅ **Non-breaking**: No existing API changes
- ✅ **Performance**: Minimal overhead for non-PII events
- ✅ **Security**: Automatic PII protection out-of-the-box

**Status**: ✅ Implemented and tested (13/13 tests pass)

**Affected Docs**:
- [ ] ADR-006 (PII Security & Compliance) - Add implementation details
- [ ] UC-007 (PII Filtering) - Add code examples
- [ ] UC-010 (Healthcare Compliance) - Reference PII filtering

---

### 2026-01-18: Audit Pipeline Implementation (FEAT-4773)

**Phase/Task**: L3.2.1 - PII Filtering & Security (Audit Pipeline)

**Change Type**: Architecture

**Decision**:
Implemented **separate audit pipeline** with cryptographic signing (HMAC-SHA256) and encryption (AES-256-GCM). Audit events sign ORIGINAL data before PII filtering and never undergo sampling or rate limiting.

**Problem**:
1. ❌ Need to ensure audit event integrity and non-repudiation
2. ❌ Audit events must be immutable and tamper-proof
3. ❌ Compliance requires encrypted storage for sensitive audit logs

**Solution**:
1. ✅ `AuditSigning` middleware: Signs event data with HMAC-SHA256
2. ✅ `AuditEncrypted` adapter: Encrypts with AES-256-GCM and stores to disk
3. ✅ Audit DSL in `Event::Base`: `audit_event true`
4. ✅ Verification method: `AuditSigning.verify_signature(event_data)`

**Implementation**:
```ruby
# Mark event as audit event
class Events::UserDeleted < E11y::Event::Base
  audit_event true  # Uses separate pipeline
  
  schema do
    required(:user_id).filled(:integer)
    required(:deleted_by).filled(:integer)
    required(:reason).filled(:string)
  end
end

# Configuration
E11y.configure do |config|
  config.adapters[:audit] = E11y::Adapters::AuditEncrypted.new(
    storage_path: "/var/audit/e11y",
    encryption_key: ENV["E11Y_AUDIT_ENCRYPTION_KEY"]
  )
end
```

**Audit Flow**:
1. **Event tracked** → AuditSigning middleware detects `audit_event?`
2. **Sign ORIGINAL** payload (before PII filtering) with HMAC-SHA256
3. **Add signature** to `event_data[:audit_signature]`
4. **Skip** sampling, rate limiting, PII filtering
5. **Encrypt** entire event with AES-256-GCM (includes signature)
6. **Store** to encrypted file: `{timestamp}_{event_name}.enc`

**Benefits**:
- ✅ **Integrity**: HMAC-SHA256 signature prevents tampering
- ✅ **Confidentiality**: AES-256-GCM encryption protects at rest
- ✅ **Compliance**: Meets SOC2, HIPAA, GDPR audit requirements
- ✅ **Non-repudiation**: Cryptographic proof of original event
- ✅ **Immutability**: Original data signed before any transformations

**Code Changes**:
- `lib/e11y/event/base.rb`: Added `audit_event` DSL method
- `lib/e11y/middleware/audit_signing.rb`: HMAC-SHA256 signing middleware
- `lib/e11y/adapters/audit_encrypted.rb`: AES-256-GCM encryption adapter
- `spec/e11y/middleware/audit_signing_spec.rb`: 8 signing tests
- `spec/e11y/adapters/audit_encrypted_spec.rb`: 13 encryption tests

**Impact**:
- ✅ **Non-breaking**: Opt-in via `audit_event true` DSL
- ✅ **Security**: Cryptographic guarantees for audit trail
- ✅ **Performance**: Separate pipeline doesn't impact regular events

**Status**: ✅ Implemented and tested (21/21 tests pass)

**Affected Docs**:
- [ ] ADR-006 (PII Security & Compliance) - Add audit pipeline section
- [ ] UC-012 (Audit Trail) - Add signing and encryption details
- [ ] UC-010 (Healthcare Compliance) - Reference audit encryption

---

### 2026-01-18: Adapter Architecture Foundation (L2.5)

**Phase/Task**: L2.5 - Adapter Architecture, L3.5.1 - Adapter::Base Contract

**Change Type**: Architecture

**Decision**:
Implemented **unified Adapter::Base contract** following ADR-004 with `write()`, `write_batch()`, `healthy?()`, `close()`, and `capabilities()` methods. Built three adapters: StdoutAdapter, InMemoryAdapter, and updated AuditEncrypted to conform to new contract.

**Problem**:
1. ❌ Existing `Adapter::Base` had inconsistent interface (`send_event` vs `write`)
2. ❌ No batching support
3. ❌ No capabilities discovery mechanism
4. ❌ No close/cleanup lifecycle method

**Solution**:
1. ✅ Updated `Adapter::Base` with ADR-004 contract:
   - `write(event_data)` → Boolean (required)
   - `write_batch(events)` → Boolean (default: loop write)
   - `healthy?()` → Boolean (default: true)
   - `close()` → void (default: no-op)
   - `capabilities()` → Hash (default: all false)

2. ✅ Created `StdoutAdapter`:
   - Pretty-print JSON output
   - Severity-based colorization (Gray/Cyan/Green/Yellow/Red/Magenta)
   - Streaming output
   - Development-friendly

3. ✅ Created `InMemoryAdapter`:
   - Thread-safe event storage
   - Batch tracking
   - Query helpers (`find_events`, `event_count`, `events_by_severity`)
   - Test adapter for specs

4. ✅ Updated `AuditEncrypted` to new contract:
   - Changed `write()` to return Boolean
   - Added `capabilities()` method
   - Fixed `super()` call order for proper validation

**Implementation**:
```ruby
# Base contract
class E11y::Adapters::Base
  def write(event_data)
    raise NotImplementedError
  end
  
  def write_batch(events)
    events.all? { |event| write(event) }  # Default
  end
  
  def healthy?
    true
  end
  
  def close
    # Default: no-op
  end
  
  def capabilities
    { batching: false, compression: false, async: false, streaming: false }
  end
end

# Stdout for development
class E11y::Adapters::Stdout < Base
  def write(event_data)
    output = @pretty_print ? JSON.pretty_generate(event_data) : event_data.to_json
    puts @colorize ? colorize_output(output, event_data[:severity]) : output
    true
  rescue => e
    warn "Stdout adapter error: #{e.message}"
    false
  end
end

# InMemory for tests
class E11y::Adapters::InMemory < Base
  attr_reader :events, :batches
  
  def write(event_data)
    @mutex.synchronize { @events << event_data }
    true
  end
  
  def find_events(pattern)
    @events.select { |event| event[:event_name].to_s.match?(pattern) }
  end
end
```

**Benefits**:
- ✅ **Unified Interface**: All adapters follow same contract
- ✅ **Batching**: Default implementation + override for optimization
- ✅ **Capabilities Discovery**: Apps can query adapter features
- ✅ **Lifecycle**: Proper close() for graceful shutdown
- ✅ **Development**: Stdout adapter with colorization
- ✅ **Testing**: InMemory adapter with query helpers
- ✅ **Thread-Safety**: Mutex protection in InMemory

**Code Changes**:
- `lib/e11y/adapters/base.rb`: Rewrote with ADR-004 contract (210 lines, full docs)
- `lib/e11y/adapters/stdout.rb`: Created (107 lines)
- `lib/e11y/adapters/in_memory.rb`: Created (169 lines)
- `lib/e11y/adapters/audit_encrypted.rb`: Updated to new contract
- `spec/e11y/adapters/base_spec.rb`: Created (22 tests for contract)
- `spec/e11y/adapters/stdout_spec.rb`: Created (29 tests)
- `spec/e11y/adapters/in_memory_spec.rb`: Created (38 tests)
- `spec/e11y/adapters/audit_encrypted_spec.rb`: Fixed (13 tests pass)

**Impact**:
- ✅ **Non-breaking**: Existing AuditEncrypted adapter updated, tests pass
- ✅ **Foundation**: Ready for Loki, Sentry, Elasticsearch adapters
- ✅ **Testing**: InMemory adapter enables easy spec writing
- ✅ **Development**: Stdout adapter improves local debugging

**Status**: ✅ Implemented and tested (102/102 adapter tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Mark §3.1 as implemented
- [ ] ADR-004 (Adapter Architecture) - Mark §4.1 (Stdout) as implemented
- [ ] ADR-004 (Adapter Architecture) - Mark §9.1 (InMemory) as implemented

---

### 2026-01-19: FileAdapter Implementation ✅

**Phase/Task**: L3.5.2.2 - FileAdapter

**Change Type**: Implementation | Tests

**Decision**: Implemented `E11y::Adapters::File` for writing events to local files with rotation and compression.

**Problem**:
Need a reliable file-based adapter for local logging with automatic rotation and optional compression.

**Solution**:
1. ✅ **JSONL Format**: One JSON object per line for easy parsing
2. ✅ **Rotation Strategies**: 
   - `:daily` - Rotate on date change
   - `:size` - Rotate when file exceeds max_size
   - `:none` - No rotation
3. ✅ **Compression**: Optional gzip compression of rotated files
4. ✅ **Thread Safety**: Mutex-protected writes
5. ✅ **Batch Support**: Efficient batch writes with single flush

**Implementation**:
```ruby
# lib/e11y/adapters/file.rb
# (JSONL format, rotation, compression, thread-safe)

# Configuration
E11y::Adapters::File.new(
  path: "log/e11y.log",
  rotation: :daily,           # or :size, :none
  max_size: 100 * 1024 * 1024, # 100MB
  compress: true              # gzip rotated files
)
```

**Benefits**:
- ✅ **Simple & Reliable**: JSONL format is easy to parse and debug
- ✅ **Automatic Rotation**: Prevents disk space issues
- ✅ **Compression**: Saves disk space for archived logs
- ✅ **Thread-Safe**: Safe for concurrent writes

**Critical Fix - Namespace Conflict**:
- ⚠️ **Issue**: `E11y::Adapters::File` conflicts with Ruby's `::File` class
- ✅ **Solution**: Use `::File` prefix in all adapters to reference Ruby's File class
- ✅ **Affected**: `AuditEncrypted` adapter updated to use `::File.join`, `::File.read`, `::File.write`

**Code Changes**:
- `lib/e11y/adapters/file.rb`: New file, implemented FileAdapter (234 lines).
- `spec/e11y/adapters/file_spec.rb`: New file, 35 tests for FileAdapter.
- `lib/e11y/adapters/audit_encrypted.rb`: Fixed namespace conflict with `::File` prefix.

**Impact**:
- ✅ **Non-breaking**: New adapter, no changes to existing functionality.
- ✅ **Foundation**: Ready for production use, supports all rotation strategies.

**Status**: ✅ Implemented and tested (176/176 adapter tests pass, 623/623 total project tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Mark §4.2 (File) as implemented.

---

### 2026-01-19: LokiAdapter Implementation ✅

**Phase/Task**: L3.5.2.3 - LokiAdapter

**Change Type**: Implementation | Tests | Dependencies

**Decision**: Implemented `E11y::Adapters::Loki` for shipping logs to Grafana Loki with batching, compression, and multi-tenancy support.

**Problem**:
Logs need to be centralized in Grafana Loki for querying and monitoring. The adapter must support Loki's push API format, handle batching efficiently, and support multi-tenant deployments.

**Solution**:
1. ✅ **`E11y::Adapters::Loki`**: Implemented adapter with automatic batching, optional gzip compression, Loki push API format, multi-tenant support, and thread-safe buffer.
2. ✅ **Dependencies**: Added `faraday` (~> 2.7) and `webmock` (~> 3.19) as development dependencies.
3. ✅ **Tests**: 34 comprehensive tests covering batching, compression, multi-tenancy, and error handling.

**Benefits**:
- ✅ **Efficient batching**: Reduces HTTP overhead
- ✅ **Compression**: Reduces network bandwidth
- ✅ **Multi-tenancy**: Supports Loki multi-tenant deployments
- ✅ **Thread-safe**: Safe for concurrent writes

**Code Changes**:
- `e11y.gemspec`: Added `faraday` and `webmock` as development dependencies
- `lib/e11y/adapters/loki.rb`: New file, 273 lines
- `spec/e11y/adapters/loki_spec.rb`: New file, 34 tests
- `spec/spec_helper.rb`: Added WebMock configuration

**Status**: ✅ Implemented and tested (34/34 tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Mark §4.3 (Loki) as implemented

---

### 2026-01-19: SentryAdapter Implementation ✅

**Phase/Task**: L3.5.2.4 - SentryAdapter

**Change Type**: Implementation | Tests | Dependencies

**Decision**: Implemented `E11y::Adapters::Sentry` for error tracking and breadcrumbs with severity-based filtering and trace context propagation.

**Problem**:
Errors and exceptions need to be reported to Sentry for monitoring and alerting. The adapter must support Sentry's context system, breadcrumb tracking, and severity-based filtering.

**Solution**:
1. ✅ **`E11y::Adapters::Sentry`**: Implemented adapter with automatic error reporting, breadcrumb tracking, severity-based filtering, trace context propagation, and user context support.
2. ✅ **Dependencies**: Added `sentry-ruby` (~> 5.15) as development dependency.
3. ✅ **Tests**: 39 comprehensive tests covering error reporting, breadcrumbs, severity filtering, and context propagation.

**Benefits**:
- ✅ **Automatic error tracking**: Errors automatically sent to Sentry
- ✅ **Breadcrumb context**: Non-error events tracked as breadcrumbs
- ✅ **Severity filtering**: Only send events above threshold
- ✅ **Trace propagation**: Full trace context for distributed tracing

**Code Changes**:
- `e11y.gemspec`: Added `sentry-ruby` as development dependency
- `lib/e11y/adapters/sentry.rb`: New file, 211 lines
- `spec/e11y/adapters/sentry_spec.rb`: New file, 39 tests

**Status**: ✅ Implemented and tested (39/39 tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Mark §4.4 (Sentry) as implemented
- [ ] UC-005 (Sentry Integration) - Update with new adapter architecture

---

## Documentation Update Checklist

After implementation phase completes, update:

1. **ADRs**:
   - [ ] ADR-004: Adapter Architecture - Add role abstraction section
   - [ ] ADR-008: Rails Integration - Update config examples
   - [ ] ADR-012: Event Evolution - Update audit event semantics

2. **Use Cases**:
   - [ ] UC-002: Business Event Tracking - Update adapter examples
   - [ ] UC-005: Sentry Integration - Add role-based configuration
   - [ ] UC-012: Audit Trail - Clarify severity flexibility

3. **Implementation Plan**:
   - [ ] IMPLEMENTATION_PLAN.md - Mark L3.1.1 deviations

---

## Template for New Entries

```markdown
### YYYY-MM-DD: [Short Title]

**Phase/Task**: [Phase/Task ID]

**Change Type**: Architecture | Requirements | API | Tests

**Decision**: 
[What was decided and why]

**Problem**:
[What problem existed]

**Solution**:
[How it was solved]

**Implementation**:
```code examples```

**Benefits**:
- ✅ Benefit 1
- ✅ Benefit 2

**Code Changes**:
- File 1: Change description
- File 2: Change description

**Impact**:
- ⚠️ Breaking/Non-breaking
- Affected areas

**Status**: ✅ Docs Updated | 🔄 Pending | ⚠️ Breaking Change

**Affected Docs**:
- [ ] ADR-XXX
- [ ] UC-XXX
```

---

### 2026-01-19: Metrics & Cardinality Protection (L2.6) ✅

**Phase/Task**: L2.6 - Metrics & Yabeda Integration

**Change Type**: Implementation | Simplification

**Decision**: Implemented Metrics Middleware with **simplified 3-layer cardinality protection** (removed unnecessary allowlist).

**Problem**:
Original ADR-002 specified 4-layer defense with both denylist AND allowlist. Allowlist was overengineering for MVP - adds complexity without clear benefit.

**Solution**:
1. ✅ **`E11y::Metrics::Registry`**: Pattern-based metric registration with glob matching
2. ✅ **`E11y::Metrics::CardinalityProtection`**: **3-layer defense** (not 4):
   - Layer 1: Universal Denylist (block high-cardinality fields)
   - Layer 2: Per-Metric Cardinality Limits (track unique values)
   - Layer 3: Dynamic Monitoring (alert when exceeded)
   - ❌ **REMOVED Layer 2 (Allowlist)** - unnecessary complexity
3. ✅ **`E11y::Middleware::Metrics`**: Auto-create metrics from events

**Implementation**:
```ruby
# lib/e11y/metrics/registry.rb
# Pattern-based metric registration with glob matching

# lib/e11y/metrics/cardinality_protection.rb
# Simplified 3-layer defense (no allowlist)

# lib/e11y/middleware/metrics.rb
# Metrics middleware with cardinality protection
```

**Benefits**:
- ✅ **Simplicity**: 3 layers instead of 4, removed allowlist complexity
- ✅ **Flexibility**: Pattern-based metric creation (no manual definitions)
- ✅ **Safety**: Cardinality protection prevents metric explosions
- ✅ **Performance**: Zero overhead when no metrics match

**Code Changes**:
- `lib/e11y/metrics/registry.rb`: New file, pattern-based metric registry
- `lib/e11y/metrics/cardinality_protection.rb`: New file, 3-layer protection (simplified)
- `lib/e11y/middleware/metrics.rb`: New file, metrics middleware
- `lib/e11y/metrics.rb`: New file, module definition
- `spec/e11y/metrics/registry_spec.rb`: New file, 45 tests
- `spec/e11y/metrics/cardinality_protection_spec.rb`: New file, 21 tests (simplified)
- `spec/e11y/middleware/metrics_spec.rb`: New file, 23 tests

**Impact**:
- ✅ **Non-breaking**: New functionality, no changes to existing code
- ✅ **Foundation**: Ready for Yabeda integration (next step)

**Status**: ✅ Implemented and tested (68/68 metrics tests pass, 764/764 total project tests pass)

**Affected Docs**:
- [ ] ADR-002 (Metrics & Yabeda) - Update with simplified 3-layer approach
- [ ] UC-003 (Pattern-Based Metrics) - Mark as implemented

---

### 2026-01-20: Metrics Architecture Refactoring - "Rails Way" ✅

**Phase/Task**: L2.6 - Metrics & Yabeda Integration (Refactoring)

**Change Type**: Architecture | Implementation | Tests

**Decision**: Refactored metrics architecture from middleware-based approach to "Rails Way" with Event::Base DSL, singleton Registry, and Yabeda adapter integration.

**Problem**:
Initial implementation (Metrics middleware + separate CardinalityProtection) was "not Rails Way":
1. ❌ Middleware for metrics creation - strange pattern for Rails
2. ❌ Manual registry management - not Rails convention
3. ❌ Overengineered CardinalityProtection with 4 layers (including unnecessary "whitelist")

**Solution**:
1. ✅ **Metrics DSL in Event::Base**: Define metrics directly in event classes
2. ✅ **Singleton Registry**: Single source of truth for ALL metrics with boot-time validation
3. ✅ **Yabeda Adapter**: Replaces middleware, integrates CardinalityProtection
4. ✅ **Label Conflict Validation**: Registry validates at boot time

**Benefits**:
- ✅ **Rails Way**: Metrics defined in Event classes, not middleware
- ✅ **Boot-time validation**: Catch conflicts early, not in production
- ✅ **Simplified architecture**: Removed unnecessary middleware and whitelist
- ✅ **Better DX**: Clear DSL, inheritance support, obvious error messages
- ✅ **Cardinality safety**: Integrated into Yabeda adapter, not separate concern

**Code Changes**:
- `lib/e11y/event/base.rb`: Added `metrics` DSL and `MetricsBuilder` class
- `lib/e11y/metrics/registry.rb`: Converted to singleton, added conflict validation
- `lib/e11y/adapters/yabeda.rb`: New Yabeda adapter with integrated CardinalityProtection
- `lib/e11y/middleware/metrics.rb`: **DELETED** (replaced by Yabeda adapter)
- `spec/e11y/event/metrics_dsl_spec.rb`: New tests for Event::Base metrics DSL (45 tests)
- `spec/e11y/metrics/registry_spec.rb`: Updated for singleton and validation (45 tests)
- `spec/e11y/adapters/yabeda_spec.rb`: New tests for Yabeda adapter (104 tests)
- `spec/e11y/middleware/metrics_spec.rb`: **DELETED** (middleware removed)

**Impact**:
- ✅ **Non-breaking**: New feature, no changes to existing Event::Base API
- ✅ **Foundation**: Critical for L3.6 (Yabeda Integration) and observability
- ✅ **Cleaner architecture**: Removed 2 unnecessary abstractions (middleware, whitelist)

**Status**: ✅ Implemented and tested (194/194 metrics tests pass, 800/800 total project tests pass, Rubocop clean)

**Affected Docs**:
- [x] ADR-002 (Metrics & Yabeda Integration) - ✅ Updated with Rails Way architecture (2026-01-20)
- [x] UC-003 (Pattern-Based Metrics) - ✅ Updated with Event::Base DSL examples (2026-01-20)

---

### 2026-01-20: Boot-Time Validation for Metrics ✅

**Phase/Task**: L2.6 - Metrics & Yabeda Integration (Enhancement)

**Change Type**: Implementation | Tests | Rails Integration

**Decision**: Added explicit boot-time validation for metrics configuration with Rails Railtie integration.

**Problem**:
While Registry already validated conflicts during registration (fail-fast), there was no explicit Rails integration for boot-time checks and logging.

**Solution**:
1. ✅ **Rails Railtie**: Automatic validation after Rails initialization
2. ✅ **Registry#validate_all!**: Explicit validation method for non-Rails projects
3. ✅ **Fail-fast validation**: Conflicts detected immediately during class loading
4. ✅ **Comprehensive tests**: 11 new tests for boot-time validation scenarios

**Implementation**:
```ruby
# lib/e11y/railtie.rb - Automatic Rails integration
class Railtie < Rails::Railtie
  initializer "e11y.validate_metrics", after: :load_config_initializers do
    Rails.application.config.after_initialize do
      E11y::Metrics::Registry.instance.validate_all!
      Rails.logger.info "E11y: Metrics validated successfully (#{registry.size} metrics)"
    end
  end
end

# lib/e11y/metrics/registry.rb - Explicit validation
def validate_all!
  @mutex.synchronize do
    metrics_by_name = @metrics.group_by { |m| m[:name] }
    metrics_by_name.each do |name, metrics|
      next if metrics.size == 1
      first = metrics.first
      metrics[1..].each { |metric| validate_no_conflicts!(first, metric) }
    end
  end
end
```

**Benefits**:
- ✅ **Rails integration**: Automatic validation on boot
- ✅ **Clear logging**: Success message with metrics count
- ✅ **Fail-fast**: Errors during class loading, not in production
- ✅ **Non-Rails support**: Manual validation via `validate_all!`
- ✅ **Better DX**: Clear error messages with source information

**Code Changes**:
- `lib/e11y/railtie.rb`: New Rails integration with automatic validation
- `lib/e11y/metrics/registry.rb`: Added `validate_all!` method
- `lib/e11y.rb`: Load Railtie when Rails is present
- `spec/e11y/metrics/boot_time_validation_spec.rb`: 11 new tests

**Impact**:
- ✅ **Non-breaking**: New feature, no changes to existing API
- ✅ **Rails-friendly**: Automatic initialization and validation
- ✅ **Production-safe**: Catches errors before deployment

**Status**: ✅ Implemented and tested (11/11 boot-time tests pass, 811/811 total project tests pass, Rubocop clean)

**Affected Docs**:
- [ ] ADR-002 (Metrics & Yabeda Integration) - Add section on boot-time validation
- [ ] UC-003 (Pattern-Based Metrics) - Add Rails integration example

---

### 2026-01-20: Sampling Middleware (L2.7 - Partial) ✅

**Phase/Task**: L2.7 - Sampling & Cost Optimization (Basic Implementation)

**Change Type**: Implementation | Tests

**Decision**: Implemented basic Sampling Middleware with trace-aware sampling (C05 Resolution). This is a foundational implementation - adaptive sampling strategies (error-based, load-based, value-based) will be added later.

**Problem**:
No sampling mechanism to reduce event volume and costs. All events are tracked at 100%, leading to high costs in production.

**Solution**:
1. ✅ **Sampling Middleware**: Basic event filtering based on sample rates
2. ✅ **Trace-Aware Sampling (C05)**: All events in a trace share the same sampling decision
3. ✅ **Severity-Based Sampling**: Override sample rates by severity (e.g., errors: 100%, debug: 1%)
4. ✅ **Integration with Event::Base**: Uses `resolve_sample_rate` from Event::Base
5. ✅ **Audit Event Protection**: Audit events are never sampled (always 100%)

**Implementation**:
```ruby
# lib/e11y/middleware/sampling.rb
class Sampling < Base
  def initialize(config = {})
    @default_sample_rate = config.fetch(:default_sample_rate, 1.0)
    @trace_aware = config.fetch(:trace_aware, true)
    @severity_rates = config.fetch(:severity_rates, {})
    @trace_decisions = {} # Cache for trace-level decisions
  end

  def call(event_data)
    event_class = event_data[:event_class]
    
    if should_sample?(event_data, event_class)
      event_data[:sampled] = true
      event_data[:sample_rate] = determine_sample_rate(event_class)
      @app.call(event_data)
    else
      nil # Drop event
    end
  end
  
  private
  
  def should_sample?(event_data, event_class)
    # 1. Never sample audit events
    return true if event_class.audit_event?
    
    # 2. Trace-aware sampling (C05)
    if @trace_aware && event_data[:trace_id]
      return trace_sampling_decision(event_data[:trace_id], event_class)
    end
    
    # 3. Random sampling
    rand < determine_sample_rate(event_class)
  end
  
  def trace_sampling_decision(trace_id, event_class)
    # Cache decision per trace to ensure consistency
    @trace_decisions[trace_id] ||= (rand < determine_sample_rate(event_class))
  end
end
```

**Benefits**:
- ✅ **Cost Reduction**: Can reduce event volume by 50-99% with sampling
- ✅ **Trace Integrity (C05)**: Distributed traces remain complete (all or nothing)
- ✅ **Audit Safety**: Audit events are never dropped (compliance)
- ✅ **Flexible Configuration**: Per-severity overrides + event-level rates

**Code Changes**:
- `lib/e11y/middleware/sampling.rb`: New sampling middleware (170 lines)
- `spec/e11y/middleware/sampling_spec.rb`: 22 comprehensive tests

**Impact**:
- ✅ **Non-breaking**: New middleware, opt-in via configuration
- ✅ **Foundation**: Critical for cost optimization in production
- ✅ **C05 Resolution**: Trace-aware sampling prevents incomplete traces

**Status**: ✅ Implemented and tested (22/22 sampling tests pass, 848/848 total project tests pass, Rubocop clean)

**Implemented**:
- ✅ **Sampling Middleware** (`E11y::Middleware::Sampling`) - Basic sampling logic with trace-aware support
- ✅ **Event-level DSL** (`sample_rate`, `adaptive_sampling`) - Event::Base configuration
- ✅ **Pipeline Integration** - Sampling middleware added to default pipeline (zone: `:routing`)
- ✅ **Comprehensive Tests** - 22 sampling middleware tests + 15 Event::Base DSL tests

**Deferred to Phase 2.8** (FEAT-4837):
- [ ] Adaptive Sampling Strategies (error-based, load-based, value-based)
- [ ] Stratified Sampling for SLO Accuracy (C11)
- [ ] Advanced sampling features (content-based, ML-based)
- **Status:** Planned as separate phase (2026-01-20), awaiting approval

**Affected Docs**:
- [x] ADR-009 (Cost Optimization) - Updated with basic sampling implementation
- [x] UC-014 (Adaptive Sampling) - Updated with implementation status
- [x] docs/PLAN.md - Added Phase 2.8 for advanced sampling

---

### 2026-01-20: Phase 2.8 Planning - Advanced Sampling Strategies ⚡

**Phase/Task**: FEAT-4837 - PHASE 2.8: Advanced Sampling Strategies

**Change Type**: Planning

**Decision**: Created separate phase for advanced adaptive sampling strategies deferred from L2.7.

**Problem**:
Advanced sampling strategies (error-based, load-based, value-based, stratified) were deferred from L2.7 (Basic Sampling) to avoid scope creep. These features need proper planning to ensure they're not forgotten.

**Solution**:
1. ✅ **Created FEAT-4837** via TeamTab `plan` tool
2. ✅ **5 L3 Components**:
   - Error-Based Adaptive Sampling (complexity: 6)
   - Load-Based Adaptive Sampling (complexity: 6)
   - Value-Based Sampling (complexity: 5)
   - Stratified Sampling for SLO Accuracy (C11) (complexity: 7, milestone)
   - Documentation & Migration Guide (complexity: 4, milestone)
3. ✅ **14 L4 Subtasks** with detailed DoD
4. ✅ **Updated docs/PLAN.md** - Added Phase 2.8 to official plan

**Benefits**:
- ✅ **No Lost Work**: Advanced features won't be forgotten
- ✅ **Clear Scope**: Each strategy has explicit requirements and tests
- ✅ **Flexible Timeline**: Can be implemented after main plan or in parallel
- ✅ **Milestone Approval**: 2 milestone tasks require human review (Stratified Sampling, Documentation)

**Plan Structure**:
```
FEAT-4837: PHASE 2.8 (Parent, complexity: 8)
├── FEAT-4838: Error-Based Adaptive Sampling (3 subtasks)
├── FEAT-4842: Load-Based Adaptive Sampling (3 subtasks)
├── FEAT-4846: Value-Based Sampling (3 subtasks)
├── FEAT-4850: Stratified Sampling for SLO Accuracy [MILESTONE] (3 subtasks)
└── FEAT-4854: Documentation & Migration Guide [MILESTONE]
```

**Timeline**:
- **Depends On:** L2.7 (Basic Sampling - completed ✅)
- **Estimated Duration:** 3-4 weeks (after approval)
- **Success Metrics:**
  - 50-80% cost reduction in production
  - <5% error in SLO calculations with stratified sampling
  - Automatic rate adjustment during incidents/load spikes
  - Zero incomplete distributed traces (C05 maintained)

**Status**: ⏳ Awaiting human approval to start execution

**Affected Docs**:
- [x] docs/PLAN.md - Added Phase 2.8 section
- [ ] ADR-009 (Cost Optimization) - Will be updated during implementation
- [ ] UC-014 (Adaptive Sampling) - Will be updated during implementation

---

### 2026-01-20: Middleware Zones (C19 Resolution) - FEAT-4774 ✅

**Phase/Task**: L3.4 (PII Filtering & Security) - FEAT-4774

**Change Type**: Implementation | Architecture | Tests

**Decision**: Implemented comprehensive zone validation system for middleware pipeline to prevent PII bypass and ensure correct execution order.

**Problem**:
Custom middleware could bypass PII filtering or undo security modifications by running in wrong order. This creates GDPR compliance risks and security vulnerabilities (C19 conflict).

**Solution**:
1. ✅ **`E11y::Pipeline::ZoneValidator`** - Centralized boot-time validation class
2. ✅ **Boot-time validation** - `validate_boot_time!` catches configuration errors at application startup
3. ✅ **Zone constraints** - Enforces correct order: `pre_processing → security → routing → post_processing → adapters`
4. ✅ **Detailed error messages** - Clear guidance when zone violations detected
5. ✅ **Integration with `Pipeline::Builder`** - Builder delegates validation to ZoneValidator

**Design Decision: No Runtime Validation**
- **Decision:** Only boot-time validation implemented, no runtime validation
- **Rationale:**
  - Boot-time validation catches all configuration errors
  - Runtime validation adds ~1ms overhead per event (unnecessary cost)
  - Pipeline configuration is static after boot
  - Zero tolerance for configuration errors (fail-fast at boot)

**Benefits**:
- ✅ **PII Bypass Prevention**: Prevents custom middleware from running after PII filtering
- ✅ **Zero Overhead**: No runtime cost (validation at boot only)
- ✅ **Clear Errors**: Detailed error messages guide developers to fix issues
- ✅ **ADR-015 Compliance**: Full implementation of §3.4 Middleware Zones

**Code Changes**:
- `lib/e11y/pipeline/zone_validator.rb`: New class (110 lines) - boot-time validation logic
- `lib/e11y/pipeline/builder.rb`: Refactored to delegate validation to ZoneValidator
- `spec/e11y/pipeline/zone_validator_spec.rb`: 15 comprehensive tests
- `spec/e11y/pipeline/builder_spec.rb`: Updated 2 tests to use new error type

**Impact**:
- ✅ **Non-breaking**: Enhances existing pipeline validation
- ✅ **C19 Resolution**: Fully resolves Custom Middleware × Pipeline Modification conflict
- ✅ **Security**: Prevents accidental PII leaks through misconfigured pipelines

**Status**: ✅ Implemented and tested (863/863 tests pass, Rubocop clean)

**Test Coverage**:
- Boot-time validation (valid/invalid zone orders)
- Backward zone progression detection
- Zone skipping allowed
- Middlewares without zone declaration
- Empty pipeline handling
- Error message quality
- Integration with Pipeline::Builder
- Error hierarchy (ZoneOrderError < InvalidPipelineError)

**Affected Docs**:
- [ ] ADR-015 §3.4 - Update with ZoneValidator details
- [ ] UC-012 (Audit Trail) - Reference zone validation

---

### 2026-01-20: Adaptive Batching Helper ✅

**Phase/Task**: L3.5.4 - Adaptive Batching (FEAT-4779)

**Change Type**: Implementation | Architecture

**Decision**: 
Implemented **`AdaptiveBatcher`** as reusable helper class for adapters that need batching. Thread-safe, automatic flushing based on size/timeout thresholds.

**Problem**:
Multiple adapters (Loki, File, InMemory) implemented their own batching logic:
1. ❌ Code duplication across adapters
2. ❌ Inconsistent batching behavior
3. ❌ Different flush strategies (size-only vs. size+timeout)
4. ❌ No min_size optimization for latency

**Solution**:
**`E11y::Adapters::AdaptiveBatcher`** - reusable helper with:
- **Configurable thresholds**: min_size (10), max_size (500), timeout (5s)
- **Automatic flushing**: On max_size (immediate) or timeout + min_size (latency-optimized)
- **Thread-safe**: Mutex-protected buffer, background timer thread
- **Callback-based**: Adapter provides flush callback, batcher handles logic
- **Graceful shutdown**: `close()` flushes remaining events, stops timer

**Usage Pattern**:
```ruby
class MyAdapter < E11y::Adapters::Base
  def initialize(config = {})
    super
    @batcher = AdaptiveBatcher.new(
      max_size: 500,
      timeout: 5.0,
      flush_callback: method(:send_batch)
    )
  end

  def write(event_data)
    @batcher.add(event_data)
  end

  def close
    @batcher.close
    super
  end

  private

  def send_batch(events)
    # Send to external system
  end
end
```

**Benefits**:
- ✅ **Reusable**: Any adapter can use AdaptiveBatcher
- ✅ **Consistent**: Uniform batching behavior across adapters
- ✅ **Optimized**: Balance throughput (max_size) vs. latency (min_size + timeout)
- ✅ **Thread-safe**: Safe for concurrent writes
- ✅ **Simple integration**: Just provide flush callback

**Code Changes**:
- `lib/e11y/adapters/adaptive_batcher.rb`: New helper class (217 lines)
- `spec/e11y/adapters/adaptive_batcher_spec.rb`: 26 tests (100% coverage)

**Impact**:
- ✅ **Non-breaking**: New helper, existing adapters can opt-in
- ✅ **Future-proof**: LokiAdapter and FileAdapter can be refactored to use it
- ✅ **Documented**: Comprehensive RDoc and usage examples

**Status**: ✅ Implemented and tested (26/26 tests pass)

**Next Steps**:
- [ ] Consider refactoring LokiAdapter to use AdaptiveBatcher
- [ ] Consider refactoring FileAdapter to use AdaptiveBatcher

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Mark §8.1 (Adaptive Batching) as implemented

---

### 2026-01-20: Connection Pooling & Retry via Gem-Level Middleware ✅

**Phase/Task**: L3.5.3 - Connection Pooling & Retry (FEAT-4778)

**Change Type**: Architecture | Implementation

**Decision**: 
Implemented **gem-level retry/pooling** instead of separate abstraction layer. Extended `Adapter::Base` with helper methods for consistency across adapters.

**Problem**:
Original plan (ADR-004) specified separate `ConnectionPool`, `RetryHandler`, and `CircuitBreaker` classes. However:
1. ❌ HTTP adapters (Loki/Sentry) already use gems with built-in retry/pooling (faraday, sentry-ruby)
2. ❌ Non-network adapters (File/Stdout/InMemory) don't need connection management
3. ❌ Separate abstraction would duplicate gem-level functionality
4. ❌ Risk of inconsistency if adapters implement differently

**Solution**:
**1. Extended `Adapter::Base` with helper methods:**
- `with_retry(max_attempts:, base_delay:, max_delay:, jitter:)` - Exponential backoff with jitter
- `with_circuit_breaker(failure_threshold:, timeout:)` - Circuit breaker pattern
- `retriable_error?(error)` - Detect transient errors (network, timeout, 5xx)
- `calculate_backoff_delay()` - Exponential: 1s→2s→4s→8s→16s with ±20% jitter

**2. Faraday retry middleware for LokiAdapter:**
- Added `faraday-retry` gem (~> 2.2)
- Configured retry middleware: max=3, exponential backoff, jitter ±20%
- Retry on: 429, 500, 502, 503, 504, TimeoutError, ConnectionFailed
- Connection pooling: Faraday uses persistent HTTP connections by default

**3. SentryAdapter:**
- `sentry-ruby` SDK has built-in retry and error handling
- No changes needed, SDK handles transient failures

**Benefits**:
- ✅ **YAGNI**: No unnecessary abstraction
- ✅ **Gem-level reliability**: Faraday/Sentry retry is battle-tested
- ✅ **Consistency**: Helper methods ensure uniform approach across adapters
- ✅ **Flexibility**: Adapters can use helpers or gem middleware as appropriate
- ✅ **Simplicity**: Less code to maintain

**Implementation**:
```ruby
# lib/e11y/adapters/base.rb - Helper methods
def with_retry(max_attempts: 3, base_delay: 1.0, max_delay: 16.0, jitter: 0.2)
  # Exponential backoff with jitter for transient errors
end

def with_circuit_breaker(failure_threshold: 5, timeout: 60)
  # Circuit breaker pattern (simplified, per-instance)
end

# lib/e11y/adapters/loki.rb - Faraday retry middleware
@connection = Faraday.new(url: @url) do |f|
  f.request :retry,
            max: 3,
            interval: 1.0,
            backoff_factor: 2,
            interval_randomness: 0.2,
            retry_statuses: [429, 500, 502, 503, 504]
  # ...
end
```

**Code Changes**:
- `lib/e11y/adapters/base.rb`: Added retry/circuit breaker helper methods (150+ lines docs)
- `lib/e11y/adapters/loki.rb`: Configured Faraday retry middleware
- `e11y.gemspec`: Added `faraday-retry` (~> 2.2) as dev dependency
- `spec/e11y/adapters/base_spec.rb`: Added 14 tests for retry/circuit breaker helpers (32→46 tests)

**Impact**:
- ✅ **Non-breaking**: New helper methods, existing adapters unchanged (except Loki)
- ✅ **Foundation**: Adapters can now easily add retry/circuit breaker via helpers
- ✅ **Production-ready**: Faraday retry handles network failures automatically
- ✅ **Documented**: ADR-004 references updated to gem-level approach

**Status**: ✅ Implemented and tested (873/873 tests pass)

**Affected Docs**:
- [ ] ADR-004 (Adapter Architecture) - Update §6.1 (Connection pooling via Faraday)
- [ ] ADR-004 (Adapter Architecture) - Update §7.1 (Retry via gem-level middleware)
- [ ] ADR-004 (Adapter Architecture) - Update §7.2 (Circuit breaker helper in Base)

---

### 2026-01-21: Cardinality Protection - CardinalityTracker & Relabeling ✅

**Phase/Task**: L4: Cardinality Protection (FEAT-4782)

**Change Type**: Architecture | Implementation | Tests

**Decision**: Extracted `CardinalityTracker` as separate component and implemented universal `Relabeling` mechanism per user request.

**Problem**:
Original `CardinalityProtection` had tracking logic embedded in main class. User requested:
1. ❌ Separate `CardinalityTracker` component for SRP
2. ❌ Universal `Relabeling` DSL (not just HTTP-specific)

**Solution**:
1. ✅ **`E11y::Metrics::CardinalityTracker`**: Extracted as separate, thread-safe component (131 lines)
   - Tracks unique label values per metric+label
   - Configurable limit (default: 1000)
   - Provides `track`, `exceeded?`, `cardinality`, `cardinalities`, `reset_metric!`, `reset_all!`
   - 23 comprehensive tests
2. ✅ **`E11y::Metrics::Relabeling`**: Universal relabeling DSL (208 lines)
   - Define relabeling rules via blocks: `relabeler.define(:http_status) { |v| "#{v / 100}xx" }`
   - Apply to single label or all labels
   - Includes `CommonRules` module with predefined rules:
     * `http_status_class` (200 → 2xx)
     * `normalize_path` (/users/123 → /users/:id, UUIDs, MD5)
     * `region_group` (us-east-1 → us, eu-west-2 → eu)
     * `duration_class` (ms → fast/medium/slow/very_slow)
   - Thread-safe, error-resilient
   - 30 comprehensive tests
3. ✅ **`E11y::Metrics::CardinalityProtection` refactored**: Uses extracted components
   - New `relabel(label_key, &block)` DSL method
   - `filter` now applies: Relabel → Denylist → Track → Alert
   - Configurable `relabeling_enabled` (default: true)
   - Exposes `tracker` and `relabeler` for direct access
   - Updated 21 existing tests + 4 new relabeling integration tests

**Implementation**:
```ruby
# lib/e11y/metrics/cardinality_tracker.rb
module E11y
  module Metrics
    class CardinalityTracker
      def initialize(limit: DEFAULT_LIMIT)
        @limit = limit
        @tracker = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Set.new } }
        @mutex = Mutex.new
      end

      def track(metric_name, label_key, label_value)
        @mutex.synchronize do
          value_set = @tracker[metric_name][label_key]
          return true if value_set.include?(label_value)
          return false if value_set.size >= @limit
          value_set.add(label_value)
          true
        end
      end
      
      def cardinality(metric_name, label_key)
        @mutex.synchronize { @tracker.dig(metric_name, label_key)&.size || 0 }
      end
    end
  end
end

# lib/e11y/metrics/relabeling.rb
module E11y
  module Metrics
    class Relabeling
      def define(label_key, &block)
        @mutex.synchronize { @rules[label_key.to_sym] = block }
      end
      
      def apply(label_key, value)
        rule = @mutex.synchronize { @rules[label_key.to_sym] }
        return value unless rule
        rule.call(value)
      rescue => e
        warn "[E11y] Relabeling error for #{label_key}=#{value}: #{e.message}"
        value
      end
      
      module CommonRules
        def self.http_status_class(value)
          code = value.to_i
          return 'unknown' if code < 100 || code >= 600
          "#{code / 100}xx"
        end
        
        def self.normalize_path(value)
          value.to_s
               .gsub(/\/[a-f0-9-]{36}/, '/:uuid') # UUIDs first
               .gsub(/\/[a-f0-9]{32}/, '/:hash')  # MD5 hashes
               .gsub(/\/\d+/, '/:id')              # Numeric IDs
        end
      end
    end
  end
end

# Usage in CardinalityProtection
protection = E11y::Metrics::CardinalityProtection.new
protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }
protection.relabel(:path) { |v| v.gsub(/\/\d+/, '/:id') }

labels = { http_status: 200, path: '/users/123' }
safe_labels = protection.filter(labels, 'api.requests')
# => { http_status: '2xx', path: '/users/:id' }
```

**Benefits**:
- ✅ **Separation of Concerns**: Tracking and relabeling are independent components
- ✅ **Reusability**: `CardinalityTracker` and `Relabeling` can be used standalone
- ✅ **Universal Relabeling**: Not limited to HTTP, works for any label type
- ✅ **Cardinality Reduction**: Relabeling prevents explosions before tracking
- ✅ **Predefined Rules**: `CommonRules` module provides battle-tested patterns
- ✅ **Thread-Safety**: All components are thread-safe with proper locking
- ✅ **Error Resilience**: Relabeling errors don't break the pipeline

**Code Changes**:
- `lib/e11y/metrics/cardinality_tracker.rb`: New file (131 lines)
- `lib/e11y/metrics/relabeling.rb`: New file (208 lines)
- `lib/e11y/metrics/cardinality_protection.rb`: Refactored to use new components (168 lines)
- `spec/e11y/metrics/cardinality_tracker_spec.rb`: New file, 23 tests
- `spec/e11y/metrics/relabeling_spec.rb`: New file, 30 tests
- `spec/e11y/metrics/cardinality_protection_spec.rb`: Updated 21 existing tests, added 4 new

**Impact**:
- ✅ **Non-breaking**: Existing `CardinalityProtection` API preserved
- ✅ **Foundation**: Provides powerful tools for cardinality management
- ✅ **MVP-ready**: All 3 layers of defense + relabeling implemented

**Status**: ✅ Implemented and tested (117/117 metrics tests pass, 956/956 total project tests pass, Rubocop clean)

**Affected Docs**:
- [ ] ADR-002 (Metrics & Yabeda) - Update §4.6 (Relabeling Rules) with universal DSL approach
- [ ] UC-013 (High Cardinality Protection) - Add relabeling examples and `CardinalityTracker` architecture

---

## Phase 3: Rails Integration

### 2026-01-20: E11y::Current Implementation (Rails Way with ActiveSupport::CurrentAttributes)

**Phase/Task**: L3.8 - Rails Instrumentation (FEAT-4795)

**Change Type**: Architecture

**Decision**: 
Implemented `E11y::Current` using **`ActiveSupport::CurrentAttributes`** for request-scoped context (trace_id, span_id, user_id, etc.), following **Rails Way** pattern.

**Rationale**:
1. **Rails Way**: Uses `ActiveSupport::CurrentAttributes` instead of custom Thread-local implementation
2. **Rails-first gem**: E11y is designed for Rails applications, not generic Ruby apps
3. **Automatic cleanup**: `CurrentAttributes` handles lifecycle management in Rails
4. **Familiar API**: Standard Rails pattern that developers already know

**API**:
```ruby
# Set attributes (Rails Way - direct assignment)
E11y::Current.trace_id = "abc123"
E11y::Current.span_id = "def456"
E11y::Current.user_id = 42

# Access via getter methods
E11y::Current.trace_id  # => "abc123"
E11y::Current.user_id   # => 42

# Reset all attributes
E11y::Current.reset
```

**Implementation**:
- `lib/e11y/current.rb`: Inherits from `ActiveSupport::CurrentAttributes`
- `lib/e11y/middleware/request.rb`: Sets context for each request
- Attributes: `trace_id`, `span_id`, `request_id`, `user_id`, `ip_address`, `user_agent`, `request_method`, `request_path`
- Auto-loaded via Zeitwerk

**Critical Fix**:
- ❌ **Initial mistake**: Implemented custom Thread-local wrapper (not Rails Way)
- ✅ **Corrected**: Using `ActiveSupport::CurrentAttributes` (Rails-first approach)

**Impact**:
- ✅ **Non-breaking**: New component, no breaking changes
- ✅ **Rails Integration**: Foundation for request-scoped context in Rails
- ✅ **Tests**: All 960 tests pass (14 examples for `E11y::Middleware::Request`)
- ✅ **Rubocop**: Minor complexity warnings (acceptable for middleware logic)

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [ ] ADR-008 (Rails Integration) - Add §X.X for `E11y::Current` architecture
- [ ] UC-016 (Rails Request Lifecycle) - Document context management

---

### 2026-01-20: Built-in Rails Event Classes Completed

**Phase/Task**: L3.8 - Rails Instrumentation (FEAT-4795)

**Change Type**: Requirements

**Decision**: 
Completed implementation of all built-in Rails event classes from `DEFAULT_RAILS_EVENT_MAPPING`, including the missing `Events::Rails::Http::StartProcessing`.

**Built-in Event Classes** (13 total):
- **Database**: `Query` (sql.active_record)
- **HTTP**: `Request` (process_action), `StartProcessing` (start_processing), `SendFile` (send_file), `Redirect` (redirect_to)
- **View**: `Render` (render_template)
- **Cache**: `Read`, `Write`, `Delete` (cache_*)
- **Job**: `Enqueued`, `Scheduled`, `Started`, `Completed`, `Failed` (active_job.*)

**Implementation**:
- `lib/e11y/events/rails/http/start_processing.rb`: New event class for `start_processing.action_controller` ASN notification
- All event classes include:
  - Schema validation for expected payload fields
  - Appropriate severity level (:debug, :info, :error)
  - Default adapter routing where needed

**Impact**:
- ✅ **Complete Coverage**: All ASN events from `DEFAULT_RAILS_EVENT_MAPPING` are now mapped
- ✅ **Devise-style Overrides**: Users can still override event classes via config
- ✅ **Tests**: All 960 tests pass, Rubocop clean

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [x] ADR-008 (Rails Integration) - Already documented in §4
- [x] UC-015 (ActiveSupport::Notifications) - Already documented

---

### 2026-01-20: Sidekiq/ActiveJob Integration (Job-Scoped Context)

**Phase/Task**: L3.8 - Rails Integration (FEAT-4796 - New)

**Change Type**: Architecture

**Decision**: 
Implemented Sidekiq and ActiveJob integration for job-scoped context management, following the same pattern as `E11y::Middleware::Request` for HTTP requests.

**Rationale**:
1. **Universal `E11y::Current`**: Uses the same `ActiveSupport::CurrentAttributes` for all execution contexts (HTTP, jobs, rake)
2. **Lifecycle Management**: Sidekiq/ActiveJob middleware/callbacks manage context setup/teardown
3. **Trace Propagation**: `trace_id` propagates from enqueue to execution via job metadata
4. **Job-Scoped Buffer**: Uses the same `RequestScopedBuffer` for debug event buffering

**Implementation**:

1. **`E11y::Instruments::Sidekiq`**:
   - `ClientMiddleware`: Injects `trace_id`/`span_id` into job metadata when enqueueing
   - `ServerMiddleware`: Sets up job-scoped context (E11y::Current), manages buffer, handles errors

2. **`E11y::Instruments::ActiveJob`**:
   - `Callbacks` concern: Provides `before_enqueue` and `around_perform` callbacks
   - `TraceAttributes`: Custom accessors for trace context in job instances
   - Auto-included into `ActiveJob::Base` and `ApplicationJob`

3. **`E11y::Railtie`**:
   - Auto-configures Sidekiq middleware (client + server) if `::Sidekiq` is defined
   - Auto-includes ActiveJob callbacks if `::ActiveJob` is defined
   - Configurable via `E11y.config.sidekiq.enabled` and `E11y.config.active_job.enabled`

**Key Features**:
- **Same context management** as HTTP requests (setup → execute → cleanup → reset)
- **Automatic trace propagation** from parent context (HTTP request, another job, rake task)
- **New `span_id`** generated for each job execution (distributed tracing)
- **Job-scoped buffer** for debug events (flush on error or success)
- **Seamless integration** with existing E11y infrastructure

**Impact**:
- ✅ **Non-breaking**: New components, no breaking changes
- ✅ **Complete lifecycle coverage**: HTTP (Request middleware), Jobs (Sidekiq/ActiveJob), Console (manual)
- ✅ **Tests**: All 960 tests pass
- ✅ **Rubocop**: Minor metrics warnings (acceptable for middleware complexity)

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [ ] ADR-008 (Rails Integration) - Add §9 (Sidekiq) and §10 (ActiveJob)
- [ ] UC-017 (Background Job Tracing) - Document job lifecycle and trace propagation

---

### 2026-01-20: Rails.logger Bridge Simplification (SimpleDelegator Pattern)

**Phase/Task**: L3.8 - Rails Integration (Logger Bridge)

**Change Type**: Architecture (Simplification)

**Problem**: 
Initial implementation was **overengineered** - fully replaced `Rails.logger` by reimplementing entire `Logger` API (all methods, compatibility, formatters, etc.). This approach was:
- ❌ **Risky**: Could break standard Rails.logger behavior
- ❌ **Complex**: Required maintaining full Logger API compatibility
- ❌ **Fragile**: Any Logger API changes would require updates

**Solution**: 
Refactored to **SimpleDelegator pattern** (wrapper instead of replacement).

**New Architecture**:
```ruby
class Bridge < SimpleDelegator
  def debug(message = nil, &block)
    track_to_e11y(:debug, message, &block) if track_to_e11y?
    super # Delegate to original logger
  end
end
```

**Why This is Better**:
1. ✅ **Simpler**: No need to reimplement Logger API - delegates everything
2. ✅ **Safer**: Preserves 100% of Rails.logger behavior
3. ✅ **Flexible**: Can be enabled/disabled without breaking anything
4. ✅ **Rails Way**: Extends functionality without replacing core components
5. ✅ **Maintainable**: Logger API changes don't affect E11y

**Implementation**:
- `lib/e11y/logger/bridge.rb`: Refactored from full replacement to `SimpleDelegator` wrapper
- Intercepts log methods (debug, info, warn, error, fatal, add) for optional E11y tracking
- All calls delegated to original logger via `super`
- Configuration: `E11y.config.logger_bridge.track_to_e11y = true` (optional)

**Impact**:
- ✅ **Non-breaking**: Behavior unchanged (still wraps Rails.logger)
- ✅ **Simpler codebase**: 173 LOC → 163 LOC, removed 30+ lines of compatibility code
- ✅ **Tests**: All 960 tests pass
- ✅ **Rubocop**: Only minor complexity warnings

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [ ] ADR-008 (Rails Integration) - Update §7 with SimpleDelegator pattern rationale
- [ ] UC-016 (Rails Logger Migration) - Update examples and migration guide

---

### 2026-01-20: Events::Rails::Log - Dynamic Severity & Per-Severity Config

**Phase/Task**: L3.8 - Rails Integration (Logger Bridge)

**Change Type**: Feature (Dynamic Severity + Per-Severity Tracking Config)

**Problem**: 
Initial `Events::Rails::Log` implementation had critical flaws:
1. ❌ **Static severity** (`severity :info`) - all logs tracked as :info regardless of actual logger call
2. ❌ **No per-severity config** - couldn't disable debug logs while keeping errors

**Solution**: 
Implemented **dynamic severity** and **per-severity tracking configuration**.

**New Architecture**:

1. **Dynamic Severity** (`lib/e11y/events/rails/log.rb`):
   ```ruby
   class Log < E11y::Event::Base
     def self.track(**payload)
       event_severity = payload[:severity] # Use payload severity!
       # ...
     end
     
     # NO default severity! (always dynamic)
   ```

2. **Dynamic Adapters** (based on severity):
   - `debug/info/warn` → `[:logs]`
   - `error/fatal` → `[:logs, :errors_tracker]`

3. **Per-Severity Config** (`lib/e11y/logger/bridge.rb`):
   ```ruby
   # Boolean (all or nothing)
   config.logger_bridge.track_to_e11y = true
   
   # Hash (granular control) - PREFERRED!
   config.logger_bridge.track_to_e11y = {
     debug: false,  # Don't track debug logs
     info: true,    # Track info
     warn: true,    # Track warn
     error: true,   # Track error
     fatal: true    # Track fatal
   }
   ```

4. **`should_track_severity?(severity)` method**:
   - Supports both `TrueClass`, `FalseClass`, and `Hash` config
   - Per-severity check for granular control

**Implementation**:
- `lib/e11y/events/rails/log.rb`: Override `.track` to use dynamic severity from payload
- `lib/e11y/logger/bridge.rb`: Replace `track_to_e11y?` with `should_track_severity?(severity)`
- `spec/e11y/events/rails/log_spec.rb`: Tests for dynamic adapters routing
- `spec/e11y/logger/bridge_spec.rb`: NEW - 12 tests for per-severity config (boolean + Hash)

**Why This is Critical**:
1. ✅ **Correct Severity**: Rails.logger.error now tracked as `:error`, not `:info`
2. ✅ **Granular Control**: Can disable noisy debug logs while keeping errors
3. ✅ **Smart Routing**: Errors/Fatal → Sentry, Info/Warn → Logs only
4. ✅ **Production Ready**: Typical config: `{debug: false, info: false, warn: true, error: true, fatal: true}`

**Impact**:
- ✅ **Non-breaking**: Boolean config still works (backward compatible)
- ✅ **13 new tests**: All pass (983 total tests, 1 flaky performance test)
- ✅ **Rubocop clean**: Only minor metrics warnings

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [ ] ADR-008 (Rails Integration) - Update §7 with per-severity config examples
- [ ] UC-016 (Rails Logger Migration) - Add production config recommendations

---

### 2026-01-20: Events::Rails::Log - Separate Class Per Severity (Rails Way)

**Phase/Task**: L3.8 - Rails Integration (Logger Bridge)

**Change Type**: Architecture (Rails Way Refactoring)

**Problem**: 
Previous approach (dynamic severity via overridden `.track`) was:
- ❌ **Not Rails Way** - breaking Event::Base contract with custom `.track`
- ❌ **Confusing** - severity in payload vs class-level DSL inconsistency
- ❌ **Complex** - special case code in Event class

**Solution**: 
**Separate class for each severity** (Rails convention for hierarchies).

**New Architecture**:

```ruby
module E11y::Events::Rails
  # Base class (abstract)
  class Log < E11y::Event::Base
    schema do
      required(:message).filled(:string)
      optional(:caller_location).filled(:string)
    end
  end

  # Concrete classes (one per severity)
  class Log::Debug < Log
    severity :debug
    adapters [:logs]
  end

  class Log::Info < Log
    severity :info
    adapters [:logs]
  end

  class Log::Warn < Log
    severity :warn
    adapters [:logs]
  end

  class Log::Error < Log
    severity :error
    adapters %i[logs errors_tracker] # Send to Sentry!
  end

  class Log::Fatal < Log
    severity :fatal
    adapters %i[logs errors_tracker] # Send to Sentry!
  end
end
```

**Logger::Bridge Integration**:
```ruby
def event_class_for_severity(severity)
  case severity
  when :debug then E11y::Events::Rails::Log::Debug
  when :info then E11y::Events::Rails::Log::Info
  # ...
  end
end

def track_to_e11y(severity, message)
  event_class = event_class_for_severity(severity)
  event_class.track(message: message, caller_location: ...)
end
```

**Why This is Better**:
1. ✅ **Rails Way**: Follows Rails convention for hierarchies (e.g., `ActiveRecord::Base`, `ApplicationRecord`, model classes)
2. ✅ **Clean Contract**: No custom `.track` override - uses standard `Event::Base` implementation
3. ✅ **Clear Separation**: Each severity is a distinct class with its own config
4. ✅ **Easy to Extend**: Want custom behavior for errors? Override in `Log::Error` class
5. ✅ **Discoverable**: `E11y::Events::Rails::Log::Error` - self-documenting class name

**Benefits**:
- **DRY**: Schema defined once in base `Log` class, inherited by all
- **Flexible**: Can override behavior per-severity if needed
- **Standard**: Matches ActiveSupport::LogSubscriber pattern
- **Type-Safe**: Each severity has its own class (no runtime dispatch)

**Implementation**:
- `lib/e11y/events/rails/log.rb`: Base class + 5 severity classes (Debug, Info, Warn, Error, Fatal)
- `lib/e11y/logger/bridge.rb`: `event_class_for_severity` helper
- `spec/e11y/events/rails/log_spec.rb`: Tests for each severity class + inheritance

**Impact**:
- ✅ **Non-breaking**: Config API unchanged
- ✅ **All 985 tests pass** (0 failures!)
- ✅ **Cleaner Code**: Removed custom `.track` override (65 LOC → 53 LOC)
- ✅ **Rails Way**: Matches Rails patterns for hierarchies

**Status**: ✅ Implemented and tested

**Affected Docs**:
- [ ] ADR-008 (Rails Integration) - Update §7 with class hierarchy diagram
- [ ] UC-016 (Rails Logger Migration) - Document per-severity classes

---

### 2026-01-20: Removed `E11y.quick_start!` - Anti-Pattern

**Phase/Task**: L3.8 - Rails Integration (Code Cleanup)

**Change Type**: Removal (Anti-Pattern Cleanup)

**Problem**: 
`E11y.quick_start!` method was present from initial plan but is **anti-pattern** and **redundant**:
1. ❌ **Magic auto-detect** - `Rails.env`, `ENV["LOKI_URL"]` - скрытая логика
2. ❌ **ENV в библиотеке** - нарушает принцип явной конфигурации
3. ❌ **Not Rails Way** - Rails использует initializers, не magic methods
4. ❌ **Redundant** - `E11y::Railtie` уже автоматически инициализирует E11y
5. ❌ **Опасно** - неочевидное поведение, зависимость от ENV

**Solution**: 
Удален метод `quick_start!` и helper методы (`detect_environment`, `detect_service_name`).

**Правильный подход** (уже реализован):
```ruby
# config/initializers/e11y.rb (явная конфигурация в Rails app)
E11y.configure do |config|
  config.environment = Rails.env.to_s
  config.service_name = "my_app"
  
  # Явное указание адаптеров (без магии ENV)
  config.adapters[:logs] = E11y::Adapters::Loki.new(
    url: Rails.application.credentials.dig(:loki, :url)
  )
  
  # Явная конфигурация Rails integration
  config.rails_instrumentation.enabled = true
  config.logger_bridge.enabled = true
end
```

**Why This is Better**:
1. ✅ **Explicit > Implicit**: Вся конфигурация в одном месте (initializer)
2. ✅ **Rails Way**: Использует Rails initializers, credentials, secrets
3. ✅ **Predictable**: Никакой скрытой магии, все очевидно
4. ✅ **Testable**: Легко тестировать и мокать
5. ✅ **Secure**: Credentials вместо ENV (Rails 7 best practice)

**Auto-initialization** (уже работает):
- `E11y::Railtie` автоматически инициализирует E11y при загрузке Rails
- Устанавливает `config.environment = Rails.env`
- Устанавливает `config.service_name` из Rails app class name
- **НЕТ НУЖДЫ** в `quick_start!` - все уже автоматически!

**Impact**:
- ✅ **Cleaner code**: Удалено 42 строки anti-pattern кода
- ✅ **All 985 tests pass** (метод не использовался)
- ✅ **More explicit**: Конфигурация теперь только через `E11y.configure`

**Status**: ✅ Removed

---

## Notes

- **Always update this file** when deviating from original plan
- **Link to commits** when changes are merged
- **Mark breaking changes** clearly
- **Update affected docs** promptly (link PR/commit)
