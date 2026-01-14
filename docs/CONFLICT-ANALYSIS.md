# E11y Feature Conflict Analysis

**Purpose:** Systematic analysis of potential conflicts between 22 use cases to ensure coherent architecture.

**Status:** ✅ Complete (16 conflicts analyzed, all resolved)

---

## Conflict Analysis Matrix

### ✅ Conflict #1: Request Buffer + Main Buffer

**Features:**
- UC-001: Request-Scoped Debug Buffering
- Core: Main Buffer (200ms flush)

**Potential Conflict:**
- Request buffer holds `:debug` events until request end
- Main buffer flushes every 200ms
- Could debug events get flushed too early?

**Analysis:**
- ✅ **NO CONFLICT**
- Reason: Dual-buffer architecture with routing logic
- `:debug` → Request-scoped buffer (Thread-local)
- `:info+` → Main buffer (Global SPSC)
- Completely independent flush triggers

**Resolution:** Already resolved in architecture

---

### 🟡 Conflict #2: Rate Limiting + Adaptive Sampling

**Features:**
- UC-011: Rate Limiting
- UC-014: Adaptive Sampling

**Potential Conflict:**
- Rate limiting drops events when limit exceeded
- Adaptive sampling also drops/samples events
- Which happens first?

**Analysis:**
```ruby
# Event flow:
Event.track(...)
  → 1. Schema validation
  → 2. PII filtering
  → 3. Rate limiting ← First filter
  → 4. Adaptive sampling ← Second filter
  → 5. Buffer
```

**Issue:**
- If rate limiter drops event, sampling never evaluated
- If sampling drops event, rate limit counter still incremented?

**Resolution:**
```ruby
# Order of operations (pipeline):
def track_event(event)
  # 1. Trace Context (add trace_id, timestamp)
  enrich_with_context!(event)
  
  # 2. Validation (fail fast, uses original class name)
  validate!(event)
  
  # 3. PII Filtering (security first, uses original class name)
  event = pii_filter.filter(event)
  
  # 4. Rate Limiting (protect system, uses original class name)
  return :rate_limited unless rate_limiter.allowed?(event)
  
  # 5. Adaptive Sampling (cost optimization, uses original class name)
  return :sampled unless sampler.should_sample?(event)
  
  # 6. Versioning (LAST! Normalize event_name for adapters)
  normalize_version!(event)
  
  # 7. Route to buffer (adapters receive normalized name)
  route_to_buffer(event)
end
```

**Decision:**
- ✅ Rate limiting BEFORE sampling
- Reason: Rate limiting protects system stability (higher priority)
- Sampling is cost optimization (lower priority)
- Rate limit counter increments BEFORE sampling decision

**Configuration Implications:**
```ruby
config.pipeline_order = [
  :trace_context,
  :validation,
  :pii_filtering,
  :rate_limiting,   # ← After PII filtering
  :adaptive_sampling # ← Second
]
```

---

### 🟡 Conflict #3: PII Filtering + OpenTelemetry Semantic Conventions

**Features:**
- UC-007: PII Filtering
- UC-008: OpenTelemetry Integration

**Potential Conflict:**
- OTel Semantic Conventions require specific fields: `user.id`, `http.client_ip`, `user.email`
- PII filter might mask these fields
- Loss of OTel compatibility?

**Analysis:**
```ruby
# OTel Semantic Conventions fields that might be PII:
- user.id         # Usually NOT PII (opaque ID)
- user.email      # IS PII
- http.client_ip  # IS PII (GDPR)
- user.agent      # Debatable
- geo.country     # NOT PII
- geo.city        # Borderline PII
```

**Issue:**
- PII filter by default masks `email`, `ip_address`
- OTel export expects these fields
- Conflict in GDPR-compliant mode

**Resolution:**
```ruby
# Option 1: Allowlist for OTel (NOT GDPR-compliant)
config.pii_filter do
  allow_fields :user_id, :ip_address  # ← Risky for GDPR
end

# Option 2: Hash/Pseudonymize for OTel (GDPR-compliant)
config.pii_filter do
  pseudonymize_fields :user_id, :ip_address, :email
  
  # user_id: 'usr_123' → 'hashed_a1b2c3d4'
  # ip_address: '192.168.1.1' → 'hashed_e5f6g7h8'
end

# Option 3: Separate PII rules per adapter (RECOMMENDED)
config.pii_filter do
  # Default: strict filtering
  mask_fields :email, :ip_address
  
  # Exception for OTel adapter (if legal basis exists)
  per_adapter :otlp do
    allow_fields :ip_address  # Keep for OTel
    pseudonymize_fields :email  # Hash for OTel
  end
end
```

**Decision:**
- ✅ **Per-adapter PII filtering**
- Reason: Different adapters have different compliance requirements
- Loki/ES: strict filtering (long-term storage)
- OTel: pseudonymization (short-term, telemetry)
- Audit log: keep original (legal requirement)

**Configuration Addition:**
```ruby
config.pii_filter do
  # Default (most adapters)
  mask_fields :email, :ip_address, :phone
  
  # Per-adapter overrides
  adapter_overrides do
    # OTel: pseudonymize (one-way hash)
    adapter :otlp do
      pseudonymize_fields :email, :ip_address
      hash_algorithm :sha256
      hash_salt ENV['PII_HASH_SALT']
    end
    
    # Audit log: keep original (compliance requirement)
    adapter :audit_file do
      skip_filtering true  # No PII filtering for audit
    end
    
    # Sentry: mask everything (external service)
    adapter :sentry do
      mask_fields :email, :ip_address, :phone, :user_id
    end
  end
end
```

---

### 🔴 Conflict #4: Audit Trail Signing + PII Filtering

**Features:**
- UC-012: Audit Trail (cryptographic signing)
- UC-007: PII Filtering

**Potential Conflict:**
- Audit events are cryptographically signed
- PII filtering modifies payload
- If filtering happens AFTER signing → signature invalid
- If filtering happens BEFORE signing → original PII lost (compliance issue?)

**Analysis:**
```ruby
# Scenario 1: Filter BEFORE signing
original_event = { user_email: 'john@example.com' }
filtered_event = { user_email: '[EMAIL]' }
signature = sign(filtered_event)  # ← Signs filtered version

# Problem: Can't verify original event contained real email
# Audit trail doesn't show what ACTUALLY happened

# Scenario 2: Filter AFTER signing
original_event = { user_email: 'john@example.com' }
signature = sign(original_event)  # ← Signs original
filtered_event = { user_email: '[EMAIL]' }

# Problem: verify(filtered_event, signature) → FAILS!
# Signature mismatch
```

**Issue:**
- Audit trail requires original data for compliance
- PII filtering requires masking for GDPR
- Signing requires immutability
- **Fundamental conflict!**

**Resolution:**
```ruby
# Option 1: DON'T filter audit events (RECOMMENDED)
config.audit_trail do
  skip_pii_filtering true  # Audit = compliance > privacy
end

# Audit events stored in separate, access-controlled storage
config.adapters do
  register :audit_file, E11y::Adapters::FileAdapter.new(
    path: 'log/audit',
    permissions: 0600,  # Owner read-only
    encryption: true    # Encrypt at rest
  )
end

# Option 2: Dual storage (original + filtered)
config.audit_trail do
  store_original true    # Original with PII (encrypted)
  store_filtered true    # Filtered for general access
  
  sign_original true     # Sign the original
  sign_filtered false    # Filtered version not signed
end

# Option 3: Selective field signing (complex)
config.audit_trail do
  # Sign only non-PII fields
  sign_fields [:user_id, :old_role, :new_role, :changed_by, :timestamp]
  exclude_from_signature [:user_email, :ip_address]
end
```

