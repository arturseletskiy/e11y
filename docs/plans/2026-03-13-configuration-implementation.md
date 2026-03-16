# E11y Configuration Refactoring — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Flatten E11y configuration to Devise-inspired flat accessors, update generator to full initializer, no backward compatibility.

**Architecture:** Replace nested config objects (rails_instrumentation, logger_bridge, etc.) with flat `config.<section>_<option>` accessors on Configuration. Keep pipeline, adapters as-is. Add helper methods for rate_limiting per-event rules, SLO controller/job configs.

**Tech Stack:** Ruby, Rails, RSpec, Cucumber

**Reference:** `docs/plans/2026-03-13-configuration-design.md` (mapping table)

---

## Phase 1: Configuration Class — Flat Accessors

### Task 1: Add flat accessors for Rails integration (rails_instrumentation, sidekiq, active_job, logger_bridge)

**Files:**
- Modify: `lib/e11y.rb:244-291` (Configuration#initialize, attr_accessor)

**Step 1: Add flat accessors and remove nested objects**

In `Configuration` class:
- Remove `attr_reader :rails_instrumentation, :logger_bridge, :sidekiq, :active_job`
- Add `attr_accessor` for: `rails_instrumentation_enabled`, `rails_instrumentation_custom_mappings`, `rails_instrumentation_ignore_events`, `logger_bridge_enabled`, `logger_bridge_track_severities`, `logger_bridge_ignore_patterns`, `sidekiq_enabled`, `active_job_enabled`
- In `initialize`, set defaults:
  - `@rails_instrumentation_enabled = false`
  - `@rails_instrumentation_custom_mappings = {}`
  - `@rails_instrumentation_ignore_events = []`
  - `@logger_bridge_enabled = false`
  - `@logger_bridge_track_severities = nil`
  - `@logger_bridge_ignore_patterns = []`
  - `@sidekiq_enabled = false`
  - `@active_job_enabled = false`
- Remove `initialize_feature_configs` calls for RailsInstrumentationConfig, LoggerBridgeConfig, ActiveJobConfig, SidekiqConfig
- Add compatibility methods (temporary, for incremental migration): `def rails_instrumentation` → struct with enabled, custom_mappings, ignore_events from flat; same for logger_bridge, sidekiq, active_job. **OR** skip compatibility and update all consumers in same phase.

**Step 2: Update Railtie**

File: `lib/e11y/railtie.rb:66-69`

```ruby
E11y::Railtie.setup_rails_instrumentation if E11y.config.rails_instrumentation_enabled
E11y::Railtie.setup_logger_bridge if E11y.config.logger_bridge_enabled
E11y::Railtie.setup_sidekiq if defined?(::Sidekiq) && E11y.config.sidekiq_enabled
E11y::Railtie.setup_active_job if defined?(::ActiveJob) && E11y.config.active_job_enabled
```

**Step 3: Update lib/e11y/instruments/rails_instrumentation.rb**

Replace `E11y.config.rails_instrumentation&.enabled` → `E11y.config.rails_instrumentation_enabled`
Replace `E11y.config.rails_instrumentation&.custom_mappings` → `E11y.config.rails_instrumentation_custom_mappings`
Replace `E11y.config.rails_instrumentation&.ignore_events` → `E11y.config.rails_instrumentation_ignore_events`

**Step 4: Update lib/e11y/logger/bridge.rb**

Replace `E11y.config.logger_bridge&.enabled` → `E11y.config.logger_bridge_enabled`
Replace `cfg&.track_severities` → `E11y.config.logger_bridge_track_severities`
Replace `cfg&.ignore_patterns` → `E11y.config.logger_bridge_ignore_patterns` (pass config to Bridge or read in initialize)

**Step 5: Run tests**

```bash
bundle exec rspec spec/e11y/instruments/ spec/e11y/logger/ spec/integration/railtie_integration_spec.rb spec/integration/sidekiq_integration_spec.rb -f d
```

**Step 6: Commit**

```bash
git add lib/e11y.rb lib/e11y/railtie.rb lib/e11y/instruments/rails_instrumentation.rb lib/e11y/logger/bridge.rb
git commit -m "refactor(config): flatten rails_instrumentation, logger_bridge, sidekiq, active_job"
```

---

### Task 2: Add flat accessors for ephemeral_buffer, error_handling

**Files:**
- Modify: `lib/e11y.rb` (Configuration)
- Modify: `lib/e11y/instruments/active_job.rb`, `lib/e11y/instruments/sidekiq.rb`, `lib/e11y/buffers/ephemeral_buffer.rb`, `lib/e11y/adapters/base.rb`, `lib/e11y/middleware/request.rb`

**Step 1: Add flat accessors**

- `ephemeral_buffer_enabled`, `ephemeral_buffer_flush_on_error`, `ephemeral_buffer_flush_on_statuses`, `ephemeral_buffer_debug_adapters`, `ephemeral_buffer_job_buffer_limit`
- `error_handling_fail_on_error`

**Step 2: Update all consumers**

Grep for `ephemeral_buffer` and `error_handling` and replace with flat equivalents.

**Step 3: Run tests**

```bash
bundle exec rspec spec/e11y/instruments/ spec/e11y/buffers/ spec/e11y/adapters/ -f d
```

**Step 4: Commit**

```bash
git commit -m "refactor(config): flatten ephemeral_buffer, error_handling"
```

---

### Task 3: Add flat accessors for rate_limiting, slo_tracking

**Files:**
- Modify: `lib/e11y.rb` (Configuration)
- Modify: `lib/e11y/middleware/rate_limiting.rb`, `lib/e11y/slo/tracker.rb`, `lib/e11y/instruments/active_job.rb`

**Step 1: Add flat accessors**

- `rate_limiting_enabled`, `rate_limiting_global_limit`, `rate_limiting_global_window`, `rate_limiting_per_event_limit`, `rate_limiting_per_event_limits`
- Add `def add_rate_limit_per_event(pattern, limit:, window: 1.0)` — appends to `rate_limiting_per_event_limits`
- Add `def rate_limit_for(event_name)` — lookup logic from old RateLimitingConfig#limit_for

- `slo_tracking_enabled`, `slo_tracking_http_ignore_statuses`, `slo_tracking_latency_percentiles`, `slo_tracking_controller_configs`, `slo_tracking_job_configs`
- Add `def add_slo_controller(name, action: nil, &block)` — populates controller_configs
- Add `def add_slo_job(name, &block)` — populates job_configs

**Step 2: Remove rate_limiting { } and slo { } block DSLs**

- Remove `def rate_limiting(&)` and `def slo(&)` and `def slo_tracking(&)`
- Remove `RateLimitingConfig`, `SLOTrackingConfig` classes (or keep for internal use, populated from flat config)

**Step 3: Update middleware and consumers**

- `lib/e11y/middleware/rate_limiting.rb`: read from `E11y.config.rate_limiting_enabled`, `E11y.config.rate_limit_for(event_name)`
- `lib/e11y/slo/tracker.rb`: read from `E11y.config.slo_tracking_enabled`, etc.

**Step 4: Run tests**

```bash
bundle exec rspec spec/e11y/middleware/rate_limiting_spec.rb spec/e11y/slo/ spec/e11y/configuration_dsl_spec.rb -f d
```

**Step 5: Commit**

```bash
git commit -m "refactor(config): flatten rate_limiting, slo_tracking"
```

---

### Task 4: Add flat accessors for security, tracing, opentelemetry, cardinality_protection

**Files:**
- Modify: `lib/e11y.rb` (Configuration)
- Modify: `lib/e11y/middleware/baggage_protection.rb`, `lib/e11y/middleware/trace_context.rb`, `lib/e11y/opentelemetry/span_creator.rb`

**Step 1: Add flat accessors**

- `security_baggage_protection_enabled`, `security_baggage_protection_allowed_keys`, `security_baggage_protection_block_mode`
- `tracing_source`, `tracing_default_sample_rate`, `tracing_respect_parent_sampling`, `tracing_per_event_sample_rates`, `tracing_always_sample_if`
- `opentelemetry_span_creation_patterns`
- `cardinality_protection_max_cardinality_limit`, `cardinality_protection_denylist`, `cardinality_protection_overflow_strategy`

**Step 2: Remove block DSLs**

- Remove `def security(&)`, `def tracing(&)`, `def opentelemetry(&)`, `def cardinality_protection(&)`
- BaggageProtection middleware: read from flat config. Add helper `def security_baggage_protection` returning struct with enabled, allowed_keys, block_mode for internal use, or read directly.

**Step 3: Update consumers**

- `lib/e11y/middleware/baggage_protection.rb`: `config = E11y.config`; use `config.security_baggage_protection_enabled`, `config.security_baggage_protection_allowed_keys`, etc.
- `lib/e11y/middleware/trace_context.rb`: `E11y.config.tracing_source`
- `lib/e11y/opentelemetry/span_creator.rb`: `E11y.config.opentelemetry_span_creation_patterns`
- `lib/e11y/current.rb`: update baggage filter to use flat config

**Step 4: Run tests**

```bash
bundle exec rspec spec/e11y/middleware/baggage_protection_spec.rb spec/e11y/opentelemetry/ spec/integration/baggage_protection_integration_spec.rb -f d
```

**Step 5: Commit**

```bash
git commit -m "refactor(config): flatten security, tracing, opentelemetry, cardinality_protection"
```

---

### Task 5: Remove dead config classes and clean up Configuration

**Files:**
- Modify: `lib/e11y.rb`

**Step 1: Delete unused classes**

- Remove `RailsInstrumentationConfig`, `LoggerBridgeConfig`, `ActiveJobConfig`, `SidekiqConfig`, `Config` (ephemeral), `ErrorHandlingConfig`, `RateLimitingConfig`, `SLOTrackingConfig`, `OpenTelemetryConfig`, `TracingConfig`, `SecurityConfig`, `BaggageProtectionConfig`, `CardinalityProtectionConfig` if no longer used.

**Step 2: Remove dlq_filter, dlq_storage from nested — keep as top-level**

- `config.dlq_filter` and `config.dlq_storage` stay as-is (they are top-level, not nested).

**Step 3: Run full test suite**

```bash
bundle exec rspec
bundle exec cucumber
```

**Step 4: Commit**

```bash
git commit -m "refactor(config): remove dead config classes"
```

---

## Phase 2: Update Specs and Docs

### Task 6: Update all specs to use flat config

**Files:**
- Modify: All spec files that use nested config (see grep results)

**Step 1: Replace in specs**

Examples:
- `config.rails_instrumentation.enabled = true` → `config.rails_instrumentation_enabled = true`
- `config.logger_bridge.track_severities` → `config.logger_bridge_track_severities`
- `E11y.config.error_handling.fail_on_error` → `E11y.config.error_handling_fail_on_error`
- `config.ephemeral_buffer.enabled` → `config.ephemeral_buffer_enabled`
- `config.rate_limiting.enabled` → `config.rate_limiting_enabled`
- `config.slo_tracking.enabled` → `config.slo_tracking_enabled`
- `config.security.baggage_protection do ... end` → `config.security_baggage_protection_enabled = true; config.security_baggage_protection_allowed_keys = [...]`
- `E11y.config.opentelemetry.span_creation_patterns` → `E11y.config.opentelemetry_span_creation_patterns`

**Step 2: Update features/support/hooks.rb**

```ruby
E11y.config.rate_limiting_enabled = false
E11y.config.rate_limiting_global_limit = 10_000
E11y.config.rate_limiting_per_event_limit = 1_000
E11y.config.rate_limiting_global_window = 1.0
E11y.config.ephemeral_buffer_enabled = false
```

**Step 3: Update features/step_definitions**

- `ephemeral_buffer_steps.rb`, `default_pipeline_steps.rb`, `slo_tracking_steps.rb`

**Step 4: Update spec/dummy/config/application.rb**

```ruby
config.rails_instrumentation_enabled = true
config.active_job_enabled = true
config.sidekiq_enabled = true if defined?(Sidekiq)
config.logger_bridge_enabled = false
```

**Step 5: Run tests**

```bash
bundle exec rspec
bundle exec cucumber
```

**Step 6: Commit**

```bash
git commit -m "test: update specs and features for flat config"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `README.md`, `docs/RAILS_INTEGRATION.md`, `docs/QUICK-START.md`, `docs/ADR-008-rails-integration.md`, `docs/use_cases/*.md`, `docs/ADR-*.md`, etc.

**Step 1: Global replace**

Replace all nested config examples with flat equivalents. Use search_replace across docs.

**Step 2: Commit**

```bash
git commit -m "docs: update config examples to flat API"
```

---

## Phase 3: Generator

### Task 8: Create Devise-style initializer template

**Files:**
- Modify: `lib/generators/e11y/install/templates/e11y.rb`
- Optionally: `lib/generators/e11y/install/install_generator.rb`

**Step 1: Create full initializer template**

```ruby
# frozen_string_literal: true

# E11y configuration — generated by `rails g e11y:install`
# Docs: https://github.com/arturseletskiy/e11y

E11y.configure do |config|
  # =============================================================================
  # BASIC
  # =============================================================================
  config.service_name = ENV["SERVICE_NAME"] || Rails.application.class.module_parent_name.underscore
  config.environment = Rails.env.to_s
  config.enabled = !Rails.env.test?
  config.default_retention_period = 30.days
  config.log_level = :info

  # =============================================================================
  # ADAPTERS
  # =============================================================================
  config.adapters[:logs] = E11y::Adapters::Stdout.new(colorize: true)
  # config.adapters[:logs] = E11y::Adapters::Loki.new(url: ENV.fetch("LOKI_URL", "http://localhost:3100"))
  # config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(dsn: ENV["SENTRY_DSN"])

  # =============================================================================
  # RAILS INTEGRATION
  # =============================================================================
  config.rails_instrumentation_enabled = true
  config.sidekiq_enabled = defined?(Sidekiq)
  config.active_job_enabled = true
  config.logger_bridge_enabled = false
  # config.logger_bridge_track_severities = nil  # nil = all
  # config.logger_bridge_ignore_patterns = [/Started GET/, /Completed \d+ OK/]

  # =============================================================================
  # EPHEMERAL BUFFER (request/job-scoped debug events)
  # =============================================================================
  config.ephemeral_buffer_enabled = false
  # config.ephemeral_buffer_flush_on_error = true
  # config.ephemeral_buffer_flush_on_statuses = []
  # config.ephemeral_buffer_job_buffer_limit = nil

  # =============================================================================
  # ERROR HANDLING
  # =============================================================================
  config.error_handling_fail_on_error = true

  # =============================================================================
  # SLO TRACKING
  # =============================================================================
  config.slo_tracking_enabled = true
  # config.slo_tracking_http_ignore_statuses = [404, 401]
  # config.slo_tracking_latency_percentiles = [50, 95, 99]

  # =============================================================================
  # RATE LIMITING
  # =============================================================================
  config.rate_limiting_enabled = false
  # config.rate_limiting_global_limit = 10_000
  # config.rate_limiting_global_window = 1.0
  # config.add_rate_limit_per_event "payment.*", limit: 500, window: 1.minute

  # =============================================================================
  # SECURITY (Baggage PII protection)
  # =============================================================================
  config.security_baggage_protection_enabled = true
  # config.security_baggage_protection_allowed_keys = %w[trace_id span_id ...]
  # config.security_baggage_protection_block_mode = :silent

  # =============================================================================
  # TRACING (OpenTelemetry)
  # =============================================================================
  # config.tracing_source = :e11y
  # config.opentelemetry_span_creation_patterns = ["order.*", "payment.*"]
end
```

**Step 2: Run generator**

```bash
cd spec/dummy && rails g e11y:install --force
```

**Step 3: Verify generated file**

```bash
cat spec/dummy/config/initializers/e11y.rb
```

**Step 4: Commit**

```bash
git commit -m "feat(generator): Devise-style full initializer template"
```

---

## Phase 4: Final Verification

### Task 9: Full test suite and CHANGELOG

**Step 1: Run full suite**

```bash
bundle exec rspec
bundle exec cucumber
```

**Step 2: Add CHANGELOG entry**

```markdown
## [Unreleased]

### Breaking Changes

- **Configuration:** Flat config API. Nested config objects removed.
  - `config.rails_instrumentation.enabled` → `config.rails_instrumentation_enabled`
  - `config.logger_bridge.track_severities` → `config.logger_bridge_track_severities`
  - `config.rate_limiting { }` block removed → use `config.rate_limiting_enabled`, `config.add_rate_limit_per_event(...)`
  - `config.slo { }` block removed → use `config.slo_tracking_enabled`, `config.add_slo_controller(...)`
  - See docs/plans/2026-03-13-configuration-design.md for full mapping.
```

**Step 3: Commit**

```bash
git commit -m "chore: add CHANGELOG for config breaking changes"
```

---

## Execution Options

**Plan complete and saved to `docs/plans/2026-03-13-configuration-implementation.md`. Two execution options:**

1. **Subagent-Driven (this session)** — Dispatch fresh subagent per task, review between tasks, fast iteration

2. **Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
