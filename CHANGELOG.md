# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Sidekiq and Active Job: propagate **`user_id`** into **`e11y_baggage`** (and restore **`E11y::Current.user_id`** when the job runs). Key **`user_id`** is included in default baggage allowlist.

### Changed

### Fixed

- **Rails Railtie:** `config.enabled` is defaulted with `!Rails.env.test?` **only when still `nil`**, so an explicit `true`/`false` from `E11y.configure` in `config/application.rb` (or any code that runs before `before_initialize`) is no longer overwritten.

### Deprecated

### Removed

- **`E11y.track`** — removed. Call **`YourEvent.track(...)`** on the event class only.

### Security

## [1.0.0] - 2026-03-20

### BREAKING: Configuration — Flat config API

**Nested config objects removed.** All configuration options are now flat accessors on `config`.

**Key migrations:**
- `config.rails_instrumentation.enabled` → `config.rails_instrumentation_enabled`
- `config.logger_bridge.track_severities` → `config.logger_bridge_track_severities`
- `config.rate_limiting { }` removed → use `config.rate_limiting_enabled`, `config.add_rate_limit_per_event(...)`
- `config.slo { }` removed → use `config.slo_tracking_enabled`, `config.add_slo_controller(...)`

**Full mapping:** See `docs/plans/2026-03-13-configuration-design.md`

### BREAKING: Middleware order changed (ADR-015 compliance)

**Per ADR-015 and ADR-006:**
- **Versioning** moved to last (before Routing) — Validation, PII, RateLimiting, Sampling now use original class names
- **AuditSigning** before PIIFilter — audit events signed with original data (GDPR Art. 30 non-repudiation)
- **RateLimiting** before Sampling — matches ADR #4, #5

**New order:** TraceContext → Validation → AuditSigning → PIIFilter → RateLimiting → Sampling → Versioning → Routing → EventSlo

**Migration:** If you custom-configured pipeline order, ensure Versioning is last before Routing. Audit events now receive unfiltered payload at signing.

### BREAKING: Registry.all_events → Registry.event_classes

**Renamed for clarity:** Method returns event classes, not event instances or names.

**Migration:** `E11y::Registry.all_events` → `E11y::Registry.event_classes`

### BREAKING: RequestScopedBuffer → EphemeralBuffer

**Renamed for accuracy:** The buffer works for both HTTP requests and background jobs. "Ephemeral" reflects its temporary lifecycle.

**Migration:**
- `E11y::Buffers::RequestScopedBuffer` → `E11y::Buffers::EphemeralBuffer`
- `config.request_buffer` → `config.ephemeral_buffer`
- `Thread.current[:e11y_request_buffer]` → `Thread.current[:e11y_ephemeral_buffer]`
- Yabeda metric `e11y_request_buffer_total` → `e11y_ephemeral_buffer_total`

**Search and replace:** `RequestScopedBuffer` → `EphemeralBuffer`, `request_buffer` → `ephemeral_buffer`

### Added

- Monorepo release tooling: `rake release:build_gems` and `rake release:gem_push` build/publish **e11y** and **e11y-devtools**; optional `release:rubygems:push_core` / `push_devtools`; GitHub Release workflow attaches both `.gem` files.

### Changed

- **e11y-devtools** 0.1.1 — depends on **e11y** `~> 1.0` (`CORE_VERSION`); README Gemfile example updated.

### Fixed

### Deprecated

### Removed

### Security

## [0.2.0] - 2026-01-26