**Decision:**
- ✅ **Audit events skip PII filtering (or use per-adapter rules)**
- Reason: Compliance/legal requirements override GDPR
- Justification: "Legal obligation" is valid GDPR basis (Art. 6(1)(c))
- Mitigation: Strict access control + encryption at rest
- PII in audit log = necessary for accountability

**Alternative (Per-Adapter PII Rules):**
```ruby
# Option A: Global skip for audit events (simpler)
config.audit_trail do
  skip_pii_filtering true
end

# Option B: Per-adapter PII rules (more flexible)
class UserPermissionChanged < E11y::AuditEvent
  # This event goes to multiple adapters
  adapters [:audit_file, :elasticsearch, :sentry]
  
  # Different PII rules per adapter
  pii_rules do
    # Audit file: keep all PII (compliance)
    adapter :audit_file do
      skip_filtering true
    end
    
    # Elasticsearch: pseudonymize PII (queryable but privacy-safe)
    adapter :elasticsearch do
      pseudonymize_fields :email, :ip_address
      hash_algorithm :sha256
    end
    
    # Sentry: mask all PII (external service)
    adapter :sentry do
      mask_fields :email, :ip_address, :user_id
    end
  end
end
```

**Per-Adapter PII in Global Config:**
```ruby
config.pii_filter do
  # Default rules (most adapters)
  mask_fields :email, :ip_address, :phone
  
  # Per-adapter overrides
  adapter_overrides do
    # Audit file: no filtering (compliance)
    adapter :audit_file do
      skip_filtering true
    end
    
    # Elasticsearch: pseudonymize
    adapter :elasticsearch do
      pseudonymize_fields :email, :ip_address
    end
    
    # Sentry: strict masking
    adapter :sentry do
      mask_fields :email, :ip_address, :user_id, :session_id
    end
  end
end
```

**Configuration:**
```ruby
# In UC-012 config
config.audit_trail do
  # PII filtering
  skip_pii_filtering true  # ← Audit events not filtered
  
  # Compensating controls
  encryption_at_rest true
  access_control do
    read_access_role :auditor
    read_access_requires_reason true
    read_access_logged true  # Meta-audit
  end
  
  # Retention (balance compliance vs. privacy)
  default_retention 7.years  # SOX, HIPAA
  gdpr_right_to_erasure_override true  # Legal basis
end
```

---

### 🟡 Conflict #5: Cardinality Protection + Metrics Auto-Creation

**Features:**
- UC-013: High Cardinality Protection
- UC-003: Pattern-Based Metrics (auto-creation)

**Potential Conflict:**
- Auto-metrics from events can create high-cardinality labels
- Event payload might contain `user_id`, `order_id` (high cardinality)
- Auto-extraction could violate cardinality limits

**Analysis:**
```ruby
# Example: Auto-metric from event
class OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:user_id).filled(:string)
    required(:status).filled(:string)
  end
  
  # Auto-create metric (naive)
  metric :counter, name: 'orders.created.total'
  
  # Question: Which fields become labels?
  # If auto-extracted: {order_id: ..., user_id: ..., status: ...}
  # → Cardinality explosion!
end
```

**Issue:**
- Auto-metric creation must respect cardinality rules
- Default label extraction could be dangerous

**Resolution:**
```ruby
# Option 1: Explicit label declaration (RECOMMENDED)
class OrderCreated < E11y::Event::Base
  metric :counter,
         name: 'orders.created.total',
         tags: [:status],  # ← EXPLICIT: only safe labels
         # order_id and user_id NOT included
end

# Option 2: Auto-extract with cardinality filtering
config.metrics do
  auto_metrics true
  
  # Auto-label extraction rules
  auto_labels_from do
    # Only extract low-cardinality fields
    safe_fields_only true
    
    # Use cardinality protection allowlist
    allowed_fields_from :cardinality_protection
    
    # Or explicit allowlist
    allowed_fields [:status, :payment_method, :plan_tier]
  end
  
  # Forbidden auto-labels (inherit from cardinality protection)
  forbidden_auto_labels_from :cardinality_protection
end

# Option 3: Runtime validation
config.metrics do
  validate_cardinality_on_creation true
  
  on_cardinality_violation :error  # :error, :warn, :drop_label
end
```

**Decision:**
- ✅ **Explicit label declaration required**
- Reason: Safety by default, no surprises
- Auto-metrics WITHOUT explicit `tags:` → ERROR or WARNING

**Configuration:**
```ruby
config.metrics do
  # Strict mode: require explicit labels
  require_explicit_labels true  # ← No auto-extraction
  
  # If auto-extraction enabled (legacy/convenience)
  auto_label_extraction do
    enabled false  # Disabled by default
    
    # If enabled, use allowlist
    allowed_fields :status, :severity, :env, :region
    
    # Inherit from cardinality protection
    respect_cardinality_rules true
  end
  
  # Validation
  validate_labels_on_metric_creation true
  on_forbidden_label :error  # Fail fast
end
```

---

### 🟢 Conflict #6: Circuit Breaker + Multi-Adapter Routing

**Features:**
- Circuit Breaker (adapter health protection)
- UC-002: Per-Event Adapter Overrides

**Potential Conflict:**
- Event configured to send to multiple adapters
- Circuit opens for one adapter
- Should event still go to other adapters?

**Analysis:**
```ruby
# Example:
class CriticalError < E11y::Event::Base
  adapters [:loki, :elasticsearch, :sentry, :pagerduty]
end

# Scenario:
# - PagerDuty circuit opens (too many failures)
# - Event tracked
# - Should it still go to Loki, ES, Sentry?
```

**Issue:**
- Circuit breaker is per-adapter
- Events can target multiple adapters
- Partial delivery semantics?

**Resolution:**
```ruby
# Option 1: Independent circuits (RECOMMENDED)
# - Each adapter has its own circuit
# - Event sent to all adapters with CLOSED circuits
# - Skipped for adapters with OPEN circuits

def flush_to_adapters(event, adapters)
  results = {}
  
  adapters.each do |adapter|
    circuit = circuit_breakers[adapter]
    
    if circuit.open?
      results[adapter] = :circuit_open
      next
    end
    
    begin
      circuit.call { adapter.write(event) }
      results[adapter] = :success
    rescue => e
      results[adapter] = :failure
    end
  end
  
  results
end

# Option 2: Fallback adapter
config.circuit_breaker do
  fallback_adapter :file
  fallback_on_all_circuits_open true
end

# If ALL circuits open → send to fallback

# Option 3: Fail-fast mode (optional)
config.circuit_breaker do
  fail_fast_if_any_circuit_open false  # default: false
end
# If true: event fails if ANY circuit is open
```

**Decision:**
- ✅ **Independent circuits, partial delivery OK**
- Reason: Availability over consistency
- Better to deliver to 3/4 adapters than 0/4
- Fallback adapter (file) used if all circuits open

