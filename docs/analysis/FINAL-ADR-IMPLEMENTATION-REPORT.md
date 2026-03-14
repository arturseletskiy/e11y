# Final Report: ADR Implementation vs Planning

**Date:** 2026-03-13  
**Source:** Consolidated findings from 15 ADR-XXX-IMPLEMENTATION-REPORT.md files (removed after consolidation)  
**Scope:** Critical, High, and Medium findings

---

## Severity Summary

| Severity | Count |
|----------|------------|
| **Critical** | 7 |
| **High** | 22 |
| **Medium** | 45 |
| **Total** | 74 |

---

## 1. Critical Findings

---

## 2. High Findings

### ADR-005: Tracing Context

| ID | Description |
|----|-------------|
| F-023 | Trace-consistent sampling (§7) not implemented. |

### ADR-006: Security & Compliance

| ID | Description |
|----|-------------|
| F-003 | **BaggageProtection middleware missing (§5.5, C08):** Middleware to block PII in OpenTelemetry Baggage not implemented. |

### ADR-007: OpenTelemetry Integration

| ID | Description |
|----|-------------|
| F1 | **OpenTelemetryCollector adapter missing:** ADR §3 describes OTLP HTTP adapter. In code only OTelLogs (SDK). |
| F2 | **Span creation not implemented:** ADR §6 — SpanCreator, automatic span creation from events. Not implemented. |
| F3 | **Trace context not integrated with OTel SDK:** ADR §8 — OpenTelemetrySource for reading trace_id from OTel SDK. No `source :opentelemetry`. |

### ADR-010: Developer Experience

| ID | Description |
|----|-------------|
| F-001 | No dev vs prod configuration: Railtie has no `e11y.setup_development`; dev_log adapter not registered. |
| F-005 | **DevLog adapter missing:** ADR §4.0 — file-based JSONL adapter (stored_events, find_event, search, clear!, stats). Not implemented. |
| F-006 | **Web UI missing:** ADR §4.1–4.5 — WebUI Engine, EventsController, mount at /e11y. Not implemented. |
| F-007 | **Event Explorer, Timeline, Inspector, Trace Viewer** not implemented. |
| F-011 | **PipelineInspector not implemented:** ADR §6.1 — E11y::Debug::PipelineInspector.trace_event. No Debug module. |

### ADR-014: Event-Driven SLO

| ID | Description |
|----|-------------|
| F-008 | **slo.yml custom_slos not implemented:** ADR §5 — config/slo.yml with custom_slos. Not implemented. |
| F-011 | **Three SLO linters not implemented:** ADR §7 — ExplicitDeclaration, SloStatusFrom, ConfigConsistency. Not implemented. |

### ADR-016: Self-Monitoring SLO

| ID | Description |
|----|-------------|
| F1 | **e11y_events_tracked_total not implemented:** UCs and ADR reference it; SLO reliability depends on success/total. |
| F3 | **SLO targets not implemented:** ADR §4 — config/e11y_slo.yml, SLOCalculator, latency/reliability/resource SLO. Missing. |

---

## 3. Medium Findings

### ADR-005: Tracing Context

| ID | Description |
|----|----------|
| F-002 | UC-006 §2.0 shows "same trace_id preserved" in jobs; contradicts ADR §8.3 C17 hybrid model. |
| F-008 | E11y::Current has no `sampled` attribute. |
| F-009 | E11y::Current has no `baggage`. |
| F-014 | tracestate for baggage on outgoing; not implemented. |
| F-016 | Propagator uses fixed "01" for sampled; ignores E11y::Current.sampled. |
| F-017 | e11y_sampled in job metadata; Sidekiq middleware does not propagate. |
| F-024 | Sampler class not present. |
| F-025 | Sampled not propagated in HTTP or jobs. |

### ADR-006: Security & Compliance

| ID | Description |
|----|-------------|
| F-005 | **PII Declaration Linter not implemented:** E11y::Linters::PiiDeclarationLinter, rake e11y:lint:pii. |
| F-007 | **Per-adapter PII vs global middleware:** ADR §3.0.6 — PII per adapter; in code PIIFilter is global middleware. |

### ADR-007: OpenTelemetry Integration

| ID | Description |
|----|-------------|
| F4 | **Semantic conventions not implemented:** ADR §4 — E11y::OpenTelemetry::SemanticConventions. OTelLogs uses generic event.#{key}. |
| F5 | **Resource attributes partial:** Only service.name; ADR §7 requires full set. |

### ADR-008: Rails Integration

| ID | Description |
|----|-------------|
| 1 | No `instruments` namespace; flat config (`rails_instrumentation`, `sidekiq`, `active_job`, `logger_bridge`). |
| 4 | Trace propagation: C17 hybrid (`e11y_parent_trace_id`) vs ADR same-trace (`e11y_trace_id`). |
| 6 | Logger Bridge: no dual_logging config; dual logging always on. |
| 7 | Logger Bridge: no track_severities, ignore_patterns, sample_rate, enrich_with_context. |
| 8 | 3-phase migration not configurable; cannot disable mirroring. |

