# E11y Comprehensive Configuration Guide

**Purpose:** Максимально полный конфиг-пример, покрывающий ВСЕ 22 use cases для анализа конфликтов между фичами.

---

## 📋 Table of Contents

1. [Initializer Configuration](#initializer-configuration)
2. [Event Examples](#event-examples)
3. [Feature Coverage Matrix](#feature-coverage-matrix)
4. [Conflict Analysis](#conflict-analysis)

---

## 1. Initializer Configuration

### config/initializers/e11y.rb

```ruby
# frozen_string_literal: true

# E11y Comprehensive Configuration
# Covers all 18 use cases

E11y.configure do |config|
  # ============================================================================
  # UC-001: Request-Scoped Debug Buffering
  # ============================================================================
  config.request_scope do
    enabled true
    buffer_limit 100  # Max debug events per request
    
    # Flush triggers
    flush_on :error         # On exception
    flush_on :warn          # On any :warn event
    flush_on :slow_request, threshold: 1000  # On requests >1s
    
    # Custom flush condition
    flush_if do |events, request|
      # Flush if payment-related
      events.any? { |e| e.name.include?('payment') }
    end
    
    # Exclude from buffering (always send immediately)
    exclude_from_buffer do
      severity [:info, :success, :warn, :error, :fatal]  # Only buffer :debug
      event_patterns ['security.*', 'audit.*', 'fraud.*']  # Never buffer these
    end
    
    # Overflow strategy
    overflow_strategy :drop_oldest  # or :drop_newest, :flush_immediately
  end
  
  # ============================================================================
  # UC-002: Business Event Tracking
  # ============================================================================
  config.events do
    # Auto-register all event classes in app/events/**/*.rb
    auto_register true
    auto_register_paths ['app/events']
    
    # Validation
    validate_schema true  # Enforce schema validation
    validation_errors :raise  # :raise, :log, :ignore
    
    # Duration tracking
    track_duration true  # Measure block execution time
    duration_unit :milliseconds  # or :seconds, :microseconds
    
    # Context enrichment (added to every event)
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
  # UC-003: Pattern-Based Metrics (Yabeda Integration)
  # ============================================================================
  config.metrics do
    enabled true
    
    # Auto-create metrics from events
    auto_metrics true
    
    # Default metric types for event patterns
    default_counter_for patterns: ['*.created', '*.completed', '*.failed']
    default_histogram_for patterns: ['*.duration', '*.latency', '*.size']
    default_gauge_for patterns: ['*.count', '*.active']
    
    # Metric naming
    prefix 'app'  # Prefix for all metrics: app_orders_created_total
    separator '_'  # Separator for metric names
    
    # See UC-013 for cardinality protection (below)
  end
  
  # ============================================================================
  # UC-004: Zero-Config SLO Tracking
  # ============================================================================
  config.slo do
    enabled true
    
    # HTTP requests (Rails controllers)
    track_http_requests true
    http_success_threshold 0.95  # 95% success rate
    http_latency_threshold 500   # 500ms p95
    
    # Background jobs
    track_sidekiq true
    track_active_job true
    job_success_threshold 0.99   # 99% success rate
    job_latency_threshold 5000   # 5s p95
    
    # Error budget
    error_budget_window 30.days
    error_budget_alerts true
    
    # Burn rate alerts
    burn_rate_alerts do
      fast_burn threshold: 14.4, window: 1.hour   # 2% budget in 1h
      slow_burn threshold: 6, window: 6.hours     # 5% budget in 6h
    end
    
    # Custom SLIs
    custom_sli 'payment.processing' do
      success_criteria { |event| event.payload[:status] == 'completed' }
      latency_threshold 2000  # 2s
      target 0.999  # 99.9%
    end
  end
  
  # ============================================================================
  # UC-005: Sentry Integration
  # ============================================================================
  config.sentry do
    enabled true
    
    # Auto-capture
    auto_capture_errors true  # :error and :fatal events → Sentry
    auto_breadcrumbs true     # All events → breadcrumbs
    
    # Breadcrumb settings
    breadcrumb_limit 100
    breadcrumb_severities [:debug, :info, :success, :warn, :error, :fatal]
    
    # Error fingerprinting
    custom_fingerprint do |event|
      # Group by error type + controller + action
      [
        event.payload[:error_class],
        event.context[:controller],
        event.context[:action]
      ]
    end
    
    # Sampling
    sample_rate 1.0  # 100% in production
    traces_sample_rate 0.1  # 10% for performance monitoring
    
    # Before send hook
    before_send do |event, hint|
      # Don't send test errors
      return nil if event.context[:env] == 'test'
      
      # Filter sensitive data
      event.payload.except!(:password, :token, :secret)
      
      event
    end
  end
  
  # ============================================================================
  # UC-006: Trace Context Management
  # ============================================================================
  config.tracing do
    enabled true
    
    # Trace ID generation
    trace_id_generator :uuid  # :uuid, :random_hex, :custom
    
    # W3C Trace Context support
    w3c_trace_context true
    
    # Propagation
    propagate_to_background_jobs true
    propagate_to_http_clients true  # Auto-inject headers
    
    # Custom trace ID extraction
    trace_id_extractor do |request|
      # Try multiple sources
      request.headers['X-Request-ID'] ||
        request.headers['X-Trace-ID'] ||
        request.headers['traceparent']&.split('-')&.[](1)
    end
    
    # Trace correlation
    correlation do
      log_correlation true  # Add trace_id to all logs
      metric_correlation true  # Add trace_id to exemplars
    end
  end
  
  # ============================================================================
  # UC-007: PII Filtering
  # ============================================================================
  config.pii_filter do
    enabled true
    
    # Rails parameter filtering compatibility
    use_rails_filter_parameters true  # Inherit from Rails.application.config.filter_parameters
    
    # Field-based filtering (exact match)
    mask_fields :email, :phone, :ssn, :card_number, :password, :token, :secret,
                :api_key, :credit_card, :cvv, :pan, :iban, :swift
    
    # Pattern-based filtering (regex)
    mask_pattern /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
                 with: '[EMAIL]',
                 name: :email
    
    mask_pattern /\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/,
                 with: '[CARD]',
                 name: :credit_card
    
    mask_pattern /\b\d{3}-\d{2}-\d{4}\b/,
                 with: '[SSN]',
                 name: :ssn
    
    mask_pattern /\b\d{10,15}\b/,
                 with: '[PHONE]',
                 name: :phone
    
    # URL parameter filtering
    mask_url_params :token, :api_key, :secret, :password
    
    # Custom filter function
    custom_filter do |field, value|
      # Mask Authorization headers
      if field.to_s.downcase == 'authorization'
        value.to_s.gsub(/Bearer\s+\S+/, 'Bearer [FILTERED]')
      else
        value
      end
    end
    
    # Allowlist (never mask these fields, even if matched)
    allow_fields :user_id, :order_id, :transaction_id, :event_id,
                 :account_id, :organization_id, :tenant_id
    
    # Deep scanning
    deep_scan true  # Scan nested hashes and arrays
    max_depth 10    # Prevent infinite recursion
    
    # Sampling (keep some filtered values for debugging)
    sample_filtered_values true
    sample_rate 0.01  # Keep 1% of filtered values
    
    # GDPR compliance
    gdpr_mode true  # Extra strict filtering
    gdpr_fields :ip_address, :user_agent, :geolocation, :device_id
  end
  
  # ============================================================================
  # UC-008: OpenTelemetry Integration
  # ============================================================================
  config.opentelemetry do
    enabled true
    
    # Semantic Conventions
    use_semantic_conventions true
    convention_version '1.21.0'
    
    # Resource Attributes (attached to all telemetry)
    resource_attributes do
      {
        'service.name' => ENV['SERVICE_NAME'] || 'api',
        'service.version' => ENV['GIT_SHA'] || 'unknown',
        'service.namespace' => ENV['NAMESPACE'] || 'production',
        'deployment.environment' => Rails.env,
        'host.name' => Socket.gethostname,
        'host.id' => ENV['HOST_ID'],
        'cloud.provider' => ENV['CLOUD_PROVIDER'],
        'cloud.region' => ENV['CLOUD_REGION'],
        'k8s.pod.name' => ENV['POD_NAME'],
        'k8s.namespace.name' => ENV['K8S_NAMESPACE']
      }
    end
    
    # OTel Collector
    collector_endpoint ENV['OTEL_COLLECTOR_URL'] || 'http://localhost:4318'
    collector_protocol :http  # :http or :grpc
    collector_headers do
      { 'X-API-Key' => ENV['OTEL_API_KEY'] }
    end
    
    # Logs Signal
    export_logs true
    logs_exporter :otlp  # or :console, :file
    
    # Automatic span creation
    auto_span_creation true
    span_kinds do
      http_requests :server
      background_jobs :consumer
      external_api_calls :client
      database_queries :client
    end
    
    # Log-Trace correlation
    log_trace_correlation true
    inject_trace_context_to_logs true
  end
  
  # ============================================================================
  # UC-009: Multi-Service Tracing
  # ============================================================================
  config.multi_service_tracing do
    enabled true
    
    # W3C Trace Context propagation (already in UC-006, here extended)
    propagate_via_http_headers true
    http_header_format :w3c  # :w3c, :b3, :jaeger, :all
    
    # Service mesh integration
    service_mesh :istio  # :istio, :linkerd, :consul, :none
    mesh_headers ['x-request-id', 'x-b3-traceid', 'x-b3-spanid']
    
    # Background job propagation
    background_job_propagation do
      sidekiq true
      active_job true
      good_job true
      
      # Metadata keys
      trace_id_key 'e11y_trace_id'
      span_id_key 'e11y_span_id'
      parent_span_id_key 'e11y_parent_span_id'
    end
    
    # Cross-service correlation
    correlation_id_header 'X-Correlation-ID'
    
    # Distributed context
    baggage_propagation true  # W3C Baggage for custom context
  end
  
  # ============================================================================
  # UC-010: Background Job Tracking
  # ============================================================================
  config.background_jobs do
    enabled true
    
    # Auto-instrumentation
    auto_instrument_sidekiq true
    auto_instrument_active_job true
    
    # Job lifecycle events
    track_enqueue true
    track_start true
    track_success true
    track_failure true
    track_retry true
    
    # Trace context propagation (see UC-009)
    propagate_trace_context true
    
    # Performance tracking
    track_duration true
    track_queue_latency true  # Time from enqueue to start
    
    # SLO tracking (see UC-004)
    track_slo true
    
    # Sampling
    sample_rate 1.0
  end
  
  # ============================================================================
  # UC-011: Rate Limiting
  # ============================================================================
  config.rate_limiting do
    enabled true
    
    # Storage backend
    backend :redis  # :redis, :memory, :null
    redis_client Redis.new(url: ENV['REDIS_URL'])
    
    # Global limit (защита от flood)
    global do
      limit 10_000
      window 1.minute
      key 'e11y:rate_limit:global'
    end
    
    # Per-event type limits
    per_event 'user.login.failed' do
      limit 100
      window 1.minute
    end
    
    per_event 'payment.failed' do
      limit 50
      window 1.minute
    end
    
    per_event 'api.rate_limit_exceeded' do
      limit 10
      window 1.minute
    end
    
    # Per-context limits (e.g., per user_id, per ip_address)
    per_context :user_id do
      limit 1000
      window 1.minute
      extract_from :context  # event.context[:user_id]
    end
    
    per_context :ip_address do
      limit 500
      window 1.minute
      extract_from :context
    end
    
    # Overflow strategy
    on_exceeded :drop  # :drop, :sample, :log_warning, :queue_for_later
    
    # Sampling when rate limited (instead of dropping)
    sample_rate_when_limited 0.1  # Keep 10% of events
    
    # Allowlist (bypass rate limiting)
    bypass_for do
      event_types ['system.critical', 'security.alert', 'audit.*']
      contexts { |ctx| ctx[:env] == 'development' }
      contexts { |ctx| ctx[:user_id] == 'admin' }
    end
    
    # Circuit breaker integration
    open_circuit_on_persistent_limit_exceeded true
    circuit_breaker_threshold 10  # Open after 10 consecutive limit hits
  end
  
  # ============================================================================
  # UC-012: Audit Trail
  # ============================================================================
  config.audit_trail do
    enabled true
    
    # Storage
    storage :database  # :database, :file, :s3, :adapter
    table_name 'e11y_audit_events'
    
    # Cryptographic signing
    signing do
      enabled true
      algorithm :ed25519  # :ed25519, :rsa, :hmac
      private_key ENV['AUDIT_SIGNING_KEY']
      public_key ENV['AUDIT_VERIFICATION_KEY']
    end
    
    # Retention (default, can be overridden per event)
    default_retention 7.years
    
    # Tamper detection
    verify_on_read true
    alert_on_tampering true
    
    # Compliance tags
    compliance_frameworks [:gdpr, :hipaa, :sox, :pci_dss]
    
    # Access control
    read_access_role :auditor
    write_access_role :system  # Only system can write
    
    # Audit log for audit log (meta-audit)
    audit_access true  # Log all reads of audit events
  end
  
  # ============================================================================
  # UC-013: High Cardinality Protection
  # ============================================================================
  config.cardinality_protection do
    enabled true
    
    # === Layer 1: Denylist (Hard Block) ===
    forbidden_labels :user_id, :order_id, :session_id, :trace_id, :request_id,
                     :pod_uid, :container_id, :instance_id, :ip_address,
                     :url, :hostname, :timestamp, :created_at
    
    enforcement :strict  # :strict (error), :warn (log), :drop (silently remove)
    
    # === Layer 2: Allowlist (Optional Strict Mode) ===
    allowed_labels_only false  # Set to true for strict allowlist mode
    allowed_labels :status, :payment_method, :plan_tier, :env, :region,
                   :http_method, :http_status_code, :controller, :action,
                   :job_class, :queue_name, :severity
    
    # === Layer 3: Per-Metric Limits ===
    default_cardinality_limit 1_000  # Default for all metrics
    
    cardinality_limit_for 'http.requests' do
      max_cardinality 2_000
      overflow_strategy :aggregate  # :aggregate, :drop, :sample
      aggregate_to_label '_other'
    end
    
    cardinality_limit_for 'background_jobs' do
      max_cardinality 500
      overflow_strategy :sample
      sample_rate 0.1  # Keep 10% when limit exceeded
    end
    
    # === Layer 4: Dynamic Monitoring ===
    monitoring do
      enabled true
      
      # Alert thresholds
      warn_threshold 0.7    # Alert at 70% of limit
      critical_threshold 0.9  # Critical at 90%
      
      # Auto-adjust strategy
      auto_adjust do
        enabled true
        threshold 0.8
        action :aggregate  # Switch to aggregation when at 80%
      end
      
      # Export cardinality metrics
      export_metrics true
    end
    
    # === Advanced Techniques ===
    
    # Relabeling / Normalization
    relabeling do
      # Normalize versions: 2.5.7234 → 2.5
      relabel 'version' do |value|
        value.to_s.split('.').first(2).join('.')
      end
      
      # Aggregate HTTP status: 200..299 → 2xx
      relabel 'http_status_code' do |value|
        "#{value.to_s[0]}xx"
      end
      
      # Group endpoints: /api/orders/123 → /api/orders/:id
      relabel 'endpoint' do |value|
        value.gsub(/\/\d+/, '/:id')
              .gsub(/\/[a-f0-9-]{36}/, '/:uuid')
      end
    end
    
    # Exemplars (high-cardinality data as samples, not labels)
    exemplars do
      enabled true
      max_per_series 10
      sample_rate 0.01  # 1% of events
    end
  end
  
  # ============================================================================
  # UC-014: Adaptive Sampling
  # ============================================================================
  config.adaptive_sampling do
    enabled true
    
    # === Strategy 1: Error-Based Sampling ===
    error_based do
      enabled true
      sample_rate_success 0.1    # 10% of success events
      sample_rate_error 1.0      # 100% of errors
      sample_rate_by_severity do
        debug 0.01   # 1%
        info 0.1     # 10%
        success 0.1  # 10%
        warn 0.5     # 50%
        error 1.0    # 100%
        fatal 1.0    # 100%
      end
    end
    
    # === Strategy 2: Load-Based Sampling ===
    load_based do
      enabled true
      
      # How we detect system load (multiple strategies)
      load_detection_strategy :events_per_second  # :events_per_second, :buffer_usage, :cpu, :memory, :combined
      
      # Strategy 1: Events per second (simplest, default)
      events_per_second do
        # Measure via internal counter (self-monitoring)
        measurement_window 10.seconds  # Rolling window
        
        thresholds do
          low_load threshold: 100, sample_rate: 1.0      # <100 events/sec = 100%
          medium_load threshold: 1000, sample_rate: 0.5  # 100-1000 = 50%
          high_load threshold: 10_000, sample_rate: 0.1  # 1000-10k = 10%
          extreme_load threshold: :infinity, sample_rate: 0.01  # >10k = 1%
        end
      end
      
      # Strategy 2: Buffer usage (backpressure indicator)
      buffer_usage do
        enabled false  # Optional, can combine with events_per_second
        
        thresholds do
          # Buffer usage % → sample rate
          low threshold: 0.3, sample_rate: 1.0     # <30% full = 100%
          medium threshold: 0.6, sample_rate: 0.5  # 30-60% = 50%
          high threshold: 0.8, sample_rate: 0.1    # 60-80% = 10%
          critical threshold: 1.0, sample_rate: 0.01  # >80% = 1%
        end
      end
      
      # Strategy 3: System metrics (advanced)
      system_metrics do
        enabled false  # Optional, requires sys-proctable gem
        
        # CPU-based
        cpu_threshold 0.8  # >80% CPU → reduce sample rate
        cpu_sample_rate 0.1
        
        # Memory-based
        memory_threshold 0.9  # >90% memory → reduce sample rate
        memory_sample_rate 0.01
      end
      
      # Combined strategy (use multiple signals)
      combined do
        enabled false  # Advanced: combine all strategies
        
        # Take MIN sample rate from all strategies
        aggregation_method :min  # or :max, :average
      end
      
      # Check interval (how often to re-evaluate load)
      check_interval 10.seconds
      
      # Smoothing (avoid rapid oscillation)
      smoothing do
        enabled true
        window 30.seconds  # Average over 30s
        min_change 0.1     # Only change if >10% difference
      end
    end
    
    # === Strategy 3: Value-Based Sampling ===
    value_based do
      enabled true
      
      # Sample based on event payload values
      sample_if do |event|
        # Always sample high-value transactions
        if event.name == 'payment.completed'
          amount = event.payload[:amount].to_f
          case amount
          when 0..10 then 0.01      # $0-10 = 1%
          when 10..100 then 0.1     # $10-100 = 10%
          when 100..1000 then 0.5   # $100-1000 = 50%
          else 1.0                  # >$1000 = 100%
          end
        else
          1.0  # Default 100%
        end
      end
    end
    
    # === Strategy 4: Content-Based Sampling ===
    content_based do
      enabled true
      
      # Always sample events matching patterns
      always_sample patterns: [
        'security.*',
        'audit.*',
        'fraud.*',
        'payment.failed',
        '*.critical'
      ]
      
      # Never sample (always 100%)
      never_sample patterns: [
        'health_check.*',
        'ping.*',
        'metrics.export'
      ]
    end
    
    # === Strategy 5: Tail-Based Sampling ===
    tail_based do
      enabled false  # Advanced feature, requires more resources
      
      # Buffer events and decide later
      buffer_duration 30.seconds
      buffer_size 10_000
      
      # Sampling decision after buffer
      sample_decision do |events|
        # Sample entire trace if any event is error
        events.any? { |e| e.severity >= :error }
      end
    end
    
    # === Global Settings ===
    
    # Always sample for specific contexts
    always_sample_for do
      contexts { |ctx| ctx[:env] == 'development' }
      contexts { |ctx| ctx[:user_id] == 'test-user' }
      contexts { |ctx| ctx[:debug_mode] == true }
    end
    
    # Override sample rate per event class
    override_sample_rate do
      event_type 'user.login', rate: 1.0      # Always 100%
      event_type 'page.view', rate: 0.01      # 1%
      event_type 'debug.*', rate: 0.001       # 0.1%
    end
  end
  
  # ============================================================================
  # UC-015: Cost Optimization
  # ============================================================================
  config.cost_optimization do
    enabled true
    
    # === Technique 1: Intelligent Sampling by Value ===
    # (See UC-014 adaptive_sampling.value_based)
    
    # === Technique 2: Deduplication ===
    deduplication do
      enabled true
      window 5.minutes
      
      # Dedup by event fingerprint
      fingerprint_fields [:name, :payload, :context]
      
      # Keep first or last?
      keep :first  # :first or :last
      
      # Storage
      backend :redis
      key_prefix 'e11y:dedup'
    end
    
    # === Technique 3: Compression ===
    compression do
      enabled true
      algorithm :zstd  # :gzip, :zstd, :lz4
      level 3  # 1-22 for zstd, 1-9 for gzip
      
      # Compress only for specific adapters
      compress_for_adapters [:http, :loki, :s3]
      
      # Minimum payload size to compress
      min_size 1.kilobyte
    end
    
    # === Technique 4: Retention Tagging (for Downstream Lifecycle) ===
    retention_tagging do
      enabled true
      
      # E11y adds absolute expiry date to each event!
      # Downstream just checks: now > retention_until
      
      # Default retention (if event doesn't specify)
      default_retention 30.days
      
      # Per-pattern retention rules
      retention_by_pattern do
        pattern 'audit.*', retention: 7.years
        pattern 'security.*', retention: 1.year
        pattern 'debug.*', retention: 1.day
        pattern '*.page_view', retention: 7.days
        pattern '*', retention: 30.days  # Default
      end
      
      # Field name
      retention_field :retention_until  # ISO8601 timestamp
      
      # Event metadata structure:
      # {
      #   "@timestamp": "2026-01-12T10:30:00Z",
      #   "retention_until": "2026-02-11T10:30:00Z",  ← E11y calculates: @timestamp + 30.days
      #   "event_name": "order.created",
      #   ...
      # }
      
      # Downstream systems (ES, S3) simply check:
      # if now > retention_until → delete
      # No calculations needed!
    end
    
    # === Technique 5: Smart Routing by Event Type ===
    smart_routing do
      enabled true
      
      # Debug events → local file only (cheap)
      route_by_severity do
        debug adapters: [:file]
        info adapters: [:loki, :file]
        success adapters: [:loki, :elasticsearch]
        warn adapters: [:loki, :elasticsearch, :sentry]
        error adapters: [:loki, :elasticsearch, :sentry, :pagerduty]
        fatal adapters: [:loki, :elasticsearch, :sentry, :pagerduty, :slack]
      end
      
      # High-volume events → sampling + cheap storage
      route_by_pattern do
        pattern '*.page_view' do
          sample_rate 0.01
          adapters [:s3_batch]  # Batch writes to S3
        end
        
        pattern '*.click' do
          sample_rate 0.05
          adapters [:s3_batch]
        end
      end
    end
    
    # === Technique 6: Payload Minimization ===
    payload_minimization do
      enabled true
      
      # Remove fields for specific severities
      drop_fields_for_severity do
        debug fields: [:stack_trace, :environment_variables]
        info fields: [:stack_trace]
      end
      
      # Truncate long strings
      truncate_strings do
        max_length 1000  # chars
        fields [:message, :error_message, :stack_trace]
      end
      
      # Drop null/empty values
      drop_empty_values true
    end
    
    # === Technique 7: Batching & Buffering ===
    batching do
      enabled true
      
      # Batch size
      max_batch_size 500
      max_batch_bytes 1.megabyte
      
      # Flush interval
      flush_interval 200.milliseconds
      
      # Adaptive batching (increase batch size under load)
      adaptive true
      min_batch_size 100
      max_batch_size 1000
    end
    
    # === Technique 8: Retention-Aware Tagging ===
    retention_tagging do
      enabled true
      
      # Tag events with retention policy
      tag_with_retention true
      retention_tag_key 'retention_days'
      
      # Downstream systems can filter by tag
      default_retention 30.days
      
      # Per-event retention
      retention_by_pattern do
        pattern 'audit.*', retention: 7.years
        pattern 'security.*', retention: 1.year
        pattern 'debug.*', retention: 1.day
        pattern '*.page_view', retention: 7.days
      end
    end
  end
  
  # ============================================================================
  # UC-016: Rails Logger Migration
  # ============================================================================
  config.rails_integration do
    enabled true
    
    # Coexistence with Rails.logger
    coexistence_mode :parallel  # :parallel, :replace, :intercept
    
    # Intercept Rails.logger calls
    intercept_rails_logger false  # Set to true to capture all Rails.logger calls
    
    # Rails.logger → E11y severity mapping
    rails_logger_mapping do
      debug :debug
      info :info
      warn :warn
      error :error
      fatal :fatal
      unknown :info
    end
    
    # ActiveSupport::Notifications integration
    subscribe_to_notifications true
    
    notification_patterns [
      'process_action.action_controller',
      'sql.active_record',
      'cache_read.active_support',
      'render_template.action_view',
      'send_email.action_mailer'
    ]
    
    # Convert Rails notifications to E11y events
    notification_to_event_mapping do
      map 'process_action.action_controller' do |name, started, finished, id, payload|
        Events::HttpRequest.track(
          controller: payload[:controller],
          action: payload[:action],
          method: payload[:method],
          path: payload[:path],
          status: payload[:status],
          duration_ms: (finished - started) * 1000,
          severity: payload[:status] < 400 ? :success : :error
        )
      end
      
      map 'sql.active_record' do |name, started, finished, id, payload|
        Events::DatabaseQuery.track(
          name: payload[:name],
          sql: payload[:sql],
          duration_ms: (finished - started) * 1000,
          severity: :debug
        )
      end
    end
  end
  
  # ============================================================================
  # UC-017: Local Development Experience
  # ============================================================================
  config.development do
    # Only for Rails.env.development?
    enabled Rails.env.development?
    
    # Console output
    console_output do
      enabled true
      colored true
      pretty_print true
      show_payload true
      show_context true
      show_metadata true
    end
    
    # Debug helpers
    debug_helpers do
      enabled true
      
      # E11y.debug_mode! → capture all events in memory
      in_memory_capture true
      
      # E11y.last_events(10) → show recent events
      event_history_size 100
      
      # E11y.event_stats → show event counts by type
      statistics true
    end
    
    # Web UI (Rails engine)
    web_ui do
      enabled true
      mount_path '/e11y'
      
      # Features
      event_explorer true
      event_search true
      metrics_dashboard true
      trace_viewer true
      
      # Authentication
      authenticate_with do |username, password|
        username == 'admin' && password == ENV['E11Y_UI_PASSWORD']
      end
    end
    
    # Validation warnings (strict in dev)
    strict_validation true
    verbose_warnings true
    
    # Performance profiling
    profiling do
      enabled false  # Enable manually when needed
      profile_track_calls true
      profile_adapters true
    end
  end
  
  # ============================================================================
  # UC-018: Testing Events (RSpec Integration)
  # ============================================================================
  config.testing do
    # Only for Rails.env.test?
    enabled Rails.env.test?
    
    # Use memory adapter (no real I/O)
    use_memory_adapter true
    
    # RSpec matchers
    rspec_matchers true
    
    # Capture all events for assertions
    capture_events true
    auto_clear_between_tests true
    
    # Strict validation in tests
    validate_schemas true
    raise_on_validation_errors true
    
    # Disable slow features in tests
    disable_in_tests do
      sentry false
      opentelemetry false
      rate_limiting false
      adaptive_sampling false
      background_jobs false
    end
    
    # Test helpers
    test_helpers do
      # E11y.tracked_events → all events captured
      # E11y.clear_tracked_events! → reset
      # E11y.track_events { block } → capture in block
    end
  end
  
  # ============================================================================
  # UC-020: Event Versioning & Schema Evolution
  # ============================================================================
  config.versioning do
    enabled true
    
    # Include version in event payload
    include_version_in_payload true
    version_field :event_version  # Field name: event_version
    
    # Deprecation warnings
    warn_on_deprecated_version true
    deprecation_log_level :warn  # :info, :warn, :error
    
    # Automatic version detection from payload
    auto_detect_version true
    
    # Auto-upgrade old versions (disabled by default)
    auto_upgrade_to_current do
      enabled false  # Explicit migration preferred
      
      # If enabled, define transformations:
      # upgrade 'order.paid' do
      #   from_version 1
      #   to_version 2
      #   transform do |v1_payload|
      #     v1_payload.merge(currency: 'USD')  # Add default for missing field
      #   end
      # end
    end
    
    # Deprecation enforcement
    deprecation_enforcement do
      # After this date, deprecated versions rejected/upgraded
      enforce_after '2026-06-01'  # Set to nil to disable enforcement
      
      # What to do with deprecated versions after enforce_after
      on_deprecated_version :warn  # :reject, :warn, :upgrade
    end
    
    # Version metrics
    track_version_usage true  # Track e11y_events_by_version_total{event_name, version}
  end
  
  # ============================================================================
  # UC-021: Error Handling, Retry Policy & Dead Letter Queue
  # ============================================================================
  config.error_handling do
    # === Retry Policy (Exponential Backoff) ===
    retry_policy do
      enabled true
      max_retries 3
      initial_delay 0.1.seconds  # 100ms
      max_delay 5.seconds
      multiplier 2  # Exponential: 100ms → 200ms → 400ms
      jitter true   # Add randomness (±50%) to prevent thundering herd
      
      # Which errors are retryable
      retryable_errors [
        Errno::ETIMEDOUT,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Net::OpenTimeout,
        Net::ReadTimeout,
        HTTP::TimeoutError
      ]
      
      # Which errors are NOT retryable (fail immediately)
      non_retryable_errors [
        E11y::ValidationError,  # Schema validation failed
        E11y::RateLimitError    # Rate limit exceeded
      ]
      
      # Per-adapter retry configuration
      per_adapter do
        adapter :loki do
          max_retries 3
          initial_delay 0.1
        end
        
        adapter :sentry do
          max_retries 5  # More retries for Sentry
          initial_delay 0.5
        end
      end
    end
    
    # === Dead Letter Queue (Failed Events) ===
    dead_letter_queue do
      enabled true
      
      # Where to store failed events (reference to registered adapter)
      adapter :dlq_file  # See ADAPTERS section below
      
      # Max events in DLQ before alerting
      max_size 10_000
      alert_on_size 1000  # Alert when DLQ has 1000+ events
      
      # Auto-cleanup
      retention 7.days  # Delete DLQ events older than 7 days
      
      # Partitioning (for large volumes)
      partition_by :adapter  # Separate DLQ per adapter
      # log/e11y_dlq/loki/2026-01-12.jsonl
      # log/e11y_dlq/sentry/2026-01-12.jsonl
      
      # Compression
      compression :gzip
      
      # Metadata
      include_metadata true  # Store error details, retry count, timestamps
      
      # ===== DLQ FILTER (Important!) =====
      # Control which events are saved to DLQ vs. dropped after max retries
      filter do
        # Always save critical events to DLQ (never drop!)
        always_save do
          severity [:error, :fatal]  # All errors must be preserved
          event_patterns [
            'payment.*',     # Payment events are critical (business value)
            'order.*',       # Order events are critical
            'audit.*',       # Audit events must never be lost (compliance)
            'security.*',    # Security events are critical
            'fraud.*',       # Fraud detection events
            'user.signup',   # User lifecycle events
            'subscription.*' # Subscription events
          ]
        end
        
        # Never save to DLQ (drop after max retries - OK to lose)
        never_save do
          severity [:debug]  # Debug events can be dropped
          event_patterns [
            'metrics.*',       # Metrics can be dropped (regenerated)
            'health_check.*',  # Health checks not critical
            'ping.*',          # Ping events not important
            'telemetry.*'      # Internal telemetry events
          ]
        end
        
        # Custom filter function (for complex logic)
        save_if do |event|
          # Example: Save high-value payments only
          if event.name.include?('payment') && event.payload[:amount]
            event.payload[:amount] > 100  # Only save payments >$100
          elsif event.name.include?('order')
            true  # Always save orders
          else
            # Default: save if not in never_save list
            true
          end
        end
      end
    end
    
    # What to do after max_retries exhausted
    on_max_retries_exceeded :send_to_dlq  # :send_to_dlq, :drop, :log
    
    # Fallback chain (if primary adapter fails after retries)
    fallback_chain do
      adapter :loki do
        fallback :file  # Loki fails → write to file
      end
      
      adapter :elasticsearch do
        fallback :file  # ES fails → write to file
      end
      
      adapter :sentry do
        fallback nil  # Sentry fails → DLQ directly (no fallback)
      end
    end
  end
  
  # ============================================================================
  # UC-022: Event Registry & Introspection
  # ============================================================================
  config.registry do
    enabled true
    
    # Eager load event classes (for registry population)
    eager_load true
    eager_load_paths [
      Rails.root.join('app', 'events')
    ]
    
    # Introspection features
    enable_introspection true  # event.schema_definition, event.adapters, etc.
    
    # Event Explorer Web UI (development only)
    enable_event_explorer Rails.env.development?  # Available at /e11y/events
    event_explorer do
      mount_path '/e11y/events'
      
      # Authentication (for production)
      authenticate_with do |username, password|
        # In production, use real auth:
        username == ENV['E11Y_EXPLORER_USER'] && 
        password == ENV['E11Y_EXPLORER_PASS']
      end
      
      # Features
      show_recent_events true   # Show last 100 tracked events
      enable_test_tracking true # Allow test tracking from UI
      show_metrics true         # Show event metrics
    end
    
    # Auto-generate documentation
    documentation do
      auto_generate false  # Set to true to auto-generate docs on boot
      output_path Rails.root.join('docs', 'EVENTS.md')
      format :markdown  # :markdown, :json, :openapi
    end
  end
  
  # ============================================================================
  # ADAPTERS (Registry)
  # ============================================================================
  config.adapters do
    # Register named adapters (created once with connections)
    
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
    
    # === Archive: S3 (cold storage) ===
    register :s3, E11y::Adapters::S3Adapter.new(
      bucket: ENV['S3_BUCKET'],
      region: ENV['AWS_REGION'],
      prefix: "e11y-events/#{Rails.env}",
      compression: :gzip
    )
    
    # === Security: Audit Log (compliance) ===
    register :audit_file, E11y::Adapters::FileAdapter.new(
      path: Rails.root.join('log', 'audit'),
      permissions: 0600,  # Read-only for owner
      rotation: :never,   # Never rotate (append-only)
      encryption: true
    )
    
    # === Dead Letter Queue (failed events) ===
    register :dlq_file, E11y::Adapters::FileAdapter.new(
      path: Rails.root.join('log', 'e11y_dlq'),
      rotation: :daily,
      compression: :gzip,
      include_metadata: true  # Store error details, retry count
    )
    
    # === Debug: Console (development) ===
    register :console, E11y::Adapters::ConsoleAdapter.new(
      colored: true,
      pretty: true
    )
    
    # === Testing: Memory (tests) ===
    register :memory, E11y::Adapters::MemoryAdapter.new
    
    # === OpenTelemetry: OTLP (collector) ===
    register :otlp, E11y::Adapters::OtlpAdapter.new(
      endpoint: ENV['OTEL_COLLECTOR_URL'] || 'http://localhost:4318',
      protocol: :http,
      headers: { 'X-API-Key' => ENV['OTEL_API_KEY'] }
    )
  end
  
  # Default adapters (used by all events unless overridden)
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
  # BUFFER (Main Buffer for non-debug events)
  # ============================================================================
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
    
    # Backpressure
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
  config.circuit_breaker do
    enabled true
    
    # Per-adapter circuit breakers
    per_adapter true
    
    # Thresholds
    failure_threshold 5       # Open after 5 consecutive failures
    timeout 30.seconds        # Wait before attempting reset
    success_threshold 2       # Close after 2 consecutive successes
    window 60.seconds         # Rolling window for failure count
    
    # Actions when open
    on_open do |adapter_name|
      Rails.logger.error "E11y circuit breaker opened for adapter: #{adapter_name}"
      
      # Send alert
      Events::CircuitBreakerOpened.track(
        adapter: adapter_name,
        severity: :error
      )
    end
    
    # Fallback adapter when circuit is open
    fallback_adapter :file  # Write to file if primary adapter fails
  end
  
  # ============================================================================
  # SELF-MONITORING (Internal Metrics)
  # ============================================================================
  config.self_monitoring do
    enabled true
    
    # Export internal metrics via Yabeda
    export_metrics true
    
    # Metrics to track (see UC-013 for cardinality metrics)
    metrics do
      # Events
      track_events_total true
      track_events_dropped true
      track_events_sampled true
      
      # Buffer
      track_buffer_size true
      track_buffer_usage_ratio true
      track_buffer_overflows true
      
      # Flush
      track_flush_duration true
      track_flush_total true
      track_flush_batch_size true
      
      # Adapters
      track_adapter_errors true
      track_adapter_latency true
      track_adapter_batch_size true
      
      # Rate limiting
      track_rate_limit_hits true
      
      # PII filtering
      track_pii_filtered_fields true
      
      # Circuit breaker
      track_circuit_breaker_state true
      
      # Performance
      track_track_call_duration true  # Overhead of track() method
      track_memory_usage true
      track_gc_stats true
    end
    
    # Health check
    health_check do
      enabled true
      endpoint '/health/e11y'
      
      checks do
        buffer_not_full true
        adapters_healthy true
        circuit_breakers_closed true
        no_recent_errors true
      end
    end
  end
  
  # ============================================================================
  # LIFECYCLE HOOKS
  # ============================================================================
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
  config.shutdown do
    # Timeout for graceful shutdown
    timeout 5.seconds
    
    # Flush remaining events on shutdown
    flush_on_shutdown true
    
    # Wait for workers to finish
    wait_for_workers true
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

## 2. Event Examples

### 2.1. Simple Business Event

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
    
    # Auto-create metric: app_orders_created_total
    metric :counter,
           name: 'orders.created.total',
           tags: [:currency],
           comment: 'Total orders created'
  end
end

# Usage
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
    # Send to all default adapters + S3 archive
    adapters_strategy :append
    adapters [:s3]  # In addition to [:loki, :elasticsearch, :otlp]
    
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

### 2.5. "Fat" Background Job Event

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

## 3. Feature Coverage Matrix

| Feature (UC) | Covered in Config | Covered in Events | Notes |
|-------------|-------------------|-------------------|-------|
| **UC-001: Request-Scoped Debug Buffering** | ✅ `request_scope` | ✅ `:debug` severity | Dual-buffer architecture |
| **UC-002: Business Event Tracking** | ✅ `events` | ✅ All events | Core functionality |
| **UC-003: Pattern-Based Metrics** | ✅ `metrics` | ✅ `metric` DSL | Yabeda integration |
| **UC-004: Zero-Config SLO Tracking** | ✅ `slo` | ✅ Auto for HTTP/Jobs | Built-in tracking |
| **UC-005: Sentry Integration** | ✅ `sentry` | ✅ `sentry_options` | Error capture + breadcrumbs |
| **UC-006: Trace Context Management** | ✅ `tracing` | ✅ `trace_id` in schema | W3C Trace Context |
| **UC-007: PII Filtering** | ✅ `pii_filter` | ✅ Auto-applied | Rails-compatible |
| **UC-008: OpenTelemetry Integration** | ✅ `opentelemetry` | ✅ Auto-mapped | OTLP export |
| **UC-009: Multi-Service Tracing** | ✅ `multi_service_tracing` | ✅ Trace propagation | Service mesh support |
| **UC-010: Background Job Tracking** | ✅ `background_jobs` | ✅ `BackgroundJobExecuted` | Sidekiq/ActiveJob |
| **UC-011: Rate Limiting** | ✅ `rate_limiting` | ✅ Auto-applied | Global + per-event |
| **UC-012: Audit Trail** | ✅ `audit_trail` | ✅ `AuditEvent` base | Cryptographic signing |
| **UC-013: High Cardinality Protection** | ✅ `cardinality_protection` | ✅ Label validation | 4-layer defense |
| **UC-014: Adaptive Sampling** | ✅ `adaptive_sampling` | ✅ Auto-applied | 5 strategies |
| **UC-015: Cost Optimization** | ✅ `cost_optimization` | ✅ Auto-applied | 8 techniques |
| **UC-016: Rails Logger Migration** | ✅ `rails_integration` | ✅ Auto-capture | ActiveSupport::Notifications |
| **UC-017: Local Development** | ✅ `development` | ✅ Console output | Web UI + helpers |
| **UC-018: Testing Events** | ✅ `testing` | ✅ Memory adapter | RSpec matchers |

---

## 4. Conflict Analysis

**(To be filled in next step - analyzing potential conflicts between features)**

### Potential Conflict Areas to Investigate:

1. **Request Buffer + Main Buffer**
   - ✅ Already analyzed: No conflict (dual-buffer)

2. **Rate Limiting + Adaptive Sampling**
   - Question: If event is rate-limited (dropped), does sampling still apply?

3. **PII Filtering + OpenTelemetry Semantic Conventions**
   - Question: Do semantic conventions require fields that might be PII?

4. **Audit Trail Signing + PII Filtering**
   - Question: Does PII filtering happen before or after signing?

5. **Cardinality Protection + Metrics Auto-Creation**
   - Question: Can auto-metrics violate cardinality limits?

6. **Cost Optimization Deduplication + Request-Scoped Buffer**
   - Question: Are debug events deduplicated when flushed on error?

7. **Circuit Breaker + Multi-Adapter Routing**
   - Question: If circuit opens for one adapter, do events still go to others?

8. **Compression + Payload Minimization**
   - Question: Order of operations?

9. **Tiered Storage + Retention Tagging**
   - Question: Duplicate retention configuration?

10. **Background Job Tracing + Adaptive Sampling**
    - Question: Are job events sampled differently than HTTP?

---

**Status:** Configuration Complete ✅  
**Next Step:** Conflict Analysis 🔍