**Configuration:**
```ruby
config.circuit_breaker do
  per_adapter true  # ← Each adapter has own circuit
  
  # Partial delivery
  allow_partial_delivery true
  
  # Fallback
  fallback_adapter :file
  use_fallback_when :all_circuits_open  # or :any_circuit_open
  
  # Alerting
  on_circuit_open do |adapter_name|
    Events::CircuitBreakerOpened.track(adapter: adapter_name)
  end
end
```

**No conflict:** Circuits are independent, partial delivery is acceptable.

---

### 🟡 Conflict #7: Compression + Payload Minimization

**Features:**
- UC-015: Cost Optimization (compression)
- UC-015: Cost Optimization (payload minimization)

**Potential Conflict:**
- Payload minimization removes/truncates fields
- Compression reduces byte size
- Which happens first?

**Analysis:**
```ruby
# Option 1: Minimize THEN compress
payload = { very_long_field: 'x' * 10000 }
minimized = truncate(payload)  # { very_long_field: 'x' * 1000 }
compressed = gzip(minimized)

# Option 2: Compress THEN minimize (doesn't make sense)
# Can't minimize after compression

# Option 3: Compress WITHOUT minimizing
payload = { very_long_field: 'x' * 10000 }
compressed = gzip(payload)  # Compression is very effective
```

**Issue:**
- Order matters
- Minimization is destructive (data loss)
- Compression is reversible (no data loss)
- Which is more cost-effective?

**Analysis:**
```ruby
# Test case:
payload = {
  message: 'Error message' * 100,  # Repetitive
  backtrace: ['line 1', 'line 2', ...] * 100  # 10KB
}

# Scenario A: Minimize THEN compress
minimized = truncate(payload, max: 1000)  # 1KB
compressed = gzip(minimized)  # ~200 bytes (80% reduction)

# Scenario B: Compress WITHOUT minimize
compressed = gzip(payload)  # ~1KB (90% reduction!)
# Compression is BETTER for repetitive data

# Scenario C: Both
minimized = truncate(payload, max: 5000)  # 5KB
compressed = gzip(minimized)  # ~500 bytes
```

**Decision:**
- ✅ **Payload minimization BEFORE compression**
- Reason: 
  - Minimization reduces processing (parsing, indexing) on backend
  - Compression reduces network/storage bytes
  - Both valuable, minimize first (smaller compressed payload)

**Pipeline Order:**
```ruby
# In adapter write:
def write_batch(events)
  # 1. Payload minimization
  events = payload_minimizer.minimize(events)
  
  # 2. Serialization (JSON)
  payload = JSON.generate(events)
  
  # 3. Compression
  payload = compressor.compress(payload) if compression_enabled?
  
  # 4. Send
  http_client.post(url, body: payload)
end
```

**Configuration:**
```ruby
config.cost_optimization do
  # Order is implicit in processing pipeline
  payload_minimization { enabled true }
  compression { enabled true }
  
  # Note: Minimization happens per-event
  # Compression happens per-batch (more efficient)
end
```

**No major conflict:** Order is logical and deterministic.

---

### 🟡 Conflict #8: Tiered Storage + Retention Tagging

**Features:**
- UC-015: Tiered Storage (hot/warm/cold)
- UC-015: Retention Tagging

**Potential Conflict:**
- Tiered storage defines retention: hot=7d, warm=30d, cold=1y
- Retention tagging adds `retention_days` to event
- Which takes precedence?

**Analysis:**
```ruby
# Example:
class AuditEvent < E11y::Event::Base
  retention 7.years  # Per-event retention (UC-012)
end

config.cost_optimization.tiered_storage do
  hot_tier duration: 7.days
  warm_tier duration: 30.days
  cold_tier duration: 1.year  # ← Conflict! Event wants 7 years
end
```

**Issue:**
- Event-level retention vs. global tiered storage
- Tiered storage is cost-optimization strategy
- Event retention is compliance requirement
- Compliance > Cost (always)

**Resolution:**
```ruby
# Option 1: Per-event retention OVERRIDES tiered storage (RECOMMENDED)
# - Audit events bypass tiered storage
# - Go directly to long-term adapter

class AuditEvent < E11y::Event::Base
  retention 7.years
  
  # Override adapters (bypass tiered storage)
  adapters [:audit_file, :s3_glacier]  # Long-term only
end

# Option 2: Tiered storage respects event retention
config.cost_optimization.tiered_storage do
  respect_event_retention true  # ← Check event.retention
  
  # If event.retention > cold_tier.duration → use event retention
  # Else use tiered storage rules
end

# Option 3: Separate tiered storage per event type
config.cost_optimization.tiered_storage do
  default_tiers do
    hot 7.days
    warm 30.days
    cold 1.year
  end
  
  # Override for specific event types
  tiers_for 'audit.*' do
    hot 30.days
    warm 1.year
    cold 7.years
  end
end
```

**Decision:**
- ✅ **Event-level retention takes precedence**
- Reason: Compliance > Cost optimization
- Tiered storage applies to events WITHOUT explicit retention

**Configuration:**
```ruby
config.cost_optimization.tiered_storage do
  enabled true
  
  # Respect per-event retention
  respect_event_retention true  # ← Check event class retention
  
  # Default tiers (for events without explicit retention)
  default_tiers do
    hot duration: 7.days, adapters: [:loki, :elasticsearch]
    warm duration: 30.days, adapters: [:s3_standard]
    cold duration: 1.year, adapters: [:s3_glacier]
  end
  
  # Events with explicit retention bypass tiered storage
  # (They define their own adapter routing)
end

# Retention tagging complements tiered storage
config.cost_optimization.retention_tagging do
  enabled true
  
  # Tag events with their retention policy
  tag_with_retention true
  retention_tag_key 'retention_days'
  
  # Downstream systems (ES, S3) can use this tag for ILM
end
```

**No major conflict:** Event retention > tiered storage (hierarchy).

---

### 🟢 Conflict #9: Background Job Tracing + Adaptive Sampling

**Features:**
- UC-010: Background Job Tracking
- UC-014: Adaptive Sampling

**Potential Conflict:**
- Background jobs are traced (trace_id propagated)
- Sampling might drop job events
- If parent HTTP request sampled but job not → broken trace
- If job sampled but parent not → orphaned spans

**Analysis:**
```ruby
# Scenario:
# 1. HTTP request arrives (trace_id: abc123)
# 2. Sampler decides: sample_rate = 10% → NOT sampled
# 3. HTTP request enqueues job (trace_id: abc123)
# 4. Job executes → should it be sampled?

# Option A: Job uses same sample rate (10%) → probably not sampled
# Result: Consistent, but trace incomplete

# Option B: Job always sampled if trace exists → sampled
# Result: Job event exists, but no parent HTTP event (confusing)
```

**Issue:**
- Trace sampling should be consistent across services/jobs
- Head-based sampling (decide at HTTP entry) vs. tail-based sampling

