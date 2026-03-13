# E11y Use Cases Documentation

Эта папка содержит детальные use cases для различных сценариев использования E11y gem.

## 📁 Структура

### Core Use Cases
- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - Killer feature: debug events только при ошибках
- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Структурированные бизнес-события
- **[UC-003: Event Metrics](./UC-003-event-metrics.md)** - Метрики в event-классах
- **[UC-004: Zero-Config SLO Tracking](./UC-004-zero-config-slo-tracking.md)** - Built-in SLO monitoring

### Integration Use Cases
- **[UC-005: Sentry Integration](./UC-005-sentry-integration.md)** - Error tracking с автоматическими breadcrumbs
- **[UC-006: Trace Context Management](./UC-006-trace-context-management.md)** - Автоматическая корреляция через trace_id
- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - Rails-compatible PII filtering
- **[UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md)** - OTel compatibility
- **[UC-009: Multi-Service Tracing](./UC-009-multi-service-tracing.md)** - Distributed tracing
- **[UC-010: Background Job Tracking](./UC-010-background-job-tracking.md)** - Sidekiq/ActiveJob

### Security & Compliance
- **[UC-011: Rate Limiting](./UC-011-rate-limiting.md)** - DoS protection
- **[UC-012: Audit Trail](./UC-012-audit-trail.md)** - Compliance-ready audit logging

### Performance & Scale
- **[UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md)** - Prevent metric explosions
- **[UC-014: Adaptive Sampling](./UC-014-adaptive-sampling.md)** - Dynamic sampling
- **[UC-015: Cost Optimization](./UC-015-cost-optimization.md)** - Reduce observability costs
- **[UC-019: Tiered Storage & Data Lifecycle](./UC-019-tiered-storage-migration.md)** - Automatic data lifecycle management

### Developer Experience
- **[UC-016: Rails Logger Migration](./UC-016-rails-logger-migration.md)** - Migrate from Rails.logger
- **[UC-017: Local Development](./UC-017-local-development.md)** - Development workflow
- **[UC-018: Testing Events](./UC-018-testing-events.md)** - Test strategies
- **[UC-020: Event Versioning](./UC-020-event-versioning.md)** - Schema evolution & backward compatibility
- **[UC-021: Error Handling & DLQ](./UC-021-error-handling-retry-dlq.md)** - Retry policy & dead letter queue
- **[UC-022: Event Registry](./UC-022-event-registry.md)** - Event introspection & discovery

## 🎯 Use Case Categories

### By User Role

**Ruby/Rails Developers:**
- UC-002 (Business Event Tracking)
- UC-014 (Rails Logger Migration)
- UC-015 (Local Development)
- UC-016 (Testing Events)

**DevOps/SRE Engineers:**
- UC-001 (Request-Scoped Debug Buffering)
- UC-004 (Zero-Config SLO Tracking)
- UC-008 (OpenTelemetry Integration)
- UC-011 (Adaptive Sampling)

**Security/Compliance Teams:**
- UC-007 (PII Filtering)
- UC-011 (Rate Limiting)
- UC-012 (Audit Trail)

**Engineering Managers/CTOs:**
- UC-015 (Cost Optimization)
- UC-013 (High Cardinality Protection)
- UC-003 (Event Metrics)

### By Complexity

**Beginner (5-15 min setup):**
- UC-002 (Business Event Tracking)
- UC-005 (Sentry Integration)
- UC-016 (Rails Logger Migration)
- UC-017 (Local Development)

**Intermediate (15-60 min setup):**
- UC-001 (Request-Scoped Debug Buffering)
- UC-003 (Event Metrics)
- UC-004 (Zero-Config SLO Tracking)
- UC-006 (Trace Context Management)
- UC-007 (PII Filtering)
- UC-010 (Background Job Tracking)

**Advanced (1+ hour setup):**
- UC-008 (OpenTelemetry Integration)
- UC-009 (Multi-Service Tracing)
- UC-013 (High Cardinality Protection)
- UC-014 (Adaptive Sampling)
- UC-015 (Cost Optimization)

## 📖 How to Use This Documentation

### For New Users
Start with:
1. UC-002 (Business Event Tracking) - понять основы
2. UC-015 (Local Development) - настроить локально
3. UC-004 (Zero-Config SLO Tracking) - получить метрики

### For Production Deployment
Review:
1. UC-001 (Request-Scoped Debug Buffering)
2. UC-007 (PII Filtering)
3. UC-011 (Rate Limiting)
4. UC-015 (Cost Optimization)

### For Migration from Existing Tools
See:
1. UC-016 (Rails Logger Migration)
2. UC-008 (OpenTelemetry Integration) - если уже используете OTel
3. UC-009 (Multi-Service Tracing) - если microservices

## 🔗 Related Documentation

- **[Quick Start Guide](../E11Y-QUICK-START.md)** - 5-minute setup
- **[API Reference](../api/README.md)** - Detailed API docs
- **[Architecture Overview](../architecture/README.md)** - System design
- **[Configuration Guide](../configuration/README.md)** - All config options

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026