### ADR-009: Cost Optimization

| ID | Description |
|----|-------------|
| F1 | **Stratified Sampling (C11) not integrated —** StratifiedTracker exists but not used by sampling middleware or SLO Tracker. |
| F2 | **Cardinality protection not unified for OTLP —** no CardinalityFilter middleware; OTel uses max_attributes truncation. |
| F3 | **Loki cardinality opt-in** — defaults to false; ADR §8 requires default. |
| F4 | **Compression not implemented** — pipeline-level compression not started. |

### ADR-010: Developer Experience

| ID | Description |
|----|-------------|
| F-002 | 5-min setup claim not achievable: no single config block. |
| F-012 | No pipeline trace debugging. |
| F-013 | Rake tasks missing: e11y:list, e11y:validate, e11y:docs:generate, e11y:stats. |
| F-014 | Documentation generator not implemented. |

### ADR-012: Event Evolution

| ID | Description |
|----|-------------|
| F-* | UC-020 uses event_version vs ADR v:; UC-020 shows OrderPaidV1 vs ADR no-suffix for V1. |
| F-* | Event Registry: no VersionExtractor, all_versions, version_usage, versioned_events; different register API. |
| F-* | DLQ/C15: no skip_validation config; replay does not set metadata[:dlq_replayed]. |

### ADR-013: Reliability

| ID | Description |
|----|-------------|
| F1 | UC-021 says Circuit Breaker "in UC-011" — UC-011 does not mention Circuit Breaker. |

### ADR-014: Event-Driven SLO

| ID | Description |
|----|-------------|
| F-001 | UC-004 does not describe event-level SLO; no UC for slo { enabled true }. |
| F-005 | Dummy app pipeline excludes EventSlo; integration tests may not pass EventSlo. |
| F-006 | OrderCreated: duplicate slo blocks, missing contributes_to. |
| F-012 | App-wide SLO aggregation (ADR §9) not implemented. |

### ADR-016: Self-Monitoring SLO

| ID | Description |
|----|-------------|
| F4 | **BufferMonitor not wired** — API exists, ring/adaptive buffers do not call it. |
| F5 | **PerformanceMonitor partial** — only track_adapter_latency; ADR §3.1 requires track_latency, track_middleware_latency, track_flush_latency. |
| F6 | **ResourceMonitor not implemented** — ADR §3.3: memory, GC, CPU metrics missing. |
| F8 | **Metric name mismatch** — BufferMonitor uses `e11y_buffer_overflows_total`; Yabeda — `e11y_buffer_overflow_total`. BufferMonitor not wired. |

---

## 4. Additional ADRs (Low/Info, gaps)

### ADR-002: Metrics (Yabeda)

| ID | Description |
|----|-------------|
| F1 | **Four-Layer vs Three-Layer inconsistency** — §4.1 header says "Three-Layer"; §4.2–4.5 and ToC — four layers. |
| F2 | **Layer 2 (Safe Allowlist) not implemented** — ADR §4.3 defines SAFE_LABELS; CardinalityProtection has no allowlist. |

### ADR-003: SLO Observability

| ID | Description |
|----|-------------|
| F3 | **slo.yml not implemented** — ADR §4. Per-endpoint SLO only via DSL. |
| F4 | **Multi-window burn rate alerts** — ADR §5. No BurnRateCalculator, alert generation. |
| F5 | **ConfigValidator** — ADR §6. No rake e11y:slo:validate. |
| F6 | **ErrorBudget** — ADR §7. Not implemented. |
| F7 | **Grafana dashboard generator** — ADR §8.1. Not implemented. |

### ADR-004: Adapter Architecture

| ID | Description |
|----|-------------|
| F1 | **Registry vs config.adapters** — ADR §5 describes Registry; routing uses `config.adapters` (Hash). Two mechanisms. |
| F2 | **Registry validation** — requires `healthy?`; ADR only write/write_batch. |

*Implemented:* Base contract, Stdout, File, Loki, Sentry, InMemory, Retention-Based Routing. Elasticsearch cancelled.

### ADR-017: Multi-Rails Compatibility

| ID | Description |
|----|-------------|
| F-001 | **ADR-001 vs ADR-017 conflict** — ADR-001: Rails 8.0+ exclusive. ADR-017 adds 7.0, 7.1. Implementation follows ADR-017. |
| F-003 | **Version-specific code** — ADR example exception handling with `Rails.version` not found; dummy app uses show_exceptions=false. |

### ADR-018: Memory Optimization

**Status:** Mostly implemented. Event::Base — hash-based, class methods only. Ring buffer, Adaptive buffer — aligned. Backpressure: drop_oldest, drop_newest, block.