**Resolution:**
```ruby
# Option 1: Trace-consistent sampling (RECOMMENDED)
# - Sample decision made at trace creation (HTTP request)
# - Decision propagated to all child spans (jobs, API calls)
# - All or nothing

config.adaptive_sampling do
  trace_consistent true
  
  # Propagate sample decision
  propagate_sample_decision true
  sample_decision_key 'e11y_sampled'  # In job metadata
end

# Implementation:
# HTTP request:
sample_decision = sampler.should_sample?(request_event)
Current.set(sampled: sample_decision)

# When enqueuing job:
MyJob.perform_later(
  ...,
  e11y_sampled: Current.sampled  # ← Propagate decision
)

# In job execution:
if job.metadata[:e11y_sampled]
  # Track event (already sampled)
else
  # Don't track (consistent with parent)
end

# Option 2: Independent sampling (simpler, but inconsistent)
# - HTTP request sampled independently
# - Job sampled independently
# - May result in incomplete traces (acceptable for sampling)

# Option 3: Always sample jobs (practical)
config.adaptive_sampling do
  always_sample_patterns ['background_jobs.*']
end

# Rationale:
# - Jobs are lower volume than HTTP requests
# - Jobs are more critical (if they fail, need full trace)
# - Cost: jobs 100%, HTTP 10% → acceptable
```

**Decision:**
- ✅ **Trace-consistent sampling for same trace_id**
- Reason: Preserves trace integrity
- Implementation: Propagate sample decision in job metadata
- Exception: Jobs can be always-sampled (override)

**Configuration:**
```ruby
config.adaptive_sampling do
  # Trace consistency
  trace_consistent_sampling true
  propagate_sample_decision true
  
  # Jobs can override (always sample)
  always_sample_patterns [
    'background_jobs.failed',  # Always sample failures
    'background_jobs.retry'    # Always sample retries
  ]
  
  # For jobs WITHOUT parent trace (orphaned jobs)
  orphaned_job_sampling do
    sample_rate 1.0  # Always sample orphaned jobs
  end
end

config.background_jobs do
  # Propagate sample decision in job metadata
  propagate_sample_decision true
  sample_decision_metadata_key 'e11y_sampled'
end
```

**No major conflict:** Trace-consistent sampling solves the issue.

---

### 🟡 Conflict #10: Event Versioning + Schema Validation

**Features:**
- UC-020: Event Versioning
- UC-002: Event Schema Validation

**Potential Conflict:**
- Multiple event versions exist (`OrderPaid` v1, `OrderPaidV2`)
- Each has different schema
- Event Registry might route to wrong version
- Validation against wrong schema

**Analysis:**
```ruby
# Scenario:
# 1. Old service sends V1 event: OrderPaid.track(order_id: '123', amount: 99.99)
# 2. New service expects V2: OrderPaidV2.track(..., currency: 'USD')
# 3. Registry receives V1 event → which schema to validate against?

# Problem:
# - V1 schema doesn't require `currency`
# - V2 schema DOES require `currency`
# - If validated against V2 → V1 events fail ❌
```

**Issue:**
- Version routing must happen BEFORE validation
- Event must declare its version explicitly
- Registry must know all versions

**Resolution:**
```ruby
# Option 1: Version in payload (RECOMMENDED)
{
  "event_name": "order.paid",
  "event_version": 1,  # ← Explicit version
  "payload": { "order_id": "123", "amount": 99.99 }
}

# Registry routes by version:
event_class = Registry.find("order.paid", version: 1)  # → OrderPaid
event_class.validate!(payload)  # ← Correct schema!

# Option 2: Class name includes version
OrderPaid.track(...)      # Implicitly v1
OrderPaidV2.track(...)    # Explicitly v2

# Each class knows its own schema
# No routing ambiguity

# Option 3: Auto-detect version from schema
def detect_version(event_name, payload)
  versions = Registry.versions_for(event_name)  # [OrderPaid, OrderPaidV2]
  
  versions.each do |event_class|
    return event_class if event_class.schema_matches?(payload)
  end
  
  raise "No matching version for #{event_name}"
end
```

**Decision:**
- ✅ **Explicit version in event class (no auto-routing needed)**
- Reason: Type safety, no ambiguity
- `OrderPaid.track` → always v1 schema
- `OrderPaidV2.track` → always v2 schema
- Version field in payload optional (for observability)

**Configuration:**
```ruby
config.versioning do
  enabled true
  
  # Include version in payload (for downstream consumers)
  include_version_in_payload true
  version_field :event_version
  
  # Validation uses class-level schema (no routing)
  validate_against_class_schema true
  
  # Optional: Auto-detect for dynamic tracking
  auto_detect_version false  # Disabled (too risky)
end
```

**Pipeline:**
```ruby
# Validation happens per-class:
OrderPaid.track(payload)
  ↓
1. OrderPaid.validate!(payload)  # ← V1 schema
  ↓
2. Add version: payload[:event_version] = 1
  ↓
3. Continue pipeline...

OrderPaidV2.track(payload)
  ↓
1. OrderPaidV2.validate!(payload)  # ← V2 schema
  ↓
2. Add version: payload[:event_version] = 2
  ↓
3. Continue pipeline...
```

**No major conflict:** Validation is class-scoped, not registry-scoped.

---

### 🟡 Conflict #11: Event Versioning + DLQ Replay

**Features:**
- UC-020: Event Versioning
- UC-021: Dead Letter Queue Replay

**Potential Conflict:**
- V1 event fails, goes to DLQ
- Developer deploys V2 (deprecates V1)
- DLQ replay → V1 class no longer exists
- Replay fails ❌

**Analysis:**
```ruby
# Timeline:
# Day 1: OrderPaid (v1) event tracked and validated ✅
#        → Adapter write fails (network timeout)
#        → Event goes to DLQ (already validated!)
# Day 30: OrderPaidV2 deployed, OrderPaid (v1) class deleted
# Day 31: Replay DLQ → ERROR: OrderPaid class not found!

{
  "event_name": "order.paid",
  "event_version": 1,  # ← V1 event in DLQ (already validated)
  "payload": { "order_id": "123", "amount": 99.99 }  # ← Valid V1 payload
}

# Replay attempts:
event_class = Registry.find("order.paid", version: 1)
# → nil (OrderPaid v1 class deleted!)

# Problem is NOT validation (event already validated)
# Problem is: HOW TO REPLAY without the class code?
```

**Issue:**
- DLQ events outlive code versions
- Event already validated (was valid when tracked)
- Replay needs event CLASS, not for validation, but for:
  1. Adapter routing (which adapters to send to)
  2. PII filtering rules (class-defined)
  3. Retry policy (class-defined)
  4. Any class-level hooks (before_track, after_track)
- **Code dependency, not schema dependency**

