# E11y - Complete Documentation

> **E11y** = **e**asy t**e**lemetry (11 букв между 'e' и 'y', как i18n, l10n)

Production-ready Ruby gem для структурированных бизнес-событий с request-scoped buffering, event metrics и zero-config SLO tracking.

---

## 🚀 Quick Links

- **[Quick Start Guide](./QUICK-START.md)** - 5-minute setup
- **[SLO Implementation Guide](./SLO-IMPLEMENTATION-GUIDE.md)** ⭐ Quick navigation for SLO setup
- **[Configuration Reference](./COMPREHENSIVE-CONFIGURATION.md)** - All config options
- **[ADR Coverage Check](./ADR-COVERAGE-CHECK.md)** - Architecture decisions

---

## 🎯 **NEW: IMPLEMENTATION PLAN (2026-01-17)** ⭐

**Complete implementation plan ready for execution!**

- 📄 **[IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)** - Main plan
  - 6 phases, 19 components, 220+ tasks with DoD
  - Parallelization strategy, integration contracts

- 📄 **[IMPLEMENTATION_PLAN_ARCHITECTURE.md](./IMPLEMENTATION_PLAN_ARCHITECTURE.md)** - Architecture decisions
  - Critical questions & answers (Q1-Q4)
  - Unidirectional ASN flow, overridable event classes, Phase 0

**Key Metrics:**
- **Timeline:** 23-27 weeks (includes Week -1 gem setup)
- **Team Size:** 4-6 developers (peak: 6)
- **Quality:** 100% ADR/UC coverage, professional Rails gem
- **Status:** ✅ Ready for execution

---

## 📚 Documentation Structure

### 1. Getting Started
- **[00. ICP & Timeline](./00-ICP-AND-TIMELINE.md)** - Project overview, target users, roadmap
- **[01. Scale Requirements](./01-SCALE-REQUIREMENTS.md)** - Performance targets, capacity planning
- **[Quick Start](./quick-start.md)** - 5-minute setup guide
- **[Installation](./installation.md)** - Detailed installation steps

### 2. Product Requirements (PRD)
- **[PRD-01: Overview & Vision](./prd/01-overview-vision.md)** - Problem, solution, value proposition
- **[PRD-02: Functional Requirements](./prd/02-functional-requirements.md)** - What the gem does
- **[PRD-03: User Stories](./prd/03-user-stories.md)** - By persona
- **[PRD-04: Success Metrics](./prd/04-success-metrics.md)** - How we measure success
- **[PRD-05: Competitive Analysis](./prd/05-competitive-analysis.md)** - vs OTel, Sentry, Yabeda

### 3. Technical Requirements (TRD)
- **[TRD-01: System Architecture](./trd/01-system-architecture.md)** - High-level design (C4 diagrams)
- **[TRD-02: API Design](./trd/02-api-design.md)** - Event DSL, configuration DSL
- **[TRD-03: Data Models](./trd/03-data-models.md)** - Event structure, schemas
- **[TRD-04: Performance Requirements](./trd/04-performance-requirements.md)** - Latency, throughput, memory
- **[TRD-05: Security Requirements](./trd/05-security-requirements.md)** - PII filtering, rate limiting, audit
- **[TRD-06: Integration Requirements](./trd/06-integration-requirements.md)** - OTel, Yabeda, Rails, Sidekiq

### 4. Detailed Design
- **[Design-01: Event Layer](./design/01-event-layer.md)** - Event DSL, validation, registry
- **[Design-02: Processing Layer](./design/02-processing-layer.md)** - Filtering, PII, rate limiting
- **[Design-03: Buffer Layer](./design/03-buffer-layer.md)** - Ring buffer, request-scoped buffering
- **[Design-04: Metrics Layer](./design/04-metrics-layer.md)** - Pattern-based metrics, Yabeda integration
- **[Design-05: Adapter Layer](./design/05-adapter-layer.md)** - Pluggable backends (Loki, ELK, Sentry)
- **[Design-06: Transport Layer](./design/06-transport-layer.md)** - Async workers, retry, circuit breaker
- **[Design-07: OpenTelemetry Integration](./design/07-opentelemetry-integration.md)** - OTel Collector, traces
- **[Design-08: SLO Tracking](./design/08-slo-tracking.md)** - Auto-instrumentation, error budgets

