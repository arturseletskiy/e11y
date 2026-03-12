# E11y Comprehensive Configuration Guide

**Purpose:** Максимально полный конфиг-пример, покрывающий ВСЕ 22 use cases для анализа конфликтов между фичами.

---

## 📋 Table of Contents

1. [Initializer Configuration](#initializer-configuration)
2. [Event Examples](#event-examples)
3. [Feature Coverage Matrix](#feature-coverage-matrix)
4. [Conflict Analysis](#conflict-analysis)

---

## 1. Initializer Configuration (v1.1 - RECOMMENDED ✅)

> **🎯 v1.1 Philosophy: Infrastructure Only**
>
> Global configuration contains **ONLY infrastructure** (adapters, buffer, circuit breaker, hooks).
> **Event-specific configuration** (severity, rate_limit, sampling, PII) is defined at **event-level** (see Section 2).
>
> **Result:** Global config reduced from **1400+ lines (v1.0) to <300 lines (v1.1)** - **78% reduction!**
>
> **What's in global config:**
> - ✅ Adapters registry (register once, reference everywhere)
> - ✅ Buffer configuration (system-wide resource management)
> - ✅ Circuit breaker (adapter health protection)
> - ✅ Global context enrichment (added to ALL events)
> - ✅ Hooks & lifecycle (system-wide event processing)
> - ✅ Graceful shutdown
>
> **What's NOT in global config (moved to event-level):**
> - ❌ Per-event severity, rate limits, sampling rates
> - ❌ Per-event PII filtering rules
> - ❌ Per-event metrics definitions
> - ❌ Per-event adapter routing
> - ❌ Per-event retention policies
>
> See [Section 2](#2-event-examples-v11---recommended-) for event-level configuration examples.

### config/initializers/e11y.rb (v1.1 - Infrastructure Only)

```ruby
# frozen_string_literal: true

# E11y v1.1 Configuration - Infrastructure Only
# Event-specific config (severity, rate_limit, sampling, PII) is at event-level!
# See Section 2 for event examples.

E11y.configure do |config|
  # ============================================================================
  # ADAPTERS REGISTRY
  # ============================================================================
  # Register adapters once, reference by name in events
  # Related: UC-002 (Business Events), ADR-004 (Adapter Architecture)
  
  config.adapters do
    # === Primary: Loki (logs) ===
    register :loki, E11y::Adapters::LokiAdapter.new(
      url: ENV['LOKI_URL'] || 'http://localhost:3100',
      labels: {
        env: Rails.env,
        service: ENV['SERVICE_NAME'] || 'api'
      },
      timeout: 5,
      batch_size: 1000
    )
    
    # === Primary: Elasticsearch (long-term storage + analytics) ===
    register :elasticsearch, E11y::Adapters::ElasticsearchAdapter.new(
      url: ENV['ELASTICSEARCH_URL'] || 'http://localhost:9200',
      index_prefix: 'e11y-events',
      username: ENV['ES_USERNAME'],
      password: ENV['ES_PASSWORD'],
      timeout: 10
    )
    
    # === Alerts: Sentry (errors) ===
    register :sentry, E11y::Adapters::SentryAdapter.new(
      dsn: ENV['SENTRY_DSN'],
      environment: Rails.env,
      release: ENV['GIT_SHA']
    )
    
    # === Alerts: PagerDuty (critical incidents) ===
    register :pagerduty, E11y::Adapters::PagerDutyAdapter.new(
      api_key: ENV['PAGERDUTY_API_KEY'],
      service_id: ENV['PAGERDUTY_SERVICE_ID']
    )
    
    # === Alerts: Slack (team notifications) ===
    register :slack, E11y::Adapters::SlackAdapter.new(
      webhook_url: ENV['SLACK_WEBHOOK_URL'],
      channel: '#alerts',
      username: 'E11y Bot'
    )
    
    # === Local: File (development, fallback) ===
    register :file, E11y::Adapters::FileAdapter.new(
      path: Rails.root.join('log', 'e11y'),
      rotation: :daily,
      max_size: 100.megabytes
    )
    
    # === Archive: external job filters Loki by retention_until (ISO8601) ===
    
    # === Security: Audit Log (compliance) ===
    register :audit_encrypted, E11y::Adapters::FileAdapter.new(
      path: Rails.root.join('log', 'audit'),
      permissions: 0600,  # Read-only for owner
      rotation: :never,   # Never rotate (append-only)
      encryption: true
    )
    
    # === OpenTelemetry: OTLP (collector) ===
    register :otlp, E11y::Adapters::OtlpAdapter.new(
      endpoint: ENV['OTEL_COLLECTOR_URL'] || 'http://localhost:4318',
      protocol: :http,
      headers: { 'X-API-Key' => ENV['OTEL_API_KEY'] }
    )
    
    # === Testing: Memory (tests) ===
    register :memory, E11y::Adapters::MemoryAdapter.new
    
    # === Debug: Console (development) ===
    register :console, E11y::Adapters::ConsoleAdapter.new(
      colored: true,
      pretty: true
    )
  end
  
  # Default adapters per environment
  config.default_adapters = case Rails.env
  when 'production'
    [:loki, :elasticsearch, :otlp]
  when 'staging'
    [:loki, :elasticsearch]
  when 'development'
    [:console, :file]
  when 'test'
    [:memory]
  else
    [:file]
  end
  
  # ============================================================================
  # BUFFER CONFIGURATION
  # ============================================================================
  # Main buffer for event processing
  # Related: ADR-001 (Core Architecture), CONTRADICTION_02 (Buffers)
  
  config.buffer do
    # Ring buffer (SPSC - Single Producer Single Consumer)
    capacity 100_000  # Max events in buffer
    
    # Flush configuration
    flush_interval 200  # milliseconds
    flush_batch_size 500  # events per batch
    
    # Worker threads
    worker_threads 2  # Parallel workers for flushing
    
    # Overflow strategy
    overflow_strategy :drop_oldest  # :drop_oldest, :drop_newest, :block
    
    # Backpressure (load-based throttling)
    backpressure do
      enabled true
      high_watermark 0.8  # 80% full → start sampling
      low_watermark 0.5   # 50% full → resume normal
      
      # Actions on high watermark
      actions [:sample, :increase_flush_rate]
      sample_rate_under_pressure 0.5  # 50% when buffer is 80%+ full
    end
  end
  
  # ============================================================================
  # CIRCUIT BREAKER (Adapter Health Protection)
  # ============================================================================
  # Per-adapter circuit breakers to prevent cascading failures
  # Related: ADR-013 (Reliability & Error Handling), UC-021 (Error Handling)
  
  config.circuit_breaker do
    enabled true
    per_adapter true  # Separate circuit breaker per adapter
    
    # Thresholds
    failure_threshold 5       # Open after 5 consecutive failures
    timeout 30.seconds        # Wait before attempting reset
    success_threshold 2       # Close after 2 consecutive successes
    window 60.seconds         # Rolling window for failure count
    
    # Actions when circuit opens
    on_open do |adapter_name|
      Rails.logger.error "E11y circuit breaker opened for adapter: #{adapter_name}"
      
      # Send alert (bypass E11y to avoid recursion!)
      Events::CircuitBreakerOpened.track(
        adapter: adapter_name,
        severity: :error
      )
    end
    
    # Fallback adapter when circuit is open
    fallback_adapter :file  # Write to file if primary adapter fails
  end
  
  # ============================================================================
  # GLOBAL CONTEXT ENRICHMENT
  # ============================================================================
  # Context added to ALL events automatically
  # Related: UC-002 (Business Events), UC-006 (Trace Context)
  
  config.events do
    # Static context (evaluated once at boot)
    global_context do
      {
        env: Rails.env,
        service: ENV['SERVICE_NAME'] || 'api',
        version: ENV['GIT_SHA'] || 'unknown',
        host: Socket.gethostname,
        deployment_id: ENV['DEPLOYMENT_ID']
      }
    end
    
    # Dynamic context (evaluated per event)
    context_enricher do |event|
      {
        trace_id: Current.trace_id,
        request_id: Current.request_id,
        user_id: Current.user&.id,
        tenant_id: Current.tenant&.id,
        session_id: Current.session_id,
        ip_address: Current.ip_address
      }
    end
  end
  
  # ============================================================================
  # LIFECYCLE HOOKS
  # ============================================================================
  # System-wide event processing hooks
  # Related: ADR-001 (Core Architecture)
  
  config.hooks do
    # Before event is tracked
    before_track do |event|
      # Add custom enrichment
      event.context[:hostname] = Socket.gethostname
      event
    end
    
    # After event is tracked (but before buffered)
    after_track do |event|
      # Custom logic (e.g., trigger side effects)
      if event.severity == :fatal
        # Immediate notification (bypass buffer)
        FatalErrorNotifier.notify(event)
      end
    end
    
    # Before flush to adapters
    before_flush do |events|
      # Last chance to modify events
      events.each do |event|
        event.metadata[:flushed_at] = Time.now.iso8601
      end
      events
    end
    
    # After flush to adapters
    after_flush do |events, results|
      # results = { adapter_name => success/failure }
      failed_adapters = results.select { |_, success| !success }.keys
      
      if failed_adapters.any?
        Rails.logger.error "E11y flush failed for adapters: #{failed_adapters.join(', ')}"
      end
    end
    
    # On error (internal E11y error)
    on_error do |error, context|
      # Don't let E11y crash the app
      Rails.logger.error "E11y internal error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      # Send to Sentry (but not via E11y to avoid recursion!)
      Sentry.capture_exception(error, extra: context) if defined?(Sentry)
    end
  end
  
  # ============================================================================
  # GRACEFUL SHUTDOWN
  # ============================================================================
  # Ensure all events are flushed on application shutdown
  
  config.shutdown do
    # Timeout for graceful shutdown
    timeout 5.seconds
    
    # Flush remaining events on shutdown
    flush_on_shutdown true
    
    # Wait for workers to finish
    wait_for_workers true
  end
  
  # ============================================================================
  # AUDIT RETENTION (Global Default)
  # ============================================================================
  # Default retention for audit events. Can be overridden:
  # 1. Per event: `retention 10.years` in event class
  # 2. Per adapter: tiered storage (hot tier in Loki 30d, cold tier 7y; archival filters by retention_until)
  # 
  # Use Cases:
  # - UC-012: Audit Trail (compliance requirements)
  # - UC-019: Tiered Storage (hot/warm/cold tiers per adapter)
  # 
  # Related: ADR-006 (Security & Compliance)
  
  config.audit_retention = case ENV['JURISDICTION']
                           when 'EU' then 7.years   # GDPR Article 30
                           when 'US' then 10.years  # SOX Section 802
                           else 5.years             # Conservative default
                           end
end

# ============================================================================
# Start E11y (starts background workers)
# ============================================================================
E11y.start!

# Graceful shutdown on SIGTERM/SIGINT
at_exit do
  E11y.stop!(timeout: 5)
end
```

---

**🎯 v1.1 Summary: Infrastructure-Only Configuration**

| Category | Lines | Description |
|----------|-------|-------------|
| **Adapters Registry** | ~120 | Register 12 adapters (Loki, Sentry, ES, etc.) |
| **Buffer Config** | ~30 | Ring buffer, flush settings, backpressure |
| **Circuit Breaker** | ~30 | Per-adapter health protection |
| **Global Context** | ~30 | Context enrichment for ALL events |
| **Lifecycle Hooks** | ~50 | before_track, after_flush, on_error |
| **Graceful Shutdown** | ~10 | Flush on exit |
| **Audit Retention** | ~10 | Configurable per jurisdiction |
| **TOTAL** | **~280 lines** | **Well under 300!** ✅ |

**What's NOT in global config (moved to event-level):**

❌ **Per-event configuration** (see Section 2):
- `severity` - defined in event class
- `rate_limit` - defined in event class
- `sample_rate` - inferred from severity or explicit
- `adapters` - inferred from severity or explicit
- `retention` - inferred from severity or explicit
- `pii_filtering` - defined in event class
- `metric` - defined in event class
- `buffering` - defined in event class
- `slo_target` - defined in event class

**Migration from v1.0:**
- v1.0: **1400+ lines** (global config for everything)
- v1.1: **<300 lines** (infrastructure only)
- **Reduction: ~1120 lines (78%)**

**UC Coverage:**
- ✅ UC-001: Request-Scoped Debug Buffering → event-level `buffering` DSL
- ✅ UC-002: Business Event Tracking → `global_context` + event schemas
- ✅ UC-003: Pattern-Based Metrics → event-level `metric` DSL
- ✅ UC-004: Zero-Config SLO Tracking → conventions + event-level overrides
- ✅ UC-005: Sentry Integration → adapter registry + event-level overrides
- ✅ UC-006: Trace Context → `context_enricher` (global)
- ✅ UC-007: PII Filtering → event-level `pii_filtering` DSL
- ✅ UC-008: OpenTelemetry → OTLP adapter registered
- ✅ UC-011: Rate Limiting → event-level `rate_limit` DSL
- ✅ UC-012: Audit Trail → `audit_retention` (configurable) + C01 two pipelines
- ✅ UC-013: Cardinality Protection → event-level metric config
- ✅ UC-014: Adaptive Sampling → conventions + C11 stratified sampling
- ✅ UC-015: Cost Optimization → event-level retention + routing
- ✅ UC-020: Event Versioning → event-level `version` DSL
- ✅ UC-021: Error Handling → circuit breaker + hooks

**See Section 2 for event-level configuration examples.**

---

## 2. Event Examples (v1.1 - RECOMMENDED ✅)

> **🎯 Event-Level Configuration** (CONTRADICTION_01 Resolution)
>
> **This is the RECOMMENDED approach starting from v1.1!**
>
> E11y now supports **event-level configuration** to reduce global config from 1400+ lines to <300 lines.
> Configuration is distributed across event classes (locality of behavior).
>
> **Benefits over v1.0 global config:**
> - ✅ **78% reduction** in config lines (1400+ → <300)
> - ✅ **Locality of behavior** (config next to schema)
> - ✅ **Better maintainability** (change event = change config)
> - ✅ **DRY via inheritance** (base classes + presets)
> - ✅ **Sensible defaults** (conventions eliminate 80% of config)

### 2.0. Conventions & Sensible Defaults (NEW)

> **Philosophy:** "Explicit over implicit" + conventions = best balance.
>
> E11y applies **sensible defaults** based on conventions to eliminate 80% of configuration.
> All conventions are clearly documented and can be overridden.

**Convention 1: Event Name → Severity**

```ruby
# Convention: *Failed, *Error → :error
class Events::PaymentFailed < E11y::Event::Base
  # ← Auto: severity = :error (inferred from name!)
  schema do; required(:error_code).filled(:string); end
end

# Convention: *Paid, *Succeeded, *Completed → :success
class Events::OrderPaid < E11y::Event::Base
  # ← Auto: severity = :success (inferred from name!)
  schema do; required(:order_id).filled(:string); end
end

# Convention: *Started, *Processing → :info
class Events::OrderProcessing < E11y::Event::Base
  # ← Auto: severity = :info (inferred from name!)
  schema do; required(:order_id).filled(:string); end
end

# Convention: Debug* → :debug
class Events::DebugQuery < E11y::Event::Base
  # ← Auto: severity = :debug (inferred from name!)
  schema do; required(:query).filled(:string); end
end

# Override when needed:
class Events::PaymentFailed < E11y::Event::Base
  severity :warn  # ← Explicit override (unusual case)
end
```

**Convention 2: Severity → Adapters**

```ruby
# Convention: :error/:fatal → [:sentry]
class Events::CriticalError < E11y::Event::Base
  severity :fatal
  # ← Auto: adapters = [:sentry] (errors go to Sentry!)
end

# Convention: :success/:info/:warn → [:loki]
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: adapters = [:loki] (business events to Loki)
end

# Convention: :debug → [:file] (dev), [:loki] (prod with sampling)
class Events::DebugLog < E11y::Event::Base
  severity :debug
  # ← Auto: adapters = [:file] in dev, [:loki] in prod
end
```

**Convention 3: Severity → Sample Rate**

```ruby
# Convention: :error/:fatal → 1.0 (100%, never sample errors!)
class Events::PaymentFailed < E11y::Event::Base
  severity :error
  # ← Auto: sample_rate = 1.0 (100%)
end

# Convention: :warn → 0.5 (50%)
class Events::RateLimitWarning < E11y::Event::Base
  severity :warn
  # ← Auto: sample_rate = 0.5 (50%)
end

# Convention: :success/:info → 0.1 (10%)
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: sample_rate = 0.1 (10%)
end

# Convention: :debug → 0.01 (1%)
class Events::DebugQuery < E11y::Event::Base
  severity :debug
  # ← Auto: sample_rate = 0.01 (1%)
end
```

**Convention 4: Severity → Retention**

```ruby
# Convention: :error/:fatal → 90 days
class Events::CriticalError < E11y::Event::Base
  severity :fatal
  # ← Auto: retention = 90.days
end

# Convention: :info/:success → 30 days
class Events::OrderCreated < E11y::Event::Base
  severity :success
  # ← Auto: retention = 30.days
end

# Convention: :debug → 7 days
class Events::DebugQuery < E11y::Event::Base
  severity :debug
  # ← Auto: retention = 7.days
end
```

**Convention 5: Default Rate Limit**

```ruby
# Convention: 1000 events/sec default (override only for high-volume)
class Events::OrderCreated < E11y::Event::Base
  # ← Auto: rate_limit = 1000 (per second)
  schema do; required(:order_id).filled(:string); end
end

# Override for high-volume events:
class Events::PageView < E11y::Event::Base
  rate_limit 10_000  # ← Explicit override (high-volume)
end
```

**Result: Zero-Config Events**

```ruby
# 90% of events need ONLY schema (zero config!)
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← That's it! All config from conventions:
  #    severity: :success (from name)
  #    adapters: [:loki] (from severity)
  #    sample_rate: 0.1 (from severity)
  #    retention: 30.days (from severity)
  #    rate_limit: 1000 (default)
end
```

**Override conventions when needed:**

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  
  # Override specific settings:
  severity :info  # ← Override convention
  sample_rate 1.0  # ← Never sample orders
  retention 7.years  # ← Financial records
end
```

---

### 2.1. Simple Business Event (with Event-Level Config)

```ruby
# app/events/order_created.rb
module Events
  class OrderCreated < E11y::Event::Base
    severity :success
    
    schema do
      required(:order_id).filled(:string)
      required(:user_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      optional(:items_count).filled(:integer)
    end
    
    # ✨ NEW: Event-level configuration (right next to schema!)
    rate_limit 1000, window: 1.second  # Max 1000 events/sec
    sample_rate 0.1                     # 10% sampling
    retention 30.days                   # Keep for 30 days
    
    # Auto-create metric: app_orders_created_total
    metric :counter,
           name: 'orders.created.total',
           tags: [:currency],
           comment: 'Total orders created'
  end
end

# Usage (unchanged)
Events::OrderCreated.track(
  order_id: 'ord_123',
  user_id: 'usr_456',
  amount: 99.99,
  currency: 'USD',
  items_count: 3
)
```

### 2.2. "Fat" Event with Multiple Features

```ruby
# app/events/payment_processed.rb
module Events
  class PaymentProcessed < E11y::Event::Base
    # === UC-002: Business Event Tracking ===
    severity :success
    
    schema do
      required(:transaction_id).filled(:string)
      required(:order_id).filled(:string)
      required(:user_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      required(:payment_method).filled(:string)
      required(:processor).filled(:string)  # stripe, paypal, etc.
      
      optional(:card_last4).filled(:string)
      optional(:card_brand).filled(:string)
      optional(:billing_country).filled(:string)
      optional(:risk_score).filled(:float)
      optional(:processor_fee).filled(:decimal)
      optional(:net_amount).filled(:decimal)
      
      # For tracing
      optional(:trace_id).filled(:string)
      optional(:span_id).filled(:string)
    end
    
    # === UC-003: Pattern-Based Metrics ===
    metric :counter,
           name: 'payments.processed.total',
           tags: [:currency, :payment_method, :processor],
           comment: 'Total successful payments'
    
    metric :histogram,
           name: 'payments.processed.amount',
           tags: [:currency, :payment_method],
           buckets: [10, 50, 100, 500, 1000, 5000, 10000],
           comment: 'Distribution of payment amounts'
    
    metric :histogram,
           name: 'payments.risk_score',
           tags: [:payment_method],
           buckets: [0.1, 0.3, 0.5, 0.7, 0.9, 1.0],
           comment: 'Payment risk score distribution'
    
    # === UC-004: Zero-Config SLO Tracking ===
    # (Automatically tracked if amount in payload)
    
    # === UC-002: Per-Event Adapter Override ===
    adapters_strategy :append
    adapters [:loki, :elasticsearch, :otlp]
    
    # === UC-007: PII Filtering ===
    # card_last4, billing_country will be filtered if in PII config
    
    # === UC-014: Adaptive Sampling ===
    # High-value payments sampled at 100% (see value_based sampling config)
    
    # === UC-015: Cost Optimization ===
    # retention_tagging will add retention_days: 90
    
    # Custom validation
    validate do
      if amount <= 0
        errors.add(:amount, 'must be positive')
      end
      
      if risk_score && risk_score > 0.9
        errors.add(:risk_score, 'suspiciously high')
      end
    end
  end
end

# Usage with duration measurement
Events::PaymentProcessed.track(
  transaction_id: 'txn_abc123',
  order_id: 'ord_456',
  user_id: 'usr_789',
  amount: 1999.99,
  currency: 'USD',
  payment_method: 'credit_card',
  processor: 'stripe',
  card_last4: '4242',  # Will be filtered
  card_brand: 'visa',
  billing_country: 'US',
  risk_score: 0.12,
  processor_fee: 59.99,
  net_amount: 1940.00
) do
  # Measure duration of block
  StripePaymentProcessor.charge(...)
end
```

### 2.3. "Fat" Security/Audit Event

```ruby
# app/events/user_permission_changed.rb
module Events
  class UserPermissionChanged < E11y::AuditEvent
    # === UC-012: Audit Trail ===
    audit_retention 7.years
    audit_reason 'compliance_regulatory'
    severity :warn
    
    signing do
      enabled true  # Cryptographically sign this event
      algorithm :ed25519
    end
    
    schema do
      required(:user_id).filled(:string)
      required(:user_email).filled(:string)
      required(:old_role).filled(:string)
      required(:new_role).filled(:string)
      required(:changed_by_user_id).filled(:string)
      required(:changed_by_email).filled(:string)
      required(:reason).filled(:string)
      required(:ip_address).filled(:string)
      required(:user_agent).filled(:string)
      
      optional(:approval_ticket_id).filled(:string)
      optional(:approval_required).filled(:bool)
    end
    
    # === UC-002: Per-Event Adapter Override ===
    # Audit events go to special audit log + Elasticsearch
    adapters [:audit_file, :elasticsearch]
    
    # === UC-003: Metrics ===
    metric :counter,
           name: 'security.permissions.changed.total',
           tags: [:old_role, :new_role],
           comment: 'User permission changes'
    
    # === UC-005: Sentry Integration ===
    # Don't send to Sentry (not an error)
    exclude_from_sentry true
    
    # === UC-007: PII Filtering ===
    # email, ip_address, user_agent will be filtered unless in allowlist
    
    # === UC-011: Rate Limiting ===
    # Has dedicated rate limit in config: per_event 'security.*'
    
    # === UC-014: Adaptive Sampling ===
    # Security events always sampled at 100% (see content_based.always_sample)
    
    # Custom validation
    validate do
      if old_role == new_role
        errors.add(:base, 'role unchanged')
      end
      
      VALID_ROLES = %w[user admin superadmin]
      unless VALID_ROLES.include?(old_role) && VALID_ROLES.include?(new_role)
        errors.add(:base, 'invalid role')
      end
    end
  end
end

# Usage
Events::UserPermissionChanged.track(
  user_id: 'usr_123',
  user_email: 'john@example.com',  # Filtered
  old_role: 'user',
  new_role: 'admin',
  changed_by_user_id: 'usr_admin',
  changed_by_email: 'admin@example.com',  # Filtered
  reason: 'User promoted to admin for project X',
  ip_address: '192.168.1.1',  # Filtered
  user_agent: 'Mozilla/5.0...',  # Filtered
  approval_ticket_id: 'JIRA-1234',
  approval_required: true
)
```

### 2.4. "Fat" Error Event with Full Context

```ruby
# app/events/critical_system_error.rb
module Events
  class CriticalSystemError < E11y::Event::Base
    # === UC-002: Business Event Tracking ===
    severity :fatal
    
    schema do
      required(:error_class).filled(:string)
      required(:error_message).filled(:string)
      required(:error_backtrace).array(:string)
      
      required(:controller).filled(:string)
      required(:action).filled(:string)
      required(:http_method).filled(:string)
      required(:path).filled(:string)
      
      optional(:user_id).filled(:string)
      optional(:session_id).filled(:string)
      optional(:request_id).filled(:string)
      optional(:trace_id).filled(:string)
      
      optional(:params).hash
      optional(:headers).hash
      optional(:environment_variables).hash
      
      optional(:database_state).filled(:string)
      optional(:redis_state).filled(:string)
      optional(:external_api_status).hash
    end
    
    # === UC-002: Per-Event Adapter Override ===
    # Critical errors go EVERYWHERE
    adapters [:loki, :elasticsearch, :sentry, :pagerduty, :slack, :file]
    
    # === UC-003: Metrics ===
    metric :counter,
           name: 'errors.critical.total',
           tags: [:error_class, :controller, :action],
           comment: 'Critical system errors'
    
    # === UC-005: Sentry Integration ===
    # Automatically sent to Sentry (severity: fatal)
    sentry_options do
      level :fatal
      
      # Custom fingerprint
      fingerprint [:error_class, :controller, :action]
      
      # Extra context
      extra do |event|
        {
          database_state: event.payload[:database_state],
          redis_state: event.payload[:redis_state],
          external_api_status: event.payload[:external_api_status]
        }
      end
      
      # Tags
      tags do |event|
        {
          controller: event.payload[:controller],
          action: event.payload[:action]
        }
      end
    end
    
    # === UC-006: Trace Context ===
    # trace_id automatically extracted from request or generated
    
    # === UC-007: PII Filtering ===
    # params, headers, environment_variables will be deeply scanned for PII
    
    # === UC-011: Rate Limiting ===
    # Has bypass in config: bypass_for event_types: ['system.critical']
    
    # === UC-014: Adaptive Sampling ===
    # Fatal errors always sampled at 100%
    
    # === UC-015: Cost Optimization ===
    # payload_minimization will truncate long backtraces
  end
end

# Usage (typically in exception handler)
begin
  # Some critical operation
  PaymentProcessor.charge(order)
rescue => e
  Events::CriticalSystemError.track(
    error_class: e.class.name,
    error_message: e.message,
    error_backtrace: e.backtrace,
    
    controller: 'OrdersController',
    action: 'create',
    http_method: 'POST',
    path: '/api/orders',
    
    user_id: current_user&.id,
    session_id: session.id,
    request_id: request.uuid,
    trace_id: Current.trace_id,
    
    params: params.to_unsafe_h,  # Will be PII-filtered
    headers: request.headers.to_h,  # Will be PII-filtered
    environment_variables: ENV.to_h,  # Will be PII-filtered
    
    database_state: 'connected',
    redis_state: 'disconnected',  # ← The problem!
    external_api_status: {
      stripe: 'healthy',
      sendgrid: 'healthy'
    }
  )
  
  # Re-raise
  raise
end
```

### 2.5. Event Inheritance & Base Classes (NEW - CONTRADICTION_01 Resolution)

> **🎯 Pattern:** Use inheritance to share common configuration across related events.

**Base class for payment events:**

```ruby
# app/events/base_payment_event.rb
module Events
  class BasePaymentEvent < E11y::Event::Base
    # Common payment event configuration
    severity :success
    rate_limit 1000
    sample_rate 1.0  # Never sample payments (high-value)
    retention 7.years  # Financial records
    adapters [:loki, :sentry]
    
    # Common PII filtering
    pii_filtering do
      hashes :email, :user_id  # Pseudonymize for searchability
      allows :order_id, :amount, :currency  # Non-PII
    end
    
    # Common metric
    metric :counter,
           name: 'payments.total',
           tags: [:currency, :payment_method],
           comment: 'Total payment events'
  end
end

# Inherit from base (1-2 lines per event!)
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)
    required(:payment_method).filled(:string)
  end
  # ← Inherits ALL config from BasePaymentEvent!
end

class Events::PaymentFailed < Events::BasePaymentEvent
  severity :error  # ← Override base (errors, not success)
  
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:error_code).filled(:string)
    required(:error_message).filled(:string)
  end
  # ← Inherits: rate_limit, sample_rate, retention, adapters, PII rules
end
```

**Base class for audit events:**

```ruby
# app/events/base_audit_event.rb
module Events
  class BaseAuditEvent < E11y::Event::Base
    # Common audit configuration
    severity :warn
    audit_event true
    adapters [:audit_encrypted]
    # ← Auto-set by audit_event:
    #    retention = E11y.config.audit_retention (default: 7.years, configurable per jurisdiction!)
    #    rate_limiting = false (LOCKED - cannot override!)
    #    sampling = false (LOCKED - cannot override!)
    
    # Cryptographic signing
    signing do
      enabled true
      algorithm :ed25519
    end
    
    # Common audit fields
    contains_pii true
    pii_filtering do
      # Audit: keep original data (GDPR Art. 6(1)(c))
      # Filtering skipped for :audit_encrypted adapter
    end
  end
end

# Inherit from base
class Events::UserPermissionChanged < Events::BaseAuditEvent
  schema do
    required(:user_id).filled(:string)
    required(:user_email).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
    required(:changed_by_user_id).filled(:string)
    required(:ip_address).filled(:string)
  end
  # ← Inherits: audit_event, adapters, retention, signing, etc.
end
```

**Base class for debug events:**

```ruby
# app/events/base_debug_event.rb
module Events
  class BaseDebugEvent < E11y::Event::Base
    # Common debug configuration
    severity :debug
    rate_limit 100  # Low limit
    sample_rate 0.01  # 1% sampling
    retention 7.days  # Short retention
    adapters [:file]  # Local file only (cheap)
    
    # No PII in debug events
    contains_pii false
  end
end

# Inherit from base
class Events::DebugSqlQuery < Events::BaseDebugEvent
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:float)
  end
  # ← Inherits: severity, rate_limit, sample_rate, retention, adapters
end
```

**Benefits of inheritance:**
- ✅ 1-2 lines per event (just schema!)
- ✅ DRY (common config shared)
- ✅ Consistency (all payments have same config)
- ✅ Easy to change (update base class → all events updated)

---

### 2.5a. Preset Modules (NEW - CONTRADICTION_01 Resolution)

> **🎯 Pattern:** Use preset modules for 1-line configuration includes (Rails-style concerns).

**E11y provides built-in presets:**

```ruby
# lib/e11y/presets/high_value_event.rb
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        rate_limit 10_000
        sample_rate 1.0  # Never sample (100%)
        retention 7.years
        adapters [:loki, :sentry]
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        severity :debug
        rate_limit 100
        sample_rate 0.01  # 1% sampling
        retention 7.days
        adapters [:file]  # Local only
      end
    end
    
    module AuditEvent
      extend ActiveSupport::Concern
      included do
        audit_event true
        adapters [:audit_encrypted]
        # ← Auto-set by audit_event:
        #    retention = E11y.config.audit_retention (configurable!)
        #    rate_limiting = false (LOCKED!)
        #    sampling = false (LOCKED!)
      end
    end
  end
end
```

**Usage (1-line includes!):**

```ruby
# High-value event
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← All config inherited!
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

# Debug event
class Events::DebugSqlQuery < E11y::Event::Base
  include E11y::Presets::DebugEvent  # ← All config inherited!
  
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:float)
  end
end

# Audit event
class Events::UserDeleted < E11y::Event::Base
  include E11y::Presets::AuditEvent  # ← All config inherited!
  
  schema do
    required(:user_id).filled(:string)
    required(:deleted_by).filled(:string)
    required(:reason).filled(:string)
  end
end
```

**Custom presets (project-specific):**

```ruby
# app/events/presets/critical_business_event.rb
module Events
  module Presets
    module CriticalBusinessEvent
      extend ActiveSupport::Concern
      included do
        severity :success
        rate_limit 5000
        sample_rate 1.0  # Never sample
        retention 7.years
        adapters [:loki, :elasticsearch]
        
        # Send Slack notification
        adapters_strategy :append
        adapters [:slack_business]
        
        # Common metric
        metric :counter,
               name: 'critical_business_events.total',
               tags: [:event_name]
      end
    end
  end
end

# Usage:
class Events::LargeOrderPlaced < E11y::Event::Base
  include Events::Presets::CriticalBusinessEvent
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end
```

**Benefits:**
- ✅ 1-line includes (even simpler than inheritance!)
- ✅ Mix multiple presets (include HighValueEvent, AuditEvent)
- ✅ Rails-style familiar pattern (ActiveSupport::Concern)
- ✅ Easy to create custom presets

---

### 2.6. "Fat" Background Job Event

```ruby
# app/events/background_job_executed.rb
module Events
  class BackgroundJobExecuted < E11y::Event::Base
    # === UC-010: Background Job Tracking ===
    severity :info
    
    schema do
      required(:job_id).filled(:string)
      required(:job_class).filled(:string)
      required(:queue_name).filled(:string)
      required(:status).filled(:string)  # enqueued, started, success, failed, retry
      
      required(:enqueued_at).filled(:time)
      optional(:started_at).filled(:time)
      optional(:finished_at).filled(:time)
      optional(:duration_ms).filled(:float)
      optional(:queue_latency_ms).filled(:float)  # started_at - enqueued_at
      
      optional(:arguments).array
      optional(:retry_count).filled(:integer)
      optional(:error_class).filled(:string)
      optional(:error_message).filled(:string)
      
      # === UC-006: Trace Context ===
      optional(:trace_id).filled(:string)
      optional(:span_id).filled(:string)
      optional(:parent_span_id).filled(:string)
      
      # === UC-009: Multi-Service Tracing ===
      optional(:origin_service).filled(:string)
      optional(:origin_request_id).filled(:string)
    end
    
    # === UC-003: Metrics ===
    metric :counter,
           name: 'background_jobs.executed.total',
           tags: [:job_class, :queue_name, :status],
           comment: 'Background jobs executed'
    
    metric :histogram,
           name: 'background_jobs.duration',
           tags: [:job_class, :queue_name],
           buckets: [10, 50, 100, 500, 1000, 5000, 10000, 30000],
           comment: 'Job execution duration'
    
    metric :histogram,
           name: 'background_jobs.queue_latency',
           tags: [:job_class, :queue_name],
           buckets: [10, 100, 1000, 5000, 10000, 30000, 60000],
           comment: 'Time from enqueue to start'
    
    # === UC-004: Zero-Config SLO Tracking ===
    # Automatically tracked for Sidekiq/ActiveJob
    
    # === UC-014: Adaptive Sampling ===
    # Job failures sampled at 100%, successes at 10%
  end
end

# Usage (auto-instrumented, but can be manual)
Events::BackgroundJobExecuted.track(
  job_id: 'jid_abc123',
  job_class: 'SendWelcomeEmailJob',
  queue_name: 'mailers',
  status: 'success',
  
  enqueued_at: 2.minutes.ago,
  started_at: 30.seconds.ago,
  finished_at: Time.now,
  duration_ms: 1234.56,
  queue_latency_ms: 90000,  # 90 seconds wait
  
  arguments: ['user_123', { template: 'welcome_v2' }],
  retry_count: 0,
  
  # Trace context (propagated from original HTTP request)
  trace_id: 'trace_xyz789',
  span_id: 'span_job_001',
  parent_span_id: 'span_http_request_001',
  
  origin_service: 'web-api',
  origin_request_id: 'req_original'
)
```

---

### 2.7. Use Case Coverage: v1.1 Event-Level Configuration

> **🎯 How Each UC Works in v1.1**
>
> This section demonstrates how v1.1 event-level configuration + conventions + infrastructure-only global config handles all 22 Use Cases with minimal code.
>
> **Key Insight:** Most UCs need **0 lines** in global config! Configuration lives where it belongs: in event classes.

#### UC-001: Request-Scoped Debug Buffering

**v1.0 (OLD):** 50+ lines in global config for request scope setup
**v1.1 (NEW):** Event-level `buffering` DSL

```ruby
# ✅ v1.1: Event-level buffering config
class Events::DebugQuery < E11y::Event::Base
  severity :debug
  
  buffering :request_scope,  # ← Buffer in request, flush on completion
            max_events: 1000,
            flush_on: :request_end
  
  schema { required(:sql).filled(:string) }
end

# Global config: ZERO lines needed! (buffer infrastructure already configured in Section 1)
```

**Lines saved:** 50+ (v1.0 global) → 0 (v1.1 event-level)

---

#### UC-002: Business Event Tracking

**v1.0 (OLD):** Per-event adapter routing in global config
**v1.1 (NEW):** Conventions + event-level overrides

```ruby
# ✅ v1.1: Convention-based (zero config!)
class Events::OrderCreated < E11y::Event::Base
  # severity :success ← Auto-inferred from name "Created"
  # adapters [:loki] ← Auto from severity
  # sample_rate 1.0 ← Auto from severity (business events = 100%)
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# Global config: ZERO lines! Conventions handle everything.
# Global context (user_id, tenant_id) enriched via Section 1 hooks.
```

**Lines saved:** 30-40 (v1.0 per-event routing) → 0 (v1.1 conventions)

---

#### UC-003: Pattern-Based Metrics

**v1.0 (OLD):** 100+ lines in global config for metric patterns
**v1.1 (NEW):** Event-level `metric` DSL

```ruby
# ✅ v1.1: Event-level metrics (locality of behavior!)
class Events::OrderCreated < E11y::Event::Base
  severity :success
  
  metric :counter,
         name: 'orders.created.total',
         tags: [:payment_method, :country],
         comment: 'Orders created'
  
  metric :histogram,
         name: 'orders.value',
         tags: [:country],
         buckets: [10, 50, 100, 500, 1000],
         comment: 'Order value distribution'
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:payment_method).filled(:string)
    required(:country).filled(:string)
  end
end

# Global config: ZERO lines! Metrics defined where they're used.
```

**Lines saved:** 100+ (v1.0 global patterns) → 0 (v1.1 event-level)

---

#### UC-004: Zero-Config SLO Tracking

**v1.0 (OLD):** 80+ lines for SLO definitions per event type
**v1.1 (NEW):** Conventions infer SLO targets from severity

```ruby
# ✅ v1.1: Convention-based SLO (zero config!)
class Events::ApiRequestCompleted < E11y::Event::Base
  severity :success
  # slo_target 0.999 ← Auto from severity (success = 99.9%)
  # slo_budget 0.001 ← Auto calculated
  
  schema do
    required(:status_code).filled(:integer)
    required(:duration_ms).filled(:float)
  end
end

# Override only when needed:
class Events::CriticalPaymentProcessed < E11y::Event::Base
  severity :success
  slo_target 0.9999  # ← Explicit override (99.99% for payments)
  
  schema { required(:payment_id).filled(:string) }
end

# Global config: ZERO lines! Conventions + optional overrides.
```

**Lines saved:** 80+ (v1.0 per-event SLO) → 0 (v1.1 conventions)

---

#### UC-005: Sentry Integration

**v1.0 (OLD):** 40+ lines for Sentry routing rules in global config
**v1.1 (NEW):** Conventions route errors to Sentry automatically

```ruby
# ✅ v1.1: Convention-based (zero config!)
class Events::PaymentFailed < E11y::Event::Base
  severity :error
  # adapters [:sentry] ← Auto from severity! (errors → Sentry)
  # sample_rate 1.0 ← Auto (never sample errors!)
  
  schema do
    required(:payment_id).filled(:string)
    required(:error_code).filled(:string)
  end
end

# Global config: 8 lines (Sentry adapter registration in Section 1)
# Routing: 0 lines (convention handles it!)
```

**Lines saved:** 40+ (v1.0 routing rules) → 0 (v1.1 conventions)

---

#### UC-006: Trace Context Management

**v1.0 (OLD):** 60+ lines for trace context propagation in global config
**v1.1 (NEW):** Global hooks (infrastructure-level, Section 1)

```ruby
# ✅ v1.1: Global infrastructure (already in Section 1!)
E11y.configure do |config|
  config.context_enricher do |event, context|
    event.context[:trace_id] = context[:trace_id] || SecureRandom.uuid
    event.context[:span_id] = SecureRandom.hex(8)
    event.context[:parent_span_id] = context[:parent_span_id]
    event
  end
end

# Event classes: ZERO extra config needed!
class Events::ApiRequest < E11y::Event::Base
  # trace_id/span_id auto-added by global enricher
  schema { required(:endpoint).filled(:string) }
end
```

**Lines saved:** 60+ (v1.0 duplicated per event) → ~20 (v1.1 global hook, reused)

---

#### UC-007: PII Filtering

**v1.0 (OLD):** 70+ lines in global config for PII patterns
**v1.1 (NEW):** Event-level `pii_filtering` DSL

```ruby
# ✅ v1.1: Event-level PII config (locality!)
class Events::UserRegistered < E11y::Event::Base
  severity :success
  
  pii_filtering enabled: true,
                fields: [:email, :phone, :ip_address],
                strategy: :hash,  # or :redact, :encrypt
                salt: ENV['PII_SALT']
  
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:phone).filled(:string)
    optional(:ip_address).filled(:string)
  end
end

# Global config: ZERO lines! PII filtering per event.
```

**Lines saved:** 70+ (v1.0 global patterns) → 0 (v1.1 event-level)

---

#### UC-008: OpenTelemetry Integration

**v1.0 (OLD):** 50+ lines for OTLP exporter config
**v1.1 (NEW):** Adapter registration (Section 1, infrastructure)

```ruby
# ✅ v1.1: Adapter registration (already in Section 1!)
config.adapters do
  register :otlp, E11y::Adapters::OTLPAdapter.new(
    endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'],
    headers: { 'Authorization' => "Bearer #{ENV['OTEL_TOKEN']}" },
    protocol: :grpc
  )
end

# Event classes: ZERO extra config!
class Events::OrderCreated < E11y::Event::Base
  # adapters [:loki, :otlp] ← Add :otlp if needed
  schema { required(:order_id).filled(:string) }
end
```

**Lines saved:** 50+ (v1.0 per-event OTLP) → ~10 (v1.1 adapter registration, reused)

---

#### UC-009: Multi-Service Tracing

**v1.0 (OLD):** 80+ lines for cross-service trace propagation
**v1.1 (NEW):** Global hooks + event-level schema

```ruby
# ✅ v1.1: Global hook (Section 1) + event schema
# Global: Already configured in Section 1 (context_enricher)

class Events::ServiceCallInitiated < E11y::Event::Base
  severity :info
  
  schema do
    required(:service_name).filled(:string)
    required(:endpoint).filled(:string)
    # trace_id, span_id, parent_span_id auto-added by enricher
  end
end

# Cross-service: E11y.current_context propagated via HTTP headers
# No global config needed beyond Section 1 hook!
```

**Lines saved:** 80+ (v1.0) → 0 (v1.1 event-level, hook reused)

---

#### UC-010: Background Job Tracking

**v1.0 (OLD):** 60+ lines for Sidekiq/ActiveJob instrumentation
**v1.1 (NEW):** Event-level config + auto-instrumentation

```ruby
# ✅ v1.1: Event class (already shown in Section 2.6!)
class Events::BackgroundJobExecuted < E11y::Event::Base
  severity :info
  
  metric :counter, name: 'jobs.executed.total', tags: [:job_class, :status]
  metric :histogram, name: 'jobs.duration', tags: [:job_class]
  
  schema do
    required(:job_id).filled(:string)
    required(:job_class).filled(:string)
    required(:status).filled(:string)
  end
end

# Global config: ZERO lines! (auto-instrumentation via Rails integration)
```

**Lines saved:** 60+ (v1.0 instrumentation config) → 0 (v1.1 auto + event-level)

---

#### UC-011: Rate Limiting

**v1.0 (OLD):** 100+ lines for rate limiting rules in global config
**v1.1 (NEW):** Event-level `rate_limit` DSL

```ruby
# ✅ v1.1: Event-level rate limiting
class Events::UserLogin < E11y::Event::Base
  severity :info
  
  rate_limit key: [:user_id],
             limit: 10,
             period: 1.minute,
             on_exceeded: :throttle,  # :drop, :sample, :throttle
             sample_rate: 0.1  # If :throttle
  
  schema { required(:user_id).filled(:string) }
end

# Global config: ZERO lines! Rate limiting per event.
```

**Lines saved:** 100+ (v1.0 global rules) → 0 (v1.1 event-level)

---

#### UC-012: Audit Trail (C01: Two Pipelines) ⚠️

**v1.0 (OLD):** 90+ lines for audit config in global config
**v1.1 (NEW):** Event-level `audit_event` + separate pipeline (C01 Resolution)

```ruby
# ✅ v1.1: Event-level audit config with separate pipeline
class Events::GdprDeletionRequested < E11y::Event::Base
  audit_event true  # ← Uses SEPARATE AUDIT PIPELINE (C01)
                    # ← Locks: rate_limiting=false, sampling=false
                    # ← NO PII filtering (signs ORIGINAL data!)
  
  retention 10.years  # ← Override global default (EU: 7y, US: 10y)
  severity :warn
  
  schema do
    required(:user_id).filled(:string)
    required(:reason).filled(:string)
    required(:requested_by).filled(:string)
    required(:admin_email).filled(:string)  # ← PII preserved for non-repudiation!
    required(:ip_address).filled(:string)   # ← PII preserved for legal compliance
  end
end

# === Pipeline Routing (Automatic) ===
#
# Standard Events (audit_event false):
#   1. Validation → 2. PII Filtering ✅ → 3. Sampling ✅ → 4. Adapters
#
# Audit Events (audit_event true):
#   1. Validation → 2. Cryptographic Signing ✅ (ORIGINAL data!)
#   → 3. Encryption (AES-256-GCM) → 4. Audit Adapter
#   → NO PII filtering (C01: non-repudiation requirement)
#   → NO rate limiting (audit events never dropped)
#   → NO sampling (100% captured)
#
# Compensating Controls:
# - ✅ Encryption at rest (AES-256-GCM mandatory)
# - ✅ Access control (auditor role only)
# - ✅ Separate storage (isolated from app DB)
#
# Related: ADR-015 §3.3 (C01 Resolution), UC-007 (PII per-adapter)

# Global config: 5 lines (audit_retention default in Section 1)
# Per-event: retention overridable, adapters auto-routed to audit pipeline
```

**Lines saved:** 90+ (v1.0 global audit rules) → ~5 (v1.1 global default + event-level)

**Key Innovation (C01):** Separate pipeline for audit events that skips PII filtering 
to preserve non-repudiation (SOX, HIPAA, GDPR Art. 30), with compensating controls 
(encryption, access control, separate storage).

---

#### UC-013: High Cardinality Protection

**v1.0 (OLD):** 70+ lines for cardinality limits in global config
**v1.1 (NEW):** Event-level metric config with `max_cardinality`

```ruby
# ✅ v1.1: Event-level cardinality protection
class Events::ApiRequest < E11y::Event::Base
  severity :info
  
  metric :counter,
         name: 'api.requests.total',
         tags: [:endpoint],  # High cardinality!
         max_cardinality: 1000,  # ← Protection!
         on_exceeded: :aggregate  # or :drop, :sample
  
  schema { required(:endpoint).filled(:string) }
end

# Global config: ZERO lines! Protection per metric.
```

**Lines saved:** 70+ (v1.0 global cardinality) → 0 (v1.1 event-level)

---

#### UC-014: Adaptive Sampling (C11: Stratified Sampling) ⚠️

**v1.0 (OLD):** 120+ lines for adaptive sampling strategies
**v1.1 (NEW):** Conventions + stratified sampling by severity (C11 Resolution)

```ruby
# ✅ v1.1: Convention-based stratified sampling (auto!)
class Events::ApiRequest < E11y::Event::Base
  # === Severity-Based Sampling (C11: Stratified Sampling) ===
  #
  # Convention: Severity → Sample Rate (auto!)
  # :error/:fatal → 1.0 (100%, never sample errors!)
  # :warn        → 0.5 (50%)
  # :success     → 0.1 (10%)
  # :info        → 0.1 (10%)
  # :debug       → 0.01 (1%)
  #
  # Why Stratified? Random sampling breaks SLO metrics!
  # - Errors are rare (5%) but critical → 100% capture
  # - Success is common (95%) but less critical → 10% sample
  # → Cost savings: 85.5% reduction while maintaining accuracy
  
  severity :success
  # sample_rate 0.1 ← Auto from severity (success = 10%)
  
  schema do
    required(:endpoint).filled(:string)
    required(:status).filled(:integer)
  end
end

# Override for high-value events:
class Events::PaymentProcessed < E11y::Event::Base
  severity :success
  sample_rate 1.0  # ← Override: NEVER sample payments (high-value)
  adaptive_sampling enabled: false  # ← Disable adaptive
  
  schema do
    required(:amount).filled(:float)
    required(:payment_id).filled(:string)
  end
end

# === SLO Calculation with Sampling Correction ===
#
# Problem: Random sampling (e.g., 10% of ALL events) skews error rates
#   1000 requests: 950 success (95%), 50 errors (5%)
#   Random 10% sample: might get 98 success, 2 errors → 98% success rate ❌ WRONG!
#
# Solution: Stratified sampling + correction
#   Sample 50 errors (100% × 50)
#   Sample 95 success (10% × 950)
#   Total: 145 events
#   Corrected success rate: (95/0.1) / ((95/0.1) + (50/1.0)) = 95% ✅ CORRECT!
#
# Related: ADR-009 §3.7 (C11 Resolution), UC-004 (SLO with correction)

# Global config: ZERO lines! Conventions + event-level overrides.
```

**Lines saved:** 120+ (v1.0 global strategies) → 0 (v1.1 conventions)

**Key Innovation (C11):** Stratified sampling by severity preserves error/success ratio 
for accurate SLO metrics (100% errors, 10% success) while achieving 85.5% cost savings.

---

#### UC-015: Cost Optimization

**v1.0 (OLD):** 150+ lines for cost optimization rules
**v1.1 (NEW):** Event-level retention + routing + sampling

```ruby
# ✅ v1.1: Event-level cost optimization
class Events::PageView < E11y::Event::Base
  severity :debug
  
  # Cost optimization via event-level config:
  retention 7.days  # ← Short retention for cheap events
  sample_rate 0.01  # ← 1% sampling
  adapters [:loki]  # ← Cheap adapter (not Datadog!)
  
  compression :zstd, level: 3  # ← Compression
  
  schema { required(:page_url).filled(:string) }
end

# Global config: ~30 lines (compression settings in Section 1)
# Per-event routing/retention: 0 lines (event-level)
```

**Lines saved:** 150+ (v1.0 global cost rules) → ~30 (v1.1 global compression + event-level)

---

#### UC-016: Rails Logger Migration

**v1.0 (OLD):** 40+ lines for Rails.logger compatibility shim
**v1.1 (NEW):** Auto-instrumentation (Rails integration, Section 1)

```ruby
# ✅ v1.1: Auto-instrumentation (zero config!)
# Rails.logger.info → auto-converted to E11y::Event

# Global config: Already in Section 1 (Rails integration)
# Enable with: config.rails_logger_integration = true

# Custom events still possible:
class Events::RailsLog < E11y::Event::Base
  severity :info
  schema { required(:message).filled(:string) }
end
```

**Lines saved:** 40+ (v1.0 shim config) → 1 (v1.1 enable flag)

---

#### UC-017: Local Development

**v1.0 (OLD):** 50+ lines for dev environment config
**v1.1 (NEW):** Environment-specific adapter routing (conventions)

```ruby
# ✅ v1.1: Convention-based dev config
# Global config (Section 1): Adapters registered per environment

config.adapters do
  if Rails.env.development?
    register :file, E11y::Adapters::FileAdapter.new(path: 'log/e11y.log')
    register :console, E11y::Adapters::ConsoleAdapter.new
  else
    register :loki, E11y::Adapters::LokiAdapter.new(url: ENV['LOKI_URL'])
  end
end

# Event classes: ZERO changes needed!
# Conventions route events based on registered adapters.
```

**Lines saved:** 50+ (v1.0 per-env duplication) → ~10 (v1.1 conditional adapter registration)

---

#### UC-018: Testing Events

**v1.0 (OLD):** 60+ lines for test adapter config
**v1.1 (NEW):** Test adapter (Section 1) + event classes unchanged

```ruby
# ✅ v1.1: Test adapter (already in Section 1!)
# spec/support/e11y.rb
E11y.configure do |config|
  config.adapters do
    register :test, E11y::Adapters::TestAdapter.new  # ← Memory-only
  end
end

# Tests: Query captured events
RSpec.describe 'Order creation' do
  it 'tracks order.created event' do
    create_order
    
    event = E11y.adapter(:test).events.last
    expect(event.name).to eq('order.created')
    expect(event.payload[:order_id]).to eq('123')
  end
end

# Event classes: ZERO changes! Same code in dev/test/prod.
```

**Lines saved:** 60+ (v1.0 test-specific config) → ~5 (v1.1 test adapter registration)

---

#### UC-019: Tiered Storage (Retention Tagging)

**v1.0 (OLD):** 80+ lines for tiered storage rules in global config
**v1.1 (NEW):** Event-level retention + adapter-level tiering

```ruby
# ✅ v1.1: Event-level retention
class Events::OrderCreated < E11y::Event::Base
  severity :success
  retention 30.days  # ← Business event: 30 days
  adapters [:loki]
end

class Events::AuditLog < E11y::Event::Base
  audit_event true
  retention 7.years  # ← Audit: 7 years
  adapters [:loki]  # ← Loki = hot; archival job filters by retention_until
end

# Global config: Loki for hot storage
config.adapters do
  register :loki, E11y::Adapters::LokiAdapter.new(retention: 30.days)
end

# Archival: External jobs filter Loki by retention_until (ISO8601) for tier migration
```

**Lines saved:** 80+ (v1.0 global tiering) → ~20 (v1.1 adapter-level + event-level)

---

#### UC-020: Event Versioning

**v1.0 (OLD):** 50+ lines for versioning config in global config
**v1.1 (NEW):** Event-level `version` DSL

```ruby
# ✅ v1.1: Event-level versioning
class Events::OrderCreated < E11y::Event::Base
  version 2  # ← Event schema version
  
  schema do
    required(:order_id).filled(:string)
    required(:amount_cents).filled(:integer)  # v2: changed from :amount
    optional(:currency).filled(:string)  # v2: added
  end
end

# Global config: ZERO lines! Versioning per event.
# Version added to event metadata automatically.
```

**Lines saved:** 50+ (v1.0 global versioning) → 0 (v1.1 event-level)

---

#### UC-021: Error Handling & Retry (Circuit Breaker, DLQ)

**v1.0 (OLD):** 100+ lines for circuit breaker + DLQ config
**v1.1 (NEW):** Infrastructure-level (Section 1) + event-level retry

```ruby
# ✅ v1.1: Infrastructure in Section 1 (already configured!)
config.circuit_breaker do
  enabled true
  per_adapter true
  failure_threshold 5
  timeout 30.seconds
end

config.dead_letter_queue do
  enabled true
  adapter :file  # or :redis
  max_retries 3
end

# Event classes: ZERO extra config!
# Circuit breaker + DLQ apply to ALL events automatically.

# Optional: Per-event retry policy
class Events::CriticalPayment < E11y::Event::Base
  retry_policy max_attempts: 5,
               backoff: :exponential,
               max_backoff: 1.minute
end
```

**Lines saved:** 100+ (v1.0 duplicated) → ~30 (v1.1 global infrastructure, reused)

---

#### UC-022: Event Registry (Schema Discovery)

**v1.0 (OLD):** 40+ lines for registry export config
**v1.1 (NEW):** Auto-generated from event classes (zero config!)

```ruby
# ✅ v1.1: Auto-generated registry (zero config!)
# E11y.registry.all_events → returns all event classes with schemas

# Export registry to JSON (for docs, tooling)
rake e11y:registry:export

# Output: config/e11y_registry.json
# {
#   "events": [
#     {
#       "name": "order.created",
#       "class": "Events::OrderCreated",
#       "severity": "success",
#       "schema": { ... },
#       "version": 1
#     }
#   ]
# }

# Global config: ZERO lines! Auto-discovery via Rails autoloading.
```

**Lines saved:** 40+ (v1.0 manual registry) → 0 (v1.1 auto-discovery)

---

### 2.7 Summary: v1.1 Configuration Savings

| Use Case | v1.0 Global Config Lines | v1.1 Global Config Lines | v1.1 Event-Level Lines | Savings |
|----------|-------------------------|-------------------------|----------------------|---------|
| **UC-001** Request-Scoped Debug | 50 | 0 | 3 | ✅ 50 → 0 |
| **UC-002** Business Events | 40 | 0 | 0 (conventions!) | ✅ 40 → 0 |
| **UC-003** Metrics | 100 | 0 | 8 | ✅ 100 → 0 |
| **UC-004** SLO Tracking | 80 | 0 | 0 (conventions!) | ✅ 80 → 0 |
| **UC-005** Sentry | 40 | 8 | 0 (conventions!) | ✅ 40 → 8 |
| **UC-006** Trace Context | 60 | 20 | 0 | ✅ 60 → 20 |
| **UC-007** PII Filtering | 70 | 0 | 5 | ✅ 70 → 0 |
| **UC-008** OpenTelemetry | 50 | 10 | 0 | ✅ 50 → 10 |
| **UC-009** Multi-Service Tracing | 80 | 0 | 3 | ✅ 80 → 0 |
| **UC-010** Background Jobs | 60 | 0 | 8 | ✅ 60 → 0 |
| **UC-011** Rate Limiting | 100 | 0 | 6 | ✅ 100 → 0 |
| **UC-012** Audit Trail | 90 | 5 | 4 | ✅ 90 → 5 |
| **UC-013** Cardinality Protection | 70 | 0 | 5 | ✅ 70 → 0 |
| **UC-014** Adaptive Sampling | 120 | 0 | 0 (conventions!) | ✅ 120 → 0 |
| **UC-015** Cost Optimization | 150 | 30 | 6 | ✅ 150 → 30 |
| **UC-016** Rails Logger | 40 | 1 | 0 | ✅ 40 → 1 |
| **UC-017** Local Development | 50 | 10 | 0 | ✅ 50 → 10 |
| **UC-018** Testing | 60 | 5 | 0 | ✅ 60 → 5 |
| **UC-019** Tiered Storage | 80 | 20 | 3 | ✅ 80 → 20 |
| **UC-020** Event Versioning | 50 | 0 | 1 | ✅ 50 → 0 |
| **UC-021** Error Handling & DLQ | 100 | 30 | 0 | ✅ 100 → 30 |
| **UC-022** Event Registry | 40 | 0 | 0 (auto!) | ✅ 40 → 0 |
| **TOTAL** | **1490 lines** | **139 lines** | **52 lines** | **✅ 1490 → 191 (87% reduction!)** |

**Key Insights:**

1. **Infrastructure stays global** (~139 lines): Adapters, buffer, circuit breaker, hooks
2. **Event-specific moves to events** (~52 lines avg per UC): Schemas, metrics, retention, PII
3. **Conventions eliminate 80% of config**: Severity → adapters, sample rates, SLO targets
4. **Total reduction: 87%** (1490 → 191 lines)
5. **Maintainability ↑**: Config lives where it's used (locality of behavior)

**v1.1 Philosophy:**

```ruby
# v1.0: "Configure everything globally" → 1400+ lines, hard to maintain
# v1.1: "Configure infrastructure globally, events locally" → <300 lines, easy to maintain
```

---

## 3. Feature Coverage Matrix (v1.1)

> **How v1.1 Event-Level Configuration Covers All Use Cases**
>
> This matrix shows where each UC's configuration lives in v1.1:
> - **Global (Infra)**: Infrastructure config in Section 1 (~280 lines)
> - **Event-Level**: Config in event classes (locality of behavior)
> - **Conventions**: Auto-inferred, zero config needed

| Use Case | v1.0 Global Lines | v1.1 Global Lines | v1.1 Event Lines | Primary Mechanism | Validation |
|----------|------------------|------------------|------------------|-------------------|------------|
| **UC-001: Request-Scoped Debug** | 50 | 0 | 3 | Event-level `buffering` DSL | ✅ Buffer type validation |
| **UC-002: Business Events** | 40 | 30 (hooks) | 0 | Conventions + global hooks | ✅ Schema required |
| **UC-003: Pattern Metrics** | 100 | 0 | 8 | Event-level `metric` DSL | ✅ Metric config validation |
| **UC-004: Zero-Config SLO** | 80 | 0 | 0 | Conventions (severity → SLO) | ✅ SLO target 0.0..1.0 |
| **UC-005: Sentry** | 40 | 8 (adapter) | 0 | Conventions (error → Sentry) | ✅ Adapter registration check |
| **UC-006: Trace Context** | 60 | 20 (enricher) | 0 | Global `context_enricher` hook | ✅ Trace ID format |
| **UC-007: PII Filtering** | 70 | 0 | 5 | Event-level `pii_filtering` DSL | ✅ PII strategy validation |
| **UC-008: OpenTelemetry** | 50 | 10 (adapter) | 0 | OTLP adapter registration | ✅ OTLP endpoint required |
| **UC-009: Multi-Service Tracing** | 80 | 0 (reuse UC-006) | 3 | Event schema + global hook | ✅ Service name required |
| **UC-010: Background Jobs** | 60 | 0 | 8 | Event-level config + Rails integration | ✅ Job status enum |
| **UC-011: Rate Limiting** | 100 | 0 | 6 | Event-level `rate_limit` DSL | ✅ Limit > 0, period valid |
| **UC-012: Audit Trail** | 90 | 5 (retention) | 4 | Event-level `audit_event` + C01 two pipelines | ✅ Locked: rate_limit/sampling |
| **UC-013: Cardinality Protection** | 70 | 0 | 5 | Event-level metric `max_cardinality` | ✅ Cardinality > 0 |
| **UC-014: Adaptive Sampling** | 120 | 0 | 0 | Conventions + C11 stratified sampling | ✅ Sample rate 0.0..1.0 |
| **UC-015: Cost Optimization** | 150 | 30 (compression) | 6 | Event-level retention + compression | ✅ Retention > 0, compression valid |
| **UC-016: Rails Logger** | 40 | 1 (enable flag) | 0 | Rails integration auto-capture | ✅ Rails env check |
| **UC-017: Local Development** | 50 | 10 (env adapters) | 0 | Environment-specific adapters | ✅ Adapter per env |
| **UC-018: Testing Events** | 60 | 5 (test adapter) | 0 | Test adapter registration | ✅ Test adapter present |
| **UC-019: Tiered Storage** | 80 | 20 (adapters) | 3 | Adapter-level + event-level retention | ✅ Retention valid, adapters registered |
| **UC-020: Event Versioning** | 50 | 0 | 1 | Event-level `version` DSL | ✅ Version > 0 |
| **UC-021: Error Handling & DLQ** | 100 | 30 (circuit breaker + DLQ) | 0 | Global infrastructure | ✅ Circuit breaker config valid |
| **UC-022: Event Registry** | 40 | 0 | 0 | Auto-discovery via Rails autoloading | ✅ All events discoverable |
| **TOTAL** | **1490** | **169** | **52** | **87% reduction** | **✅ Comprehensive** |

### v1.1 Configuration Distribution

**Where config lives:**

1. **Global Infrastructure (169 lines):**
   - Adapters registry (120 lines) - reused by all UCs
   - Buffer (30 lines) - UC-001 infrastructure
   - Circuit breaker (30 lines) - UC-021 infrastructure
   - Context enricher (20 lines) - UC-006, UC-009 shared
   - Audit retention (5 lines) - UC-012 default
   - Compression (30 lines) - UC-015 infrastructure
   - Rails integration (1 line) - UC-016 enable flag
   - Test adapter (5 lines) - UC-018 infrastructure
   - DLQ (30 lines) - UC-021 infrastructure

2. **Event-Level Config (avg 52 lines per UC):**
   - Schemas (all events) - UC-002, UC-022
   - Metrics (8 lines) - UC-003
   - PII filtering (5 lines) - UC-007
   - Rate limiting (6 lines) - UC-011
   - Audit settings (4 lines) - UC-012
   - Buffering (3 lines) - UC-001
   - Retention (3 lines) - UC-015, UC-019
   - Version (1 line) - UC-020

3. **Conventions (0 lines!):**
   - Severity → adapters (UC-005)
   - Severity → sample rate (UC-014)
   - Severity → SLO target (UC-004)
   - Event name → severity (UC-002)
   - Auto-discovery (UC-022)

### v1.1 Benefits Summary

**Configuration Simplicity:**
- ✅ **87% reduction** in global config (1490 → 169 lines)
- ✅ **Locality of behavior** - config lives in event classes
- ✅ **DRY** - infrastructure configured once, reused
- ✅ **Conventions** - 80% of config inferred automatically

**Maintainability:**
- ✅ **Single source of truth** - event schema + config in one place
- ✅ **Type safety** - validations at class load time
- ✅ **Refactoring** - change event = change config (no global search)

**Developer Experience:**
- ✅ **Intuitive** - Rails developers feel at home
- ✅ **Discoverable** - config visible in event class
- ✅ **Safe** - impossible to forget adapter registration

---

## 4. Conflict Analysis (v1.1 - RESOLVED ✅)

> **Status:** All major contradictions analyzed and resolved through v1.1 event-level configuration approach.
>
> **Reference:** See `docs/researches/final_analysis/contradictions/` for detailed TRIZ analysis.

### v1.1 Resolution Summary

**CONTRADICTION_01: Configuration Complexity (PRIMARY)**
- ✅ **RESOLVED** through event-level configuration
- Solution: Global config (infrastructure only) + Event-level config + Conventions
- Result: 1400+ lines → <300 lines (78% reduction)
- Details: `contradictions/CONTRADICTION_01_IMPLEMENTATION_SUMMARY.md`

**CONTRADICTION_02: Buffer Management**
- ✅ **RESOLVED** through dual-buffer architecture
- Solution: Request-scoped buffer (debug) + Main buffer (all events)
- Result: No conflicts, clear separation of concerns
- Details: `contradictions/CONTRADICTION_02_BUFFERS.md`

**CONTRADICTION_03: Sampling Strategies**
- ✅ **RESOLVED** through conventions + event-level overrides
- Solution: Severity-based default sampling + per-event adaptive strategies
- Result: 120+ lines global config → 0 lines (conventions)
- Details: `contradictions/CONTRADICTION_03_SAMPLING.md`

**CONTRADICTION_04: PII Filtering**
- ✅ **RESOLVED** through event-level PII config
- Solution: Per-event `pii_filtering` DSL with field-level control
- Result: 70+ lines global patterns → event-level (locality)
- Details: `contradictions/CONTRADICTION_04_PII.md`

**CONTRADICTION_05: Performance Overhead**
- ✅ **RESOLVED** through smart defaults + lazy evaluation + opt-in features
- Solution: Zero-allocation fast path + opt-in features (versioning, sampling) + opt-out features (PII filtering, rate limiting)
- Result: <100ns per event overhead on happy path
- Performance optimization: Opt-out PII filtering saves 0.2ms (20% of budget!), opt-out rate limiting saves 0.01ms
- Details: `contradictions/CONTRADICTION_05_PERFORMANCE.md`
- See also: ADR-001 Section 12 (Opt-In Features Pattern)

**CONTRADICTION_06: Multi-Adapter Routing**
- ✅ **RESOLVED** through conventions + circuit breaker
- Solution: Severity-based routing + per-adapter health checks
- Result: Automatic failover, no global routing rules
- Details: `contradictions/CONTRADICTION_06_MULTI_ADAPTER.md`

### Feature Interaction Matrix (v1.1)

| Feature A | Feature B | Conflict? | Resolution |
|-----------|-----------|-----------|------------|
| **Request Buffer** | Main Buffer | ❌ No | Dual-buffer: separate concerns |
| **Rate Limiting** | Adaptive Sampling | ❌ No | Sequential: rate limit → sampling |
| **PII Filtering** | OTEL Semantics | ❌ No | PII applied after semantic conventions |
| **Audit Signing** | PII Filtering | ❌ No | Signing after PII (hash stable) |
| **Cardinality Protection** | Auto-Metrics | ❌ No | Max cardinality enforced per metric |
| **Circuit Breaker** | Multi-Adapter | ❌ No | Per-adapter circuit, others unaffected |
| **Compression** | Minimization | ❌ No | Minimize → compress (order matters) |
| **Tiered Storage** | Retention | ❌ No | Complementary: retention drives tiering |
| **Job Tracing** | Sampling | ❌ No | Same rules as HTTP (severity-based) |

### Middleware Order (Canonical)

**v1.1 Middleware Stack (ADR-015):**

```ruby
# Execution order (top to bottom):
1. Schema Validation       # ← Fail fast on invalid events
2. PII Filtering           # ← Before any storage/transmission
3. Context Enrichment      # ← Add trace_id, tenant_id, etc.
4. Rate Limiting           # ← Drop excess events early
5. Adaptive Sampling       # ← Intelligent sampling decisions
6. Cardinality Protection  # ← Protect metrics from explosion
7. Compression             # ← Reduce payload size
8. Circuit Breaker         # ← Adapter health check
9. Multi-Adapter Routing   # ← Send to registered adapters
10. Buffer Management      # ← Queue for async flush
```

**Key Insight:** v1.1 event-level configuration eliminates most potential conflicts by moving decisions to event definition time (class load) rather than runtime global rules.

**Reference Documents:**
- `docs/researches/final_analysis/contradictions/CONTRADICTION_01_CONFIGURATION.md`
- `docs/ADR-015-middleware-order.md`
- `docs/ADR-013-reliability-error-handling.md`

---

## 5. Unified DSL Validations & Best Practices (NEW - v1.1)

### 5.1. Automatic Validations

**All event classes automatically validated at load time:**

```ruby
# Schema presence validation
class Events::OrderPaid < E11y::Event::Base
  # ← ERROR at load: "Events::OrderPaid missing schema!"
end

# Severity validation
class Events::OrderPaid < E11y::Event::Base
  severity :critical  # ← ERROR: "Invalid severity: :critical. Valid: debug, info, success, warn, error, fatal"
end

# Adapters validation
class Events::OrderPaid < E11y::Event::Base
  adapters [:loki, :sentri]  # ← ERROR: "Unknown adapter: :sentri. Registered: loki, sentry, file"
end

# Rate limit validation
class Events::ApiRequest < E11y::Event::Base
  rate_limit -100  # ← ERROR: "rate_limit must be positive integer, got: -100"
end

# Sample rate validation
class Events::DebugLog < E11y::Event::Base
  sample_rate 1.5  # ← ERROR: "sample_rate must be 0.0..1.0, got: 1.5"
end

# Audit event locked settings
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  rate_limiting true  # ← ERROR: "Cannot enable rate_limiting for audit events!"
  sampling true       # ← ERROR: "Cannot enable sampling for audit events!"
end
```

### 5.2. Environment-Specific Configuration Patterns

**Pattern 1: Adapters per environment**

```ruby
class Events::DebugQuery < E11y::Event::Base
  adapters Rails.env.production? ? [:loki] : [:file]
end
```

**Pattern 2: Rate limits per environment**

```ruby
class Events::ApiRequest < E11y::Event::Base
  rate_limit case Rails.env
             when 'production' then 10_000
             when 'staging' then 1_000
             else 100
             end
end
```

**Pattern 3: Sampling per environment**

```ruby
class Events::DebugLog < E11y::Event::Base
  sample_rate Rails.env.production? ? 0.01 : 1.0
  adaptive_sampling enabled: Rails.env.production?
end
```

**Pattern 4: PII per jurisdiction**

```ruby
class Events::UserRegistered < E11y::Event::Base
  contains_pii true
  pii_filtering do
    if ENV['JURISDICTION'] == 'EU'
      hashes :user_id, algorithm: :sha256  # GDPR pseudonymization
    else
      allows :user_id  # Non-EU: allow
    end
  end
end
```

**Pattern 5: Audit retention per jurisdiction**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.audit_retention = case ENV['JURISDICTION']
                           when 'EU' then 7.years   # GDPR
                           when 'US' then 10.years  # SOX/Financial
                           else 5.years
                           end
end

# Event uses configured value:
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  # ← Auto: retention = E11y.config.audit_retention (configurable!)
end
```

### 5.3. Precedence Rules Summary

**Configuration precedence (highest to lowest):**

```
1. Event-level explicit config (highest priority)
   ↓
2. Preset module config
   ↓
3. Base class config (inheritance)
   ↓
4. Convention-based defaults
   ↓
5. Global config (lowest priority)
```

**Example: Complete precedence chain**

```ruby
# Global (lowest)
E11y.configure do |config|
  config.adapters = [:file]
  config.sample_rate = 0.1
  config.rate_limit = 1_000
end

# Convention (auto-inferred)
# severity :error → sample_rate 1.0, adapters [:sentry]

# Base class (inheritance)
class Events::BasePaymentEvent < E11y::Event::Base
  severity :success
  adapters [:loki, :sentry]
  sample_rate 1.0
  rate_limit 10_000
end

# Preset (module)
module E11y::Presets::HighValueEvent
  extend ActiveSupport::Concern
  included do
    retention 7.years
    rate_limit 50_000
  end
end

# Event (highest)
class Events::CriticalPayment < Events::BasePaymentEvent
  include E11y::Presets::HighValueEvent
  
  adapters [:loki, :sentry]  # Override all
  
  # Final config:
  # - severity: :success (base)
  # - adapters: [:loki, :sentry] (event override)
  # - sample_rate: 1.0 (base)
  # - rate_limit: 50_000 (preset override)
  # - retention: 7.years (preset)
end
```

---

**Status:** Configuration Complete ✅ (Updated to Unified DSL v1.1.0)  
**Next Step:** Conflict Analysis 🔍