**Resolution:**
```ruby
# Option 1: Keep old versions until DLQ empty (RECOMMENDED)
# Why? Not for validation (already validated), but for:
# - Adapter routing (class defines which adapters)
# - PII filtering (class-level rules)
# - Hooks (before_track, after_track)

# Before deleting OrderPaid (v1):
# 1. Mark as deprecated
# 2. Deploy OrderPaidV2
# 3. Wait for DLQ to drain (or manually replay)
# 4. Verify: no V1 events in DLQ for 30 days
# 5. THEN delete OrderPaid (v1)

# Checklist:
- [ ] Mark V1 as deprecated
- [ ] Deploy V2
- [ ] Replay DLQ: E11y::DeadLetterQueue.replay_all
- [ ] Monitor: no V1 events for 30 days
- [ ] Delete V1 class

# Why replay needs the class:
# - Event in DLQ = just data (JSON)
# - To replay = need class behavior (adapters, hooks, PII rules)
# - Class is the "instructions" for how to send the event

# Option 2: Auto-upgrade on replay (SAFETY NET)
# If V1 class deleted, use V2 class with transformation
config.error_handling.dead_letter_queue do
  auto_upgrade_on_replay true
  
  upgrade_rules do
    # V1 → V2 transformation
    upgrade 'order.paid' do
      from_version 1
      to_version 2
      transform do |v1_payload|
        v1_payload.merge(currency: 'USD')  # Add missing field for V2
      end
    end
  end
end

# On replay:
dlq_event = { event_name: 'order.paid', event_version: 1, payload: {...} }

# Try to find V1 class
v1_class = Registry.find('order.paid', version: 1)

if v1_class.nil?
  # V1 deleted! Auto-upgrade to V2
  upgraded_payload = upgrade_transformer.transform(dlq_event, to: 2)
  # Use V2 class behavior (adapters, hooks, etc.)
  OrderPaidV2.track(**upgraded_payload)  # ← Uses V2 class code
else
  # V1 still exists, use it
  OrderPaid.track(**dlq_event[:payload])  # ← Uses V1 class code
end

# Key point: Event data is valid (already validated)
# We need class CODE for replay behavior, not validation

# Option 3: Graceful degradation (log + skip)
config.error_handling.dead_letter_queue do
  on_version_not_found :skip  # :skip, :error, :upgrade
  
  log_skipped_events true
  skipped_events_file 'log/dlq_skipped.jsonl'
end

# Option 4: Version-agnostic replay (COMPLEX)
# Store full event metadata in DLQ (not just payload)
config.error_handling.dead_letter_queue do
  store_full_event_metadata true
  
  # DLQ includes:
  # - event_name
  # - event_version
  # - payload (already validated)
  # - adapters (which adapters to replay to)
  # - pii_rules (how to filter)
  # - retry_policy (how to retry)
  # - Any class-level config at time of original tracking
end

# Replay uses stored metadata (not class code)
# Problem: Metadata might be outdated (e.g., adapter URLs changed)
# Benefit: Can replay without class existing
# Tradeoff: Replays with OLD behavior, not current
```

**Decision:**
- ✅ **Keep V1 until DLQ drained (manual process)**
- ✅ **Auto-upgrade on replay (safety net)**
- Reason: Prevents data loss, graceful migration
- Deprecation process includes DLQ check

**Important Clarification:**
- DLQ events are ALREADY VALIDATED ✅ (validation happened when first tracked)
- Replay doesn't need validation, needs **class behavior**:
  - Which adapters to send to (`OrderPaid.adapters`)
  - PII filtering rules (`OrderPaid.pii_rules`)
  - Retry policy (`OrderPaid.retry_policy`)
  - Hooks (`OrderPaid.before_track`, `OrderPaid.after_track`)
- Without class code → can't determine HOW to replay
- Auto-upgrade = use V2 class behavior with V1 data (transformed)

**Configuration:**
```ruby
config.versioning do
  # DLQ compatibility
  deprecation_enforcement do
    check_dlq_before_removal true  # ← Verify DLQ empty
    
    # What to do if DLQ contains deprecated version
    on_dlq_contains_deprecated :warn  # :error, :warn, :skip
  end
end

config.error_handling.dead_letter_queue do
  # Auto-upgrade on replay (if version missing)
  auto_upgrade_on_replay true
  
  upgrade_rules do
    # Define transformations
    upgrade 'order.paid' do
      from_version 1
      to_version 2
      transform_method :migrate_to_v2  # Use event's method
    end
  end
  
  # Fallback: skip if no upgrade rule
  on_version_not_found :skip
  log_skipped_events true
end
```

**Why Class Code Needed for Replay:**

```
┌─────────────────────────────────────────────────────────────┐
│ DLQ Event (Just Data)                                       │
│ {                                                            │
│   "event_name": "order.paid",                               │
│   "event_version": 1,                                       │
│   "payload": { "order_id": "123", "amount": 99.99 }        │
│ }                                                            │
│                                                              │
│ ✅ Already validated (when first tracked)                   │
│ ❌ No behavior information:                                 │
│    - Which adapters? (need OrderPaid.adapters)             │
│    - PII rules? (need OrderPaid.pii_rules)                 │
│    - Retry policy? (need OrderPaid.retry_policy)           │
│    - Hooks? (need OrderPaid callbacks)                     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Replay Process                                               │
│                                                              │
│ 1. Find class: OrderPaid = Registry.find('order.paid', v:1) │
│    ↓                                                         │
│ 2. Use class behavior:                                      │
│    - adapters: [:loki, :elasticsearch]  ← from class       │
│    - pii_rules: { mask: [:email] }      ← from class       │
│    - retry: 3 attempts                   ← from class       │
│    ↓                                                         │
│ 3. Execute: OrderPaid.track(payload)                        │
│    ↓                                                         │
│ 4. Send to adapters with class-defined behavior             │
└─────────────────────────────────────────────────────────────┘
```

**Deprecation Checklist (Updated):**
```ruby
# Before removing OrderPaid (v1):
1. Mark deprecated:
   class OrderPaid < E11y::Event::Base
     deprecated true
     deprecation_date '2026-06-01'
   end

2. Deploy OrderPaidV2 (coexist)

3. Migrate tracking calls

4. Check DLQ:
   events = E11y::DeadLetterQueue.find { |e| e.name == 'order.paid' && e.version == 1 }
   if events.any?
     # Replay first! (needs V1 class code)
     E11y::DeadLetterQueue.replay_all
   end

5. Monitor: no V1 events for 30 days

6. Delete OrderPaid (v1) class
   # Safe to delete: DLQ empty, no V1 events in flight
```

**Conflict resolved:** DLQ checks before version removal + auto-upgrade on replay.

---

### 🟢 Conflict #12: Event Versioning + Event Registry

**Features:**
- UC-020: Event Versioning
- UC-022: Event Registry

**Potential Conflict:**
- Registry must track multiple versions
- `Registry.all_events` → returns V1 and V2?
- `Registry.find('order.paid')` → which version?

**Analysis:**
```ruby
# Registry contains:
# - OrderPaid (v1)
# - OrderPaidV2 (v2)
# - UserSignup (v1, no V2 yet)

# Question 1: What does Registry.all_events return?
Registry.all_events
# → [OrderPaid, OrderPaidV2, UserSignup]  # All versions?
# → [OrderPaidV2, UserSignup]  # Only latest/default?

# Question 2: What does Registry.find('order.paid') return?
Registry.find('order.paid')
# → OrderPaid (v1)?  # First registered
# → OrderPaidV2 (v2)?  # Latest version
# → nil?  # Ambiguous, require version parameter
```

**Issue:**
- Registry API must handle versioning
- Ambiguity in lookups