### Added
- Multi-Rails version support (7.0, 7.1, 8.0) (#5)
  - CI matrix testing across Ruby 3.2, 3.3 with Rails 7.0, 7.1, 8.0
  - Dynamic Gemfile dependencies based on RAILS_VERSION env var
  - Support for sqlite3 1.4 (Rails 7.x) and 2.0 (Rails 8.x)
- Comprehensive test suite documentation in README (#5)
  - Quick commands using rake tasks
  - Manual commands for each test suite
  - Test suite overview with timing and example counts
  - Development commands reference
- Climate Control gem for ENV manipulation in tests (#5)

### Fixed
- **RequestScopedBuffer API method names** (#5)
  - `start!` → `initialize!` (correct initialization method)
  - `flush!` → `discard` (for success path - discard buffered events)
  - `flush_on_error!` → `flush_on_error` (remove bang, method doesn't modify in-place)
  - This eliminates warning messages during test execution
  - **BREAKING CHANGE:** If you use `E11y::Buffers::RequestScopedBuffer` directly, update method names
- Rails instrumentation event namespaces (#5)
  - Fixed: `"Events::Rails::*"` → `"E11y::Events::Rails::*"`
  - Resolves uninitialized constant errors in Rails instrumentation
- Rails 8.0 exception handling test compatibility (#5)
  - Updated error handling test to support both Rails 7.x and 8.0 behaviors
  - Rails 8.0 changed: exceptions caught and converted to 500 responses
  - Rails 7.x: exceptions raised with show_exceptions = false
- HTTP request format validation (#5)
  - Now accepts Symbol (e.g., :html, :json) as Rails passes format as Symbol
  - Removed strict :string type check from format field
- Integration test isolation issues (#5)
  - Moved Rails initialization to spec_helper.rb (prevents FrozenError)
  - Renamed TestJob → DummyTestJob to prevent class conflicts
  - Fixed railtie integration spec tag isolation
  - Added File.exist? check for routes file in railtie tests
- Floating point precision in stratified sampling tests (#5)
  - Increased upper bound from 0.95 to 0.96 to handle FP precision
  - Fixes intermittent test failures: expected 0.9500000000000001 to be <= 0.95
- Test isolation in active_job_spec.rb (#5)
  - Store and restore original request_buffer.enabled config
  - Prevents config changes from affecting subsequent tests
- View rendering instrumentation test (#5)
  - Added posts/list.html.erb template
  - Added posts#list action to render HTML views
  - Implemented complete test for view rendering events (was pending)

### Changed
- CI workflow now tests against multiple Rails versions (#5)
  - Matrix: Ruby 3.2, 3.3 × Rails 7.0, 7.1, 8.0
  - Separate artifact uploads per Ruby/Rails combination
  - Enhanced test output with Rails version information
- Improved test execution speed with better organization (#5)
  - Separate rake tasks: spec:unit, spec:integration, spec:railtie
  - Unit tests exclude integration and railtie specs
  - Integration tests run only integration specs
  - Total: 1729 examples (1672 unit + 36 integration + 21 railtie)
- RuboCop configuration (#5)
  - Exclude spec/integration/**/* from RSpec/DescribeClass cop
  - Integration tests don't always describe a specific class

### Breaking Changes

#### RequestScopedBuffer API (affects only direct usage)

If you use `E11y::Buffers::RequestScopedBuffer` directly in your code, update method names:

**Before (incorrect):**
```ruby
E11y::Buffers::RequestScopedBuffer.start!          # ❌ Wrong
E11y::Buffers::RequestScopedBuffer.flush!          # ❌ Wrong
E11y::Buffers::RequestScopedBuffer.flush_on_error! # ❌ Wrong
```

**After (correct):**
```ruby
E11y::Buffers::RequestScopedBuffer.initialize!     # ✅ Correct
E11y::Buffers::RequestScopedBuffer.discard         # ✅ Correct
E11y::Buffers::RequestScopedBuffer.flush_on_error  # ✅ Correct
```

**Impact:** LOW - RequestScopedBuffer is an internal API. Most users are not affected as the middleware, ActiveJob, and Sidekiq instrumentations are already updated. Only users who directly call these methods need to update their code.

**Migration:** Search your codebase for `RequestScopedBuffer` and update method names if found.

---

## [0.1.0] - 2026-01-17

Initial release of E11y - Event-driven observability for Rails applications.

### Features

- **Core Event System**
  - Unified event API with dry-schema validation
  - Type-safe event schemas
  - Extensible adapter architecture
  - Request-scoped debug buffering

- **Rails Integration**
  - Automatic Rails instrumentation
  - ActiveJob tracking
  - Sidekiq middleware
  - Rails.logger bridge
  - Trace context propagation

- **Adapters**
  - Loki (logs)
  - Prometheus (metrics)
  - Sentry (errors)
  - OpenTelemetry (traces)
  - Elasticsearch (search)
  - Redis (fast writes)
  - Audit log (encrypted storage)

- **Advanced Features**
  - Event-level metrics (metrics DSL)
  - PII filtering with configurable rules
  - Stratified sampling
  - Rate limiting
  - High-cardinality protection
  - Error handling with retry and DLQ

- **Developer Experience**
  - RSpec matchers for testing
  - InMemory test adapter
  - Zero-config defaults
  - Comprehensive documentation
  - 25+ ADRs and use cases

### Supported Versions

- Ruby: 3.2, 3.3
- Rails: 8.0
- RSpec: 3.13+

### Documentation

- 17 Architecture Decision Records (ADRs)
- 22 Use Cases with examples
- Complete API documentation
- Testing guide
- Migration guides
