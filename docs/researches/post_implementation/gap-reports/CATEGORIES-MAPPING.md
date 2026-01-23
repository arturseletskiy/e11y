# Audit to Categories Mapping

**Purpose:** Определение, какие audits попадают в какие категории gap reports

---

## Mapping Table

| Audit | Name | Primary Category | Secondary Categories | Expected Issue Types |
|-------|------|------------------|---------------------|----------------------|
| AUDIT-001 | ADR-006 Security & Compliance | Security | Documentation | Missing compliance docs, security gaps |
| AUDIT-002 | UC-007 PII Filtering | Security | DX | PII detection coverage, filtering rules |
| AUDIT-003 | UC-012 Audit Trail | Security | Reliability | Audit log completeness, tamper-proofing |
| AUDIT-027 | UC-003 PII Redaction | Security | Performance | Redaction performance, pattern coverage |
| AUDIT-004 | ADR-001 Architecture & Design | Architecture | Performance | Zero-allocation violations, design principles |
| AUDIT-005 | ADR-004 Adapter Architecture | Architecture | Reliability | Adapter interface consistency, error handling |
| AUDIT-006 | ADR-009 Buffer Architecture | Architecture | Performance | Buffer strategy coverage, memory management |
| AUDIT-007 | ADR-014 Zone Validation | Architecture | Security | Zone validation enforcement, cross-zone leaks |
| AUDIT-008 | ADR-022 Event Registry | Architecture | Documentation | Registry implementation (v1.1+ feature) |
| AUDIT-009 | UC-001 Request Scoped Buffering | Architecture | Performance | Buffer lifecycle, request isolation |
| AUDIT-026 | UC-002 Business Event Tracking | Architecture | DX | Event DSL, business event patterns |
| AUDIT-010 | ADR-013 Reliability & Error Handling | Reliability | Architecture | Error handling strategy, failure modes |
| AUDIT-011 | ADR-016 Self-Monitoring SLO | Reliability | Performance | Self-monitoring coverage, SLO tracking |
| AUDIT-012 | UC-009 Circuit Breaker | Reliability | Performance | Circuit breaker thresholds, fail-fast |
| AUDIT-013 | UC-011 Dead Letter Queue | Reliability | Architecture | DLQ storage, poison message handling |
| AUDIT-014 | UC-013 Retry Strategy | Reliability | Performance | Retry policies, exponential backoff |
| AUDIT-015 | ADR-002 Performance Targets | Performance | Testing | SLO compliance, benchmark coverage |
| AUDIT-016 | ADR-005 Sampling & Cardinality | Performance | Reliability | Sampling strategies, cardinality limits |
| AUDIT-017 | UC-014 Adaptive Sampling | Performance | Reliability | Load-based sampling, spike handling |
| AUDIT-018 | UC-015 Cardinality Protection | Performance | Reliability | Cardinality explosion prevention |
| AUDIT-019 | UC-016 Rails Logger Migration | Performance | DX | Logger bridge, backward compatibility |
| AUDIT-020 | UC-019 Metrics Integration | Performance | DX | Metrics collection, integration points |
| AUDIT-021 | ADR-003 SLO Observability | Performance | Reliability | SLO tracking, alerting |
| AUDIT-022 | ADR-015 Metrics Architecture | Performance | Architecture | Metrics design, relabeling, cardinality |
| AUDIT-023 | UC-004 Zero-Config SLO Tracking | Performance | DX | SLO automation, zero-config experience |
| AUDIT-024 | UC-006 Event-Based Alerts | Reliability | Documentation | Alert configuration, event triggers |
| AUDIT-025 | UC-021 Yabeda Integration | Performance | DX | Yabeda adapter, metrics export |
| AUDIT-028 | ADR-007 OpenTelemetry Integration | DX | Architecture | OTel integration design, trace propagation |
| AUDIT-029 | ADR-010 Developer Experience | DX | Documentation | DX philosophy, ease of use |
| AUDIT-030 | ADR-011 Testing Strategy | Testing | DX | Testing approach, test helpers |
| AUDIT-031 | UC-005 Sentry Integration | DX | Reliability | Sentry breadcrumbs, error tracking |
| AUDIT-032 | UC-008 OpenTelemetry Integration | DX | Performance | OTel implementation, trace context |
| AUDIT-033 | UC-010 Background Jobs | DX | Reliability | Sidekiq/ActiveJob instrumentation |
| AUDIT-034 | UC-016 Logger Migration | DX | Architecture | Logger bridge, migration path |
| AUDIT-035 | UC-017 Local Development | DX | Documentation | Local setup, debug tools |
| AUDIT-036 | UC-018 Testing Events | Testing | DX | Test mode, RSpec matchers |
| AUDIT-037 | UC-020 Event Versioning | DX | Architecture | Version field, backward compatibility, breaking changes |
| AUDIT-038 | UC-022 Event Registry | Documentation | Architecture | Registry API, docs generation (v1.1+ feature) |

---

## Category Priorities

**Security:**
- Focus: Security vulnerabilities, compliance gaps, PII handling
- Expected Issues: Missing encryption, insufficient PII coverage, audit trail gaps

**Architecture:**
- Focus: Design principles, component interactions, patterns
- Expected Issues: Design violations, missing abstractions, inconsistencies

**Reliability:**
- Focus: Error handling, fault tolerance, self-monitoring
- Expected Issues: Missing circuit breakers, insufficient retry logic, DLQ gaps

**Performance:**
- Focus: Performance targets, sampling, cardinality, SLO tracking
- Expected Issues: SLO violations, missing benchmarks, cardinality explosions

**DX (Developer Experience):**
- Focus: Ease of use, integrations, local development
- Expected Issues: Manual setup steps, missing helpers, poor documentation

**Testing:**
- Focus: Testing strategy, test helpers, test coverage
- Expected Issues: Missing test utilities, incomplete test coverage

**Documentation:**
- Focus: API docs, guides, migration documentation
- Expected Issues: Missing docs, outdated examples, unclear guides