**Resolution:**
```ruby
# Option 1: Explicit version in find (RECOMMENDED)
Registry.find('order.paid')  # → Returns default_version (V2)
Registry.find('order.paid', version: 1)  # → OrderPaid (v1)
Registry.find('order.paid', version: 2)  # → OrderPaidV2 (v2)

# all_events includes all versions
Registry.all_events
# → [OrderPaid, OrderPaidV2, UserSignup]

# Filter by latest
Registry.all_events.filter(&:default_version?)
# → [OrderPaidV2, UserSignup]

# Option 2: Separate methods
Registry.all_events  # All versions (for introspection)
Registry.current_events  # Only default versions (for docs)
Registry.deprecated_events  # Only deprecated versions

# Option 3: Structured registry
Registry.versions_for('order.paid')
# → {
#   1 => OrderPaid (deprecated: true),
#   2 => OrderPaidV2 (default: true)
# }

# Implementation:
class Registry
  def self.find(event_name, version: nil)
    versions = @events[event_name] || {}
    
    if version
      versions[version]
    else
      # Return default version
      versions.values.find(&:default_version?) || versions.values.last
    end
  end
  
  def self.all_events
    @events.values.flat_map(&:values).uniq
  end
  
  def self.current_events
    all_events.filter(&:default_version?)
  end
  
  def self.versions_for(event_name)
    @events[event_name] || {}
  end
end
```

**Decision:**
- ✅ **Registry tracks all versions**
- ✅ **find() returns default_version**
- ✅ **find(version: N) returns specific version**
- ✅ **all_events returns all versions (for introspection)**
- ✅ **current_events returns only defaults (for docs)**

**Configuration:**
```ruby
config.registry do
  enabled true
  
  # Version handling
  track_all_versions true  # Register all versions
  
  # Default version resolution
  default_version_strategy :explicit  # Use default_version flag
  # Alternative: :latest (highest version number)
  
  # Introspection
  enable_version_listing true  # Registry.versions_for('event.name')
end
```

**Registry API:**
```ruby
# Lookup
Registry.find('order.paid')  # → OrderPaidV2 (default)
Registry.find('order.paid', version: 1)  # → OrderPaid (v1)

# List all versions
Registry.versions_for('order.paid')
# → { 1 => OrderPaid, 2 => OrderPaidV2 }

# List events
Registry.all_events  # All versions
Registry.current_events  # Only defaults
Registry.deprecated_events  # Only deprecated

# Stats
Registry.stats
# → {
#   total_events: 42,
#   by_version: { 1 => 30, 2 => 12 },
#   deprecated: 5,
#   default: 35
# }
```

**No conflict:** Registry explicitly handles versioning.

---

### 🟡 Conflict #13: Retry Policy + Rate Limiting

**Features:**
- UC-021: Retry Policy
- UC-011: Rate Limiting

**Potential Conflict:**
- Event fails to send → retry
- Retry attempts count toward rate limit?
- Could exhaust rate limit with retries alone

**Analysis:**
```ruby
# Scenario:
# Rate limit: 100 events/sec
# Current rate: 95 events/sec (near limit)
# 5 events fail to send (network timeout)
# Each retries 3 times = 15 retry attempts
# Total: 95 + 15 = 110 events → RATE LIMITED!

# Question: Should retries count toward rate limit?

# Option A: Retries count (safer for system)
rate_limiter.track(event)  # Original attempt
# → Rate limit exceeded
# → Event dropped, never retried

# Option B: Retries don't count (better delivery)
rate_limiter.track(event) unless event.retry?
# → Retries bypass rate limiter
# → Risk: retry storm could overwhelm system
```

**Issue:**
- Rate limiting protects system
- Retries ensure delivery
- Conflict between protection and reliability

**Resolution:**
```ruby
# Option 1: Retries count toward rate limit (RECOMMENDED)
# - Safer for system stability
# - Prevents retry amplification
# - Failed events go to DLQ (not retried indefinitely)

def track_event(event, is_retry: false)
  # Rate limit check (applies to retries too)
  unless rate_limiter.allowed?(event)
    if is_retry
      # Retry rate-limited → DLQ
      dead_letter_queue.add(event, reason: 'rate_limited_retry')
    else
      # Original rate-limited → drop
      metrics.increment('events_rate_limited')
    end
    return :rate_limited
  end
  
  # Continue processing...
end

# Option 2: Separate rate limit for retries
config.rate_limiting do
  original_limit 100.per_second
  retry_limit 20.per_second  # Additional headroom for retries
end

# Option 3: Priority queue (retries prioritized)
config.rate_limiting do
  priority_levels do
    high [:error, :fatal]  # Never rate-limit errors
    medium [:warn, :info]
    low [:debug]
  end
  
  prioritize_retries true  # Retries get priority
end
```

**Decision:**
- ✅ **Retries DO count toward rate limit**
- ✅ **Separate rate limit pool for retries (optional)**
- Reason: Prevent retry amplification attack
- Safety: Rate-limited retries → DLQ (not dropped)

**Configuration:**
```ruby
config.error_handling do
  retry_policy do
    enabled true
    max_retries 3
    
    # Retries respect rate limiting
    respect_rate_limits true
    
    # What to do if retry rate-limited
    on_retry_rate_limited :send_to_dlq  # :send_to_dlq, :drop, :wait
  end
end

config.rate_limiting do
  global_limit 100.per_second
  
  # Optional: separate limit for retries
  retry_limit do
    enabled true
    limit 20.per_second  # Additional headroom
  end
  
  # Priority for retries (within limit)
  prioritize_retries true
  
  # Critical events bypass (errors, audit)
  bypass_for_severities [:error, :fatal]
  bypass_for_patterns ['audit.*', 'security.*']
end
```

**Pipeline Order:**
```ruby
# Original event:
track(event)
  → Rate Limiting (check)
  → Adapter Write (fail)
  → Retry #1
    → Rate Limiting (check again)  # ← Retry counts!
    → Adapter Write (fail)
  → Retry #2 (rate limited)
    → DLQ (rate-limited retry)

# Retries DO go through rate limiter again
```

**Conflict resolved:** Retries count toward limit, with DLQ safety net.

---

### 🟢 Conflict #14: DLQ Filter + Retry Policy

**Features:**
- UC-021: DLQ Filter (save critical events only)
- UC-021: Retry Policy

**Potential Conflict:**
- DLQ filter says "never save health checks"
- Retry policy says "retry 3 times then DLQ"
- Health check fails after 3 retries → where does it go?

**Analysis:**
```ruby
# Scenario:
# DLQ filter:
config.dead_letter_queue.filter do
  never_save { event_patterns ['health_check.*'] }
end

# Retry policy:
config.retry_policy do
  max_retries 3
  on_max_retries_exceeded :send_to_dlq
end

# Event fails:
Events::HealthCheck.track(status: 'ok')
# → Adapter fails
# → Retry #1, #2, #3 (all fail)
# → on_max_retries_exceeded says: send_to_dlq
# → DLQ filter says: never_save health_check.*
# → Conflict! What happens?
```

**Issue:**
- Retry policy → send to DLQ
- DLQ filter → don't save
- Which wins?

**Resolution:**
```ruby
# Option 1: DLQ filter wins (RECOMMENDED)
# - Filter is more specific (per-event rules)
# - Health check dropped (not saved to DLQ)
# - Logged for observability

def handle_max_retries(event, error)
  if dlq_filter.should_save?(event)
    dead_letter_queue.add(event, error)
    metrics.increment('dlq_events_added')
  else
    # Filter says don't save
    logger.warn "Event dropped after max retries (filtered)", event: event.name
    metrics.increment('dlq_events_filtered')
  end
end

# Option 2: Retry policy wins (override filter)
# - on_max_retries_exceeded is explicit intent
# - Saves to DLQ despite filter
# - Filter applies to other DLQ sources

config.error_handling do
  on_max_retries_exceeded :send_to_dlq_ignore_filter
end

# Option 3: Log dropped events
config.error_handling do
  on_max_retries_exceeded :send_to_dlq  # Check filter first
  
  # If filtered, log to separate file
  log_filtered_failures true
  filtered_failures_log 'log/e11y_dropped.jsonl'
end
```