### 5. Use Cases
- **[Use Cases Index](./use_cases/README.md)** - All use cases by category
- **[UC-001: Request-Scoped Debug Buffering](./use_cases/UC-001-request-scoped-debug-buffering.md)** ⭐ Killer feature
- **[UC-002: Business Event Tracking](./use_cases/UC-002-business-event-tracking.md)** ⭐ Core feature
- **[UC-003: Event Metrics](./use_cases/UC-003-event-metrics.md)**
- **[UC-004: Zero-Config SLO Tracking](./use_cases/UC-004-zero-config-slo-tracking.md)** ⭐ Killer feature
- **[UC-005: PII Filtering](./use_cases/UC-005-pii-filtering.md)**
- **[UC-006-016: Additional Use Cases](./use_cases/README.md)**

### 6. Configuration
- **[Configuration Reference](./configuration/README.md)** - All options explained
- **[Configuration Examples](./configuration/examples.md)** - Small/Medium/Large teams
- **[Configuration Best Practices](./configuration/best-practices.md)** - Production recommendations

### 7. API Reference
- **[API Overview](./api/README.md)**
- **[Event API](./api/event-api.md)** - E11y::Event class, attributes, validation
- **[Configuration API](./api/configuration-api.md)** - E11y.configure DSL
- **[Tracking API](./api/tracking-api.md)** - .track() method, blocks
- **[Metrics API](./api/metrics-api.md)** - Pattern-based metrics DSL

### 8. Guides
- **[Migration from Rails.logger](./guides/migration-from-rails-logger.md)**
- **[Migration from Yabeda](./guides/migration-from-yabeda.md)**
- **[Integration with OpenTelemetry](./guides/opentelemetry-integration.md)**
- **[Testing Guide](./guides/testing.md)** - Unit, integration, load tests
- **[Debugging Guide](./guides/debugging.md)** - Troubleshooting
- **[Performance Tuning](./guides/performance-tuning.md)** - Optimization tips

### 9. Architecture Decision Records (ADRs)

**Complete ADRs:**
- **[ADR-001: Architecture](./ADR-001-architecture.md)** - Core architecture, components, processing pipeline
- **[ADR-002: Metrics & Yabeda](./ADR-002-metrics-yabeda.md)** - Pattern-based metrics, cardinality protection
- **[ADR-003: SLO & Observability](./ADR-003-slo-observability.md)** - HTTP/Job SLO, per-endpoint config, burn rate alerts
- **[ADR-004: Adapter Architecture](./ADR-004-adapter-architecture.md)** - Pluggable backends, retry, circuit breaker
- **[ADR-005: Tracing & Context](./ADR-005-tracing-context.md)** - W3C Trace Context, propagation
- **[ADR-006: Security & Compliance](./ADR-006-security-compliance.md)** - PII filtering, rate limiting, audit trail
- **[ADR-007: OpenTelemetry Integration](./ADR-007-opentelemetry-integration.md)** - OTLP, semantic conventions
- **[ADR-008: Rails Integration](./ADR-008-rails-integration.md)** - Railtie, Rack, Sidekiq, ActiveJob
- **[ADR-009: Cost Optimization](./ADR-009-cost-optimization.md)** - Sampling, compression, smart routing
- **[ADR-010: Developer Experience](./ADR-010-developer-experience.md)** - Console, Web UI, debug tools
- **[ADR-011: Testing Strategy](./ADR-011-testing-strategy.md)** - RSpec matchers, test adapters
- **[ADR-012: Event Evolution](./ADR-012-event-evolution.md)** - Versioning, schema changes, DLQ replay
- **[ADR-013: Reliability & Error Handling](./ADR-013-reliability-error-handling.md)** - Retry, DLQ, circuit breaker
- **[ADR-014: Event-Driven SLO](./ADR-014-event-driven-slo.md)** - Custom SLO for business logic
- **[ADR-015: Middleware Order](./ADR-015-middleware-order.md)** - Processing pipeline execution order

