# Architecture Decision Records (ADR) Index

This document provides an index of all architectural decisions made for the E11y gem.

## 📋 Index

| ADR | Title | Status | Phase |
|-----|-------|--------|-------|
| [ADR-001](ADR-001-architecture.md) | Architecture & Design Principles | ✅ Accepted | 0 |
| [ADR-002](ADR-002-metrics-yabeda.md) | Metrics Integration (Yabeda) | ✅ Accepted | 2 |
| [ADR-003](ADR-003-slo-observability.md) | SLO Observability | ✅ Accepted | 2 |
| [ADR-004](ADR-004-adapter-architecture.md) | Adapter Architecture | ✅ Accepted | 2 |
| [ADR-005](ADR-005-tracing-context.md) | Tracing Context Propagation | ✅ Accepted | 2 |
| [ADR-006](ADR-006-security-compliance.md) | Security & Compliance (GDPR/SOC2) | ✅ Accepted | 2 |
| [ADR-007](ADR-007-opentelemetry-integration.md) | OpenTelemetry Integration | ✅ Accepted | 3 |
| [ADR-008](ADR-008-rails-integration.md) | Rails Integration Strategy | ✅ Accepted | 3 |
| [ADR-009](ADR-009-cost-optimization.md) | Cost Optimization Strategies | ✅ Accepted | 4 |
| [ADR-010](ADR-010-developer-experience.md) | Developer Experience (DX) | ✅ Accepted | 5 |
| [ADR-011](ADR-011-testing-strategy.md) | Testing Strategy | ✅ Accepted | 5 |
| [ADR-012](ADR-012-event-evolution.md) | Event Schema Evolution | ✅ Accepted | 1 |
| [ADR-013](ADR-013-reliability-error-handling.md) | Reliability & Error Handling | ✅ Accepted | 4 |
| [ADR-014](ADR-014-event-driven-slo.md) | Event-Driven SLO Tracking | ✅ Accepted | 3 |
| [ADR-015](ADR-015-middleware-order.md) | Middleware Execution Order | ✅ Accepted | 2 |
| [ADR-016](ADR-016-self-monitoring-slo.md) | Self-Monitoring SLO | ✅ Accepted | 4 |

## 🎯 Key Decisions by Topic

### Architecture & Design
- **ADR-001**: Core architecture principles, zero-allocation pattern, convention over configuration
- **ADR-012**: Event schema evolution strategy with versioning

### Performance & Scale
- **ADR-001 §5**: Performance requirements (1K/10K/100K events/sec)
- **ADR-009**: Cost optimization strategies (adaptive sampling, compression, tiered storage)

### Reliability & Operations
- **ADR-013**: Circuit breakers, retry policies, dead letter queues
- **ADR-016**: Self-monitoring SLO targets

### Integration & Adapters
- **ADR-004**: Pluggable adapter architecture
- **ADR-007**: OpenTelemetry integration for distributed tracing
- **ADR-008**: Rails integration patterns (Railtie, instrumentation)

### Observability
- **ADR-002**: Yabeda metrics integration
- **ADR-003**: SLO observability patterns
- **ADR-014**: Event-driven SLO tracking

### Security & Compliance
- **ADR-006**: GDPR/SOC2 compliance (PII filtering, audit trails, encryption)
- **ADR-005**: Trace context propagation

### Developer Experience
- **ADR-010**: Developer experience priorities (5-min setup, conventions)
- **ADR-011**: Testing strategy (RSpec, integration tests, benchmarks)
- **ADR-015**: Middleware execution order guarantees

## 📚 Decision Process

All ADRs follow this structure:

1. **Context** - The issue motivating this decision
2. **Decision** - The change that we're proposing or have agreed to
3. **Consequences** - What becomes easier or more difficult to do

## 🔄 Status Legend

- ✅ **Accepted** - Decision is final and implemented
- 🔄 **Proposed** - Under review
- ❌ **Rejected** - Decision was not accepted
- ⚠️ **Deprecated** - Superseded by a newer decision

## 📖 How to Read ADRs

### For New Contributors
Start with:
1. [ADR-001](ADR-001-architecture.md) - Core architecture principles
2. [ADR-010](ADR-010-developer-experience.md) - Developer experience goals
3. [ADR-008](ADR-008-rails-integration.md) - Rails integration patterns

### For Production Deployment
Review:
1. [ADR-013](ADR-013-reliability-error-handling.md) - Reliability patterns
2. [ADR-006](ADR-006-security-compliance.md) - Security & compliance
3. [ADR-009](ADR-009-cost-optimization.md) - Cost optimization

### For Performance Tuning
See:
1. [ADR-001 §5](ADR-001-architecture.md) - Performance requirements
2. [ADR-009](ADR-009-cost-optimization.md) - Optimization strategies
3. [docs/guides/performance-tuning.md](guides/performance-tuning.md) - Tuning guide

## 🔗 Related Documentation

- [Implementation Plan](IMPLEMENTATION_PLAN.md) - Detailed development timeline
- [Use Cases](use_cases/) - User scenarios and requirements
- [API Reference](API.md) - Public API documentation
- [Guides](guides/) - How-to guides for common tasks