**Decision:**
- ✅ **DLQ filter wins (higher precedence)**
- Reason: Filter is explicit per-event policy
- Mitigation: Log dropped events for audit trail
- Alternative: `send_to_dlq_ignore_filter` for override

**Configuration:**
```ruby
config.error_handling do
  retry_policy do
    max_retries 3
  end
  
  # What happens after max retries
  on_max_retries_exceeded :send_to_dlq  # Check DLQ filter first
  
  dead_letter_queue do
    enabled true
    
    filter do
      never_save { event_patterns ['health_check.*'] }
    end
  end
  
  # Dropped events (failed + filtered)
  log_dropped_events true
  dropped_events_log 'log/e11y_dropped.jsonl'
  dropped_events_metrics true  # Track in metrics
end
```

**Pipeline:**
```ruby
# Health check fails:
track(:health_check)
  → Adapter fails
  → Retry #1, #2, #3 (all fail)
  → on_max_retries_exceeded
    → Check DLQ filter
      → Filter says: never_save
      → Don't add to DLQ
      → Log to dropped_events_log
      → Increment metric: dlq_events_filtered
```

**Metrics:**
```ruby
# Track filtered events
e11y_dlq_events_filtered_total{event_name, reason}
e11y_events_dropped_total{event_name, reason}

# Alert if critical events filtered
alert: CriticalEventsFiltered
expr: e11y_dlq_events_filtered_total{event_name=~"payment.*|order.*"} > 0
```

**No conflict:** DLQ filter has precedence, with logging for audit.

---

### 🟢 Conflict #15: Event Registry + Memory Optimization

**Features:**
- UC-022: Event Registry (eager load all events)
- Memory Optimization (zero-allocation pattern)

**Potential Conflict:**
- Registry eager loads all event classes
- Memory footprint increases (class definitions in memory)
- Zero-allocation pattern minimizes per-event memory
- Does registry negate memory optimization?

**Analysis:**
```ruby
# Registry eager loads:
E11y::Registry.all_events  # Loads all 100 event classes

# Memory cost:
# - 100 classes × ~10KB per class definition = 1MB
# - vs. per-event allocation: 100 events/sec × 100 bytes = 10KB/sec

# Question: Does 1MB one-time cost matter?
# Answer: No, it's negligible compared to per-event cost

# Without registry:
# - Autoload classes on demand (lazy)
# - Memory: only loaded classes

# With registry:
# - Eager load all classes
# - Memory: all classes (but fixed cost)

# Per-event memory (zero-allocation):
# - No instances created: 0 bytes/event
# - Only hash allocated: ~100 bytes/event

# Conclusion: Registry is one-time cost, per-event is recurring
# 1MB one-time << 100 bytes × millions of events
```

**Issue:**
- Registry adds fixed memory cost (~1MB)
- But zero-allocation saves recurring cost (>>1MB over time)
- No real conflict

**Resolution:**
```ruby
# Option 1: Eager load in production (RECOMMENDED)
config.registry do
  eager_load Rails.env.production?
  # Prod: eager load (registry benefits)
  # Dev: lazy load (faster boot)
end

# Option 2: Lazy registry
config.registry do
  lazy_load true
  # Classes loaded on first access
  # Registry populated incrementally
end

# Option 3: Configurable
config.registry do
  eager_load_paths [
    Rails.root.join('app', 'events')
  ]
  
  # Skip heavy/unused events
  eager_load_exclude ['test_events', 'examples']
end
```

**Decision:**
- ✅ **Eager load in production (registry benefits)**
- ✅ **Lazy load in development (faster boot)**
- Reason: Fixed 1MB cost is negligible vs. recurring savings
- Registry provides introspection, documentation, tooling

**Configuration:**
```ruby
config.registry do
  # Eager load (production)
  eager_load Rails.env.production?
  eager_load_paths [Rails.root.join('app', 'events')]
  
  # Memory impact: ~1MB one-time
  # Benefit: Introspection, docs, event explorer
  
  # Still use zero-allocation pattern
  # Memory saved: ~100 bytes/event × millions = >>1MB
end

config.development do
  # Lazy load (development)
  eager_load_events false
  # Faster Rails boot time
end
```

**Memory Analysis:**
```
Registry Cost (One-time):
- 100 event classes × 10KB = 1MB

Zero-Allocation Savings (Recurring):
- Without: 100 events/sec × 100 bytes/event × 86400 sec/day = 864MB/day
- With: 100 events/sec × 0 bytes/event = 0MB/day
- Savings: 864MB/day

Conclusion: Registry cost (1MB) << Savings (864MB/day)
```

**No conflict:** Registry is negligible one-time cost, zero-allocation is massive recurring saving.

---

## Summary of Conflicts (Updated)

| # | Conflict | Severity | Resolution | Status |
|---|----------|----------|------------|--------|
| 1 | Request Buffer + Main Buffer | ✅ None | Dual-buffer architecture | Resolved |
| 2 | Rate Limiting + Adaptive Sampling | 🟡 Minor | Pipeline order: Rate limit → Sample | Resolved |
| 3 | PII Filtering + OTel Semantic Conventions | 🟡 Minor | Per-adapter PII filtering | Resolved |
| 4 | Audit Signing + PII Filtering | 🔴 Major | Audit events skip PII filtering | Resolved |
| 5 | Cardinality + Auto-Metrics | 🟡 Minor | Require explicit labels | Resolved |
| 6 | Circuit Breaker + Multi-Adapter | ✅ None | Independent circuits | Resolved |
| 7 | Compression + Minimization | 🟡 Minor | Minimize → Compress | Resolved |
| 8 | Tiered Storage + Retention Tags | 🟡 Minor | Event retention > Tiered | Resolved |
| 9 | Job Tracing + Sampling | 🟡 Minor | Trace-consistent sampling | Resolved |
| **10** | **Event Versioning + Schema Validation** | 🟡 Minor | Class-scoped validation | ✅ Resolved |
| **11** | **Event Versioning + DLQ Replay** | 🟡 Minor | Keep V1 until DLQ drained + auto-upgrade | ✅ Resolved |
| **12** | **Event Versioning + Event Registry** | ✅ None | Registry tracks all versions | ✅ Resolved |
| **13** | **Retry Policy + Rate Limiting** | 🟡 Minor | Retries count toward limit + DLQ | ✅ Resolved |
| **14** | **DLQ Filter + Retry Policy** | ✅ None | DLQ filter has precedence | ✅ Resolved |
| **15** | **Event Registry + Memory Optimization** | ✅ None | Registry negligible vs. savings | ✅ Resolved |

---

## Summary of Conflicts