**Integration & Analysis:**
- **[ADR-003-014 Integration](./ADR-003-014-INTEGRATION.md)** - How HTTP SLO and Event SLO work together
- **[ADR Coverage Check](./ADR-COVERAGE-CHECK.md)** - ADR completeness matrix

### 10. Implementation Plan
- **[Phase 1: MVP Core](./implementation/phase-1-mvp.md)** - Weeks 1-8
- **[Phase 2: Yabeda Integration](./implementation/phase-2-yabeda.md)** - Weeks 9-12
- **[Phase 3: SLO Tracking](./implementation/phase-3-slo.md)** - Weeks 13-16
- **[Phase 4: OpenTelemetry](./implementation/phase-4-otel.md)** - Weeks 17-20
- **[Phase 5: Production Hardening](./implementation/phase-5-hardening.md)** - Weeks 21-24

### 11. Research & Analysis
- **[Research Findings 2025](./research/e11y-research-findings-2025.md)** - 40+ sources analyzed
- **[Cardinality Protection](./research/cardinality-protection.md)** - Critical issue deep-dive
- **[Rails PII Filtering Compatibility](./research/rails-pii-filtering.md)** - Design decision

### 12. Operations
- **[Deployment Guide](./operations/deployment.md)** - Production deployment
- **[Monitoring Guide](./operations/monitoring.md)** - Self-monitoring
- **[Alerting Guide](./operations/alerting.md)** - Prometheus alerts
- **[Runbooks](./operations/runbooks/)** - Common operational tasks

---

## 🎯 Documentation by Persona

### Ruby/Rails Developers
**Start here:**
1. [Quick Start](./quick-start.md) - Get running in 5 minutes
2. [UC-002: Business Event Tracking](./use_cases/UC-002-business-event-tracking.md) - Core functionality
3. [Migration from Rails.logger](./guides/migration-from-rails-logger.md) - Replace existing logging

**Then explore:**
- [Event API Reference](./api/event-api.md)
- [Testing Guide](./guides/testing.md)
- [Configuration Examples](./configuration/examples.md)

---

### DevOps/SRE Engineers
**Start here:**
1. [01. Scale Requirements](./01-SCALE-REQUIREMENTS.md) - Performance targets
2. [UC-004: Zero-Config SLO Tracking](./use_cases/UC-004-zero-config-slo-tracking.md) - Auto-monitoring
3. [Deployment Guide](./operations/deployment.md) - Production setup

**Then explore:**
- [Performance Requirements](./trd/04-performance-requirements.md)
- [Monitoring Guide](./operations/monitoring.md)
- [Performance Tuning](./guides/performance-tuning.md)

---

### Engineering Managers/CTOs
**Start here:**
1. [00. ICP & Timeline](./00-ICP-AND-TIMELINE.md) - Project overview, ROI
2. [PRD-01: Overview & Vision](./prd/01-overview-vision.md) - Business value
3. [PRD-05: Competitive Analysis](./prd/05-competitive-analysis.md) - vs alternatives

**Then explore:**
- [Success Metrics](./prd/04-success-metrics.md)
- [Implementation Plan](./implementation/phase-1-mvp.md)

---

### Security/Compliance Teams
**Start here:**
1. [UC-005: PII Filtering](./use_cases/UC-005-pii-filtering.md) - Rails-compatible filtering
2. [Security Requirements](./trd/05-security-requirements.md) - Threat model
3. [UC-007: Audit Trail](./use_cases/UC-007-audit-trail.md) - Compliance logging

**Then explore:**
- [Design-02: Processing Layer](./design/02-processing-layer.md) - PII, rate limiting

---

## 🔍 Finding What You Need

### By Task

**"I want to get started quickly"**
→ [Quick Start Guide](./quick-start.md)

**"I need to track business events"**
→ [UC-002: Business Event Tracking](./use_cases/UC-002-business-event-tracking.md)

