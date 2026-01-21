# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Integration Tests** - Full test suite for Rails, OpenTelemetry, and external services
  - Rails 8.0 integration tests (Railtie, middleware, instrumentation)
  - OpenTelemetry SDK integration tests (OTel Logs API, severity mapping, baggage protection)
  - ActiveJob integration tests (hybrid tracing, context isolation, error handling)
  - Docker Compose setup for Loki, Prometheus, Elasticsearch, Redis
  - `bin/test-integration` script for automated integration testing
  - CI/CD: Separate jobs for unit tests (fast) and integration tests (with services)
  - Documentation: [Integration Testing Guide](docs/testing/integration-tests.md)

### Changed
- **Retention-Based Routing** - Replaced TieredStorage adapter with flexible lambda-based routing
  - Events declare `retention_period` (e.g., `7.days`, `7.years`)
  - Routing middleware auto-calculates `retention_until` and selects optimal adapters
  - 80-97% cost savings via automatic tiered routing (hot/warm/cold storage)
- **Configuration** - Added `default_retention_period` and `routing_rules` (lambda-based)
- **Event::Base** - Added `retention_period` DSL method, `retention_until` auto-calculated in `track()`
- **Middleware::Routing** - Rewritten to support retention-based adapter selection
- **Test Organization** - Unit tests run by default, integration tests require `INTEGRATION=true`

### Removed
- **TieredStorage Adapter** - Removed in favor of retention-based routing (more flexible)

## [1.0.0] - 2026-01-21

### 🎉 First Production Release

Production-ready observability gem for Ruby on Rails with zero-config SLO tracking, request-scoped buffering, and high-performance event streaming.

### Added - Core Architecture (Phase 1)

- **Event System** - Type-safe event classes with dry-schema validation
- **Pipeline Architecture** - Middleware-based event processing with routing, sampling, PII filtering
- **Adapters** - Pluggable backends: Stdout, File, InMemory, Loki, Sentry, OpenTelemetry, Yabeda
- **Buffers** - Lock-free RingBuffer, RequestScopedBuffer, AdaptiveBuffer with auto-scaling
- **Configuration DSL** - Flexible Ruby DSL for gem configuration

### Added - Reliability & Observability (Phase 2)

- **Retry Handler** - Exponential backoff with jitter, configurable retry policies
- **Circuit Breaker** - Automatic failure detection and recovery
- **Dead Letter Queue (DLQ)** - Failed event persistence with file storage backend
- **Self-Monitoring** - Buffer health, performance metrics, reliability tracking
- **Rate Limiting** - Token bucket algorithm for event flow control

### Added - SLO Tracking (Phase 3)

- **Event-Driven SLOs** - Automatic SLO tracking for HTTP requests and background jobs
- **Stratified Sampling** - Maintain representative samples across latency percentiles
- **Error Spike Detection** - Adaptive sampling during error bursts
- **Value-Based Sampling** - Sample by severity, user_id, endpoint patterns
- **Load Monitoring** - CPU/memory-aware sampling rate adjustment

### Added - Rails Integration (Phase 4)

- **Rails Instrumentation** - Auto-track ActiveSupport::Notifications events
- **HTTP Request Tracking** - Automatic controller action monitoring with SLOs
- **Background Job Tracking** - ActiveJob and Sidekiq instrumentation
- **Database Query Events** - SQL query monitoring with duration tracking
- **View Rendering Events** - Template rendering metrics
- **Cache Events** - Redis/Memcached operation tracking
- **Logger Bridge** - Rails.logger → E11y event conversion

### Added - Scale & Performance (Phase 5)

- **Cardinality Protection** - 4-layer defense against metric explosions
  - Layer 1: Static limits (100-10K labels)
  - Layer 2: Sliding window detection
  - Layer 3: Pattern-based tracking
  - Layer 4: Dynamic actions (drop/alert/relabel)
- **Tiered Storage Adapter** - Cost-optimized event retention (hot/warm/cold tiers)
- **Performance Optimization** - Benchmarked for 100K events/sec throughput
  - Latency: p99 <50μs (small scale)
  - Memory: <100MB (1K events)
  - Throughput: >100K events/sec per process

### Added - Security & Compliance

- **PII Filtering** - Automatic redaction of emails, phones, SSNs, credit cards, IPs
- **Audit Event Signing** - Cryptographic signatures for tamper-proof audit logs
- **Audit Encryption** - AES-256-GCM encryption for sensitive events
- **Versioning Middleware** - Event schema version tracking

### Added - Documentation

- **16 Architecture Decision Records (ADRs)** - Documented design decisions
- **API Reference** - Complete public API documentation
- **Benchmark Suite** - 3-scale performance validation (small/medium/large)
- **72 Spec Files** - 1409 test examples with 99%+ pass rate

### Performance

- **Latency:** p99 <50μs for track() calls
- **Throughput:** 100K+ events/sec per Ruby process
- **Memory:** 2KB per event, <100MB for 1K events
- **Thread-Safe:** Lock-free buffers, concurrent event processing

### Requirements

- Ruby >= 3.2.0
- Rails >= 7.0 (optional, for Rails instrumentation)
- ActiveSupport >= 7.0

### Dependencies

- `activesupport` >= 7.0
- `concurrent-ruby` ~> 1.2 (thread-safe data structures)
- `dry-schema` ~> 1.13 (event validation)
- `dry-types` ~> 1.7
- `zeitwerk` ~> 2.6

## [0.1.0] - 2026-01-17

### Added
- Project initialization
- Phase 0: Gem Setup & Best Practices Research complete
- Research documents for 6 successful gems (Devise, Sidekiq, Puma, Dry-rb, Yabeda, Sentry)
- Best practices synthesis for configuration DSL, testing, documentation, CI/CD, release process

[Unreleased]: https://github.com/arturseletskiy/e11y/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/arturseletskiy/e11y/releases/tag/v1.0.0
[0.1.0]: https://github.com/arturseletskiy/e11y/releases/tag/v0.1.0