| # | Conflict | Severity | Resolution | Status |
|---|----------|----------|------------|--------|
| 1 | Request Buffer + Main Buffer | ✅ None | Dual-buffer architecture | Resolved |
| 2 | Rate Limiting + Adaptive Sampling | 🟡 Minor | Pipeline order: Rate limit → Sample | Resolved |
| 3 | PII Filtering + OTel Semantic Conventions | 🟡 Minor | Per-adapter PII filtering | Resolved |
| 4 | Audit Signing + PII Filtering | 🔴 Major | Audit events skip PII filtering | Resolved |
| 5 | Cardinality + Auto-Metrics | 🟡 Minor | Require explicit labels | Resolved |
| 6 | Circuit Breaker + Multi-Adapter | ✅ None | Independent circuits | Resolved |
| 7 | Compression + Minimization | 🟡 Minor | Minimize → Compress | Resolved |
| 8 | Tiered Storage + Retention Tags | 🟡 Minor | Event retention > Tiered | Resolved |
| 9 | Job Tracing + Sampling | 🟡 Minor | Trace-consistent sampling | Resolved |
| 10 | Event Versioning + Schema Validation | 🟡 Minor | Class-scoped validation | Resolved |
| 11 | Event Versioning + DLQ Replay | 🟡 Minor | Keep V1 until DLQ drained + auto-upgrade | Resolved |
| 12 | Event Versioning + Event Registry | ✅ None | Registry tracks all versions | Resolved |
| 13 | Retry Policy + Rate Limiting | 🟡 Minor | Retries count toward limit + DLQ | Resolved |
| 14 | DLQ Filter + Retry Policy | ✅ None | DLQ filter has precedence | Resolved |
| 15 | Event Registry + Memory Optimization | ✅ None | Registry negligible vs. savings | Resolved |

---

## Architecture Decisions

### 1. Pipeline Order (Processing)

**Definitive order for event processing:**

```ruby
track(event)
  ↓
1. Schema Validation (fail fast)
  ↓
2. Context Enrichment (trace_id, user_id, etc.)
  ↓
3. PII Filtering (security first)
  ↓  [Per-adapter: different rules]
  ↓
4. Rate Limiting (system protection)
  ↓  [Drop if exceeded]
  ↓
5. Adaptive Sampling (cost optimization)
  ↓  [Drop if not sampled]
  ↓
6. Buffer Routing (debug vs. main)
  ↓
  ├─→ Request Buffer (:debug only)
  │    ↓ (on error/end)
  │
  └─→ Main Buffer (:info+)
       ↓ (every 200ms)
       └─→ 7. Batching
            ↓
       8. Payload Minimization
            ↓
       9. Serialization (JSON)
            ↓
      10. Compression (if enabled)
            ↓
      11. Circuit Breaker Check
            ↓
      12. Adapter Write (fan-out to all adapters)
```

### 2. Per-Adapter Overrides

**Features that support per-adapter configuration:**

- PII Filtering (different rules per adapter)
- Compression (only for remote adapters)
- Serialization format (JSON, MessagePack, Protobuf)
- Batch size (larger for file, smaller for HTTP)
- Circuit breaker settings

### 3. Precedence Rules

**When multiple configs apply, order of precedence:**

1. **Event-level config** (highest priority)
   - Example: `event.retention = 7.years`
   - Example: `event.adapters = [:audit_file]`

2. **Per-event-type config**
   - Example: `per_event 'payment.*' { sample_rate: 1.0 }`

3. **Per-severity config**
   - Example: `per_severity :fatal { adapters: [:sentry, :pagerduty] }`

4. **Global config** (lowest priority)
   - Example: `config.default_adapters = [:loki]`

### 4. Feature Interactions (Positive)

**Features that ENHANCE each other:**

- ✅ Tracing + Metrics (exemplars with trace_id)
- ✅ Rate Limiting + Circuit Breaker (protect system)
- ✅ Sampling + Compression (reduce costs)
- ✅ Cardinality Protection + Cost Optimization (both reduce costs)
- ✅ Request Buffer + Tracing (full debug context on error)
- ✅ Audit Trail + Retention Tagging (compliance + lifecycle)

---

## Next Steps

### Configuration Updates Required

1. ✅ Update `config.pipeline_order` section
2. ✅ Add `config.pii_filter.adapter_overrides`
3. ✅ Add `config.audit_trail.skip_pii_filtering`
4. ✅ Add `config.metrics.require_explicit_labels`
5. ✅ Add `config.adaptive_sampling.trace_consistent_sampling`
6. ✅ Add `config.cost_optimization.tiered_storage.respect_event_retention`

### Documentation Updates Required

1. Pipeline order diagram (definitive)
2. Per-adapter configuration examples
3. Precedence rules documentation
4. Feature interaction matrix (positive synergies)

---

## 📊 Updated Statistics

**Total Conflicts Analyzed:** 16 (was 10, added 6 new)

**By Severity:**
- 🔴 Major: 1 (Audit Signing + PII) - Resolved
- 🟡 Minor: 9 (various) - All Resolved
- ✅ None: 6 (no conflicts) - N/A

**By Feature Category:**
- Core Pipeline: 3 conflicts
- Security/Compliance: 2 conflicts
- Performance/Cost: 4 conflicts
- Reliability: 3 conflicts
- **New (UC-020, UC-021, UC-022): 6 conflicts**

**Resolution Methods:**
- Pipeline ordering: 4 conflicts
- Per-adapter configuration: 2 conflicts
- Precedence rules: 3 conflicts
- Auto-upgrade/migration: 2 conflicts
- Independent components: 5 conflicts

---

## 🆕 New Conflicts from UC-020, UC-021, UC-022

| # | New Conflict | Features | Resolution |
|---|-------------|----------|------------|
| 11 | Versioning + Validation | UC-020 + UC-002 | Class-scoped validation |
| 12 | Versioning + DLQ Replay | UC-020 + UC-021 | Keep V1 until DLQ drained |
| 13 | Versioning + Registry | UC-020 + UC-022 | Registry tracks all versions |
| 14 | Retry + Rate Limiting | UC-021 + UC-011 | Retries count toward limit |
| 15 | DLQ Filter + Retry Policy | UC-021 + UC-021 | DLQ filter has precedence |
| 16 | Registry + Memory | UC-022 + Memory | Registry negligible cost |

**All resolved!** ✅

---

## 🎯 Key Architectural Insights

### From New Conflicts:

1. **Event Versioning (UC-020):**
   - No routing ambiguity (class-based, not registry-based)
   - DLQ replay requires version compatibility
   - Registry must track all versions explicitly

2. **Error Handling (UC-021):**
   - Retries respect system limits (rate limiting)
   - DLQ filter is highest precedence (explicit per-event policy)
   - Dropped events logged for audit (no silent failures)

3. **Event Registry (UC-022):**
   - Fixed memory cost (1MB) vs. recurring savings (864MB/day)
   - Eager load in production, lazy in development
   - Version-aware API (find by version, list all versions)

### Design Principles Validated:

- ✅ **Explicit over implicit** (version in class name, explicit labels)
- ✅ **Safety over convenience** (DLQ filter precedence, rate limit retries)
- ✅ **Compliance over cost** (event retention > tiered storage)
- ✅ **Observability over silence** (log dropped events, track metrics)
- ✅ **Pragmatism over purity** (auto-upgrade on replay, graceful degradation)

---

**Status:** ✅ Conflict Analysis Complete (16/16)  
**Result:** All conflicts analyzed and resolved  
**Severity:** 1 major (resolved), 9 minor (resolved), 6 none  
**New Features:** UC-020, UC-021, UC-022 fully integrated

**Ready for:** Implementation 🚀