**"I need to debug production issues"**
→ [UC-001: Request-Scoped Debug Buffering](./use_cases/UC-001-request-scoped-debug-buffering.md)

**"I need SLO monitoring"**
→ [SLO Implementation Guide](./SLO-IMPLEMENTATION-GUIDE.md) ⭐ or [UC-004: Zero-Config SLO](./use_cases/UC-004-zero-config-slo-tracking.md)

**"I need to filter PII"**
→ [UC-005: PII Filtering](./use_cases/UC-005-pii-filtering.md)

**"I need to migrate from Rails.logger"**
→ [Migration Guide](./guides/migration-from-rails-logger.md)

**"I need to integrate with OpenTelemetry"**
→ [OpenTelemetry Integration Guide](./guides/opentelemetry-integration.md)

**"I need to test events"**
→ [Testing Guide](./guides/testing.md)

**"I need to optimize performance"**
→ [Performance Tuning Guide](./guides/performance-tuning.md)

**"I need to deploy to production"**
→ [Deployment Guide](./operations/deployment.md)

---

### By Feature

- **Event DSL:** [Event API](./api/event-api.md), [Design-01](./design/01-event-layer.md)
- **Request-Scoped Buffering:** [UC-001](./use_cases/UC-001-request-scoped-debug-buffering.md), [Design-03](./design/03-buffer-layer.md)
- **Event Metrics:** [UC-003](./use_cases/UC-003-event-metrics.md), [Design-04](./design/04-metrics-layer.md)
- **SLO Tracking:** [UC-004](./use_cases/UC-004-zero-config-slo-tracking.md), [Design-08](./design/08-slo-tracking.md)
- **PII Filtering:** [UC-005](./use_cases/UC-005-pii-filtering.md), [Design-02](./design/02-processing-layer.md)
- **OpenTelemetry:** [Guide](./guides/opentelemetry-integration.md), [Design-07](./design/07-opentelemetry-integration.md)
- **Adapters:** [Design-05](./design/05-adapter-layer.md)

---

## 📖 Reading Order

### For First-Time Users (Linear)
1. [Quick Start](./quick-start.md) - 5 min
2. [UC-002: Business Event Tracking](./use_cases/UC-002-business-event-tracking.md) - 15 min
3. [Configuration Examples](./configuration/examples.md) - 10 min
4. [UC-001: Request-Scoped Debug Buffering](./use_cases/UC-001-request-scoped-debug-buffering.md) - 20 min
5. [UC-004: Zero-Config SLO Tracking](./use_cases/UC-004-zero-config-slo-tracking.md) - 15 min

**Total: ~1 hour to understand core features**

---

### For Production Deployment (Checklist)
- [ ] Read [Quick Start](./quick-start.md)
- [ ] Review [Scale Requirements](./01-SCALE-REQUIREMENTS.md)
- [ ] Read [Security Requirements](./trd/05-security-requirements.md)
- [ ] Configure [PII Filtering](./use_cases/UC-005-pii-filtering.md)
- [ ] Set up [Adapters](./design/05-adapter-layer.md) (Loki, Sentry)
- [ ] Enable [SLO Tracking](./use_cases/UC-004-zero-config-slo-tracking.md)
- [ ] Review [Performance Tuning](./guides/performance-tuning.md)
- [ ] Follow [Deployment Guide](./operations/deployment.md)
- [ ] Set up [Monitoring](./operations/monitoring.md) & [Alerting](./operations/alerting.md)

---

## 🤝 Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for:
- How to report bugs
- How to suggest features
- How to submit patches
- Development setup

---

## 📜 License

E11y is released under the [MIT License](../LICENSE.md).

---

## 🔗 External Resources

- **GitHub:** https://github.com/yourorg/e11y
- **RubyGems:** https://rubygems.org/gems/e11y
- **Documentation Site:** https://e11y.dev
- **Community Discord:** https://discord.gg/e11y
- **Twitter:** @e11y_gem

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Project Status:** MVP Development (Phase 1)
