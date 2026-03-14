# Финальный отчёт: ADR Implementation vs Planning

**Дата:** 2026-03-13  
**Источник:** Консолидация находок из 15 отчётов ADR-XXX-IMPLEMENTATION-REPORT.md (удалены после консолидации)  
**Охват:** Критические, высокие и средние находки (Critical, High, Medium)

---

## Сводка по severity

| Severity | Количество |
|----------|------------|
| **Critical** | 7 |
| **High** | 22 |
| **Medium** | 45 |
| **Всего** | 74 |

---

## 1. Критические находки (Critical)

### ADR-001: Architecture

| ID | Описание |
|----|----------|
| F-010 | **Middleware order:** ADR требует Versioning последним перед Routing; в коде Versioning стоит вторым (до Validation). Может влиять на schema validation, PII rules, rate limits. |
| F-011 | **Middleware order:** ADR: RateLimit #4, Sampling #5. В коде: Sampling перед RateLimiting. Порядок обратный. |

### ADR-006: Security & Compliance

| ID | Описание |
|----|----------|
| F-001 | **Audit events signed after PII filtering:** Audit events должны подписываться **оригинальными** данными (до PII filtering) для non-repudiation (GDPR Art. 30). В коде PIIFilter идёт перед AuditSigning — подпись на отфильтрованных данных. |

### ADR-013: Reliability & Error Handling

| ID | Описание |
|----|----------|
| F3 | **Adapter DLQ not wired:** `@dlq_filter` и `@dlq_storage` в Base adapter остаются `nil` — нигде не инициализируются из `E11y.config`. В результате `save_to_dlq_if_needed` всегда возвращает early, DLQ не работает. |

### ADR-015: Middleware Order

| ID | Описание |
|----|----------|
| F-001 | **Versioning position:** Versioning должен быть последним перед Routing; в коде Versioning второй. Validation, PII, RateLimiting, Sampling могут использовать нормализованные имена вместо оригинальных class names. |

---

## 2. Высокие находки (High)

### ADR-005: Tracing Context

| ID | Описание |
|----|----------|
| F-023 | Trace-consistent sampling (§7) не реализован. |

### ADR-006: Security & Compliance

| ID | Описание |
|----|----------|
| F-003 | **BaggageProtection middleware missing (§5.5, C08):** Middleware для блокировки PII в OpenTelemetry Baggage не реализован. |
| F-004 | **No PII skip for DLQ replayed events (§5.6, C07):** PIIFilter не проверяет `metadata[:replayed]`; replay не устанавливает `:replayed`. Double-hashing при replay. |

### ADR-007: OpenTelemetry Integration

| ID | Описание |
|----|----------|
| F1 | **OpenTelemetryCollector adapter missing:** ADR §3 описывает OTLP HTTP adapter. В коде только OTelLogs (SDK). |
| F2 | **Span creation not implemented:** ADR §6 — SpanCreator, автоматическое создание spans из events. Не реализовано. |
| F3 | **Trace context not integrated with OTel SDK:** ADR §8 — OpenTelemetrySource для чтения trace_id из OTel SDK. Нет `source :opentelemetry`. |

### ADR-010: Developer Experience

| ID | Описание |
|----|----------|
| F-001 | No dev vs prod configuration: Railtie не имеет `e11y.setup_development`; dev_log adapter не регистрируется. |
| F-005 | **DevLog adapter missing:** ADR §4.0 — file-based JSONL adapter (all_events, find_event, search, clear!, stats). Не реализован. |
| F-006 | **Web UI missing:** ADR §4.1–4.5 — WebUI Engine, EventsController, mount at /e11y. Не реализовано. |
| F-007 | **Event Explorer, Timeline, Inspector, Trace Viewer** не реализованы. |
| F-011 | **PipelineInspector not implemented:** ADR §6.1 — E11y::Debug::PipelineInspector.trace_event. Нет Debug module. |

### ADR-011: Testing Strategy

| ID | Описание |
|----|----------|
| F-002 | **RSpec matchers not implemented:** `have_tracked_event`, `track_event`, etc. Нет `lib/e11y/testing/rspec_matchers.rb`. |
| F-004 | **No spec/support/e11y.rb, no E11y.test_adapter.** Test setup разбросан по spec_helper и dummy config. |
| F-006 | **Snapshot testing not implemented:** `match_snapshot`, `spec/snapshots/` отсутствуют. |

### ADR-014: Event-Driven SLO

| ID | Описание |
|----|----------|
| F-008 | **slo.yml custom_slos not implemented:** ADR §5 — config/slo.yml с custom_slos. Не реализовано. |
| F-011 | **Three SLO linters not implemented:** ADR §7 — ExplicitDeclaration, SloStatusFrom, ConfigConsistency. Не реализованы. |

### ADR-016: Self-Monitoring SLO

| ID | Описание |
|----|----------|
| F1 | **e11y_events_tracked_total not implemented:** UCs и ADR ссылаются; SLO reliability зависит от success/total. |
| F2 | **e11y_dlq_size not implemented:** UC-021, ADR-013, Grafana dashboard ссылаются. Gauge не зарегистрирован. |
| F3 | **SLO targets not implemented:** ADR §4 — config/e11y_slo.yml, SLOCalculator, latency/reliability/resource SLO. Отсутствуют. |

---

## 3. Средние находки (Medium)

### ADR-001: Architecture (Medium)

| ID | Описание |
|----|----------|
| F-007 | **Request buffer:** ADR §3.4 показывает `Current.request_buffer`; код использует `EphemeralBuffer` + `Thread.current`. |

### ADR-005: Tracing Context

| ID | Описание |
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

| ID | Описание |
|----|----------|
| F-005 | **PII Declaration Linter not implemented:** E11y::Linters::PiiDeclarationLinter, rake e11y:lint:pii. |
| F-007 | **Per-adapter PII vs global middleware:** ADR §3.0.6 — PII per adapter; в коде PIIFilter — глобальный middleware. |

### ADR-007: OpenTelemetry Integration

| ID | Описание |
|----|----------|
| F4 | **Semantic conventions not implemented:** ADR §4 — E11y::OpenTelemetry::SemanticConventions. OTelLogs использует generic event.#{key}. |
| F5 | **Resource attributes partial:** Только service.name; ADR §7 требует полный набор. |

### ADR-008: Rails Integration

| ID | Описание |
|----|----------|
| 1 | No `instruments` namespace; flat config (`rails_instrumentation`, `sidekiq`, `active_job`, `logger_bridge`). |
| 2 | ~~Sidekiq middleware не эмитит Events::Rails::Job::*~~ **RESOLVED:** Sidekiq эмитит Enqueued/Started/Completed/Failed для raw jobs; ActiveJob-wrapped пропускается (ASN). |
| 3 | ~~ActiveJob callbacks не эмитят Events::Rails::Job::*~~ **By design:** События идут через RailsInstrumentation (ASN); callbacks — trace/buffer/SLO. ADR обновлён. |
| 4 | Trace propagation: C17 hybrid (`e11y_parent_trace_id`) vs ADR same-trace (`e11y_trace_id`). |
| 5 | ~~Single buffer~~ **By design:** Один EphemeralBuffer для HTTP и jobs. `config.buffer.job_buffer_limit` для jobs. ADR обновлён. |
| 6 | Logger Bridge: нет dual_logging config; dual logging всегда on. |
| 7 | Logger Bridge: нет track_severities, ignore_patterns, sample_rate, enrich_with_context. |
| 8 | 3-phase migration не конфигурируема; нельзя отключить mirroring. |

### ADR-009: Cost Optimization

| ID | Описание |
|----|----------|
| F1 | **Stratified Sampling (C11) not integrated —** StratifiedTracker существует, но не используется sampling middleware или SLO Tracker. |
| F2 | **Cardinality protection not unified for OTLP —** нет CardinalityFilter middleware; OTel использует max_attributes truncation. |
| F3 | **Loki cardinality opt-in** — по умолчанию false; ADR §8 требует по умолчанию. |
| F4 | **Compression not implemented** — pipeline-level compression не начата. |

### ADR-010: Developer Experience

| ID | Описание |
|----|----------|
| F-002 | 5-min setup claim не достижим: нет единого config block. |
| F-003 | Console vs Stdout naming: ADR — Console, код — Stdout. |
| F-004 | Console output format: ADR §3 — rich format; Stdout — JSON.pretty_generate only. |
| F-012 | No pipeline trace debugging. |
| F-013 | Rake tasks missing: e11y:list, e11y:validate, e11y:docs:generate, e11y:stats. |
| F-014 | Documentation generator not implemented. |

### ADR-011: Testing Strategy

| ID | Описание |
|----|----------|
| F-005 | No FactoryBot event factories. |

### ADR-012: Event Evolution

| ID | Описание |
|----|----------|
| F-* | UC-020 использует event_version vs ADR v:; UC-020 показывает OrderPaidV1 vs ADR no-suffix для V1. |
| F-* | Event Registry: нет VersionExtractor, all_versions, version_usage, versioned_events; другой register API. |
| F-* | DLQ/C15: нет skip_validation config; replay не устанавливает metadata[:replayed]. |

### ADR-013: Reliability

| ID | Описание |
|----|----------|
| F1 | UC-021 says Circuit Breaker "in UC-011" — UC-011 не упоминает Circuit Breaker. |
| F2 | DLQ::Filter не экспортирует always_save_patterns; rate limiter ожидает этот метод. |

### ADR-014: Event-Driven SLO

| ID | Описание |
|----|----------|
| F-001 | UC-004 не описывает event-level SLO; нет UC для slo { enabled true }. |
| F-005 | Dummy app pipeline исключает EventSlo; integration tests могут не проходить EventSlo. |
| F-006 | OrderCreated: duplicate slo blocks, missing contributes_to. |
| F-012 | App-wide SLO aggregation (ADR §9) не реализована. |

### ADR-016: Self-Monitoring SLO

| ID | Описание |
|----|----------|
| F4 | **BufferMonitor not wired** — API есть, ring/adaptive buffers не вызывают. |
| F5 | **PerformanceMonitor partial** — только track_adapter_latency; ADR §3.1 требует track_latency, track_middleware_latency, track_flush_latency. |
| F6 | **ResourceMonitor not implemented** — ADR §3.3: memory, GC, CPU metrics отсутствуют. |
| F7 | ~~HealthCheck~~ **ADR обновлён:** E11y.health и E11y.healthy? вместо HealthCheck class; без endpoint (гем встраивается в процесс). |
| F8 | **Metric name mismatch** — BufferMonitor uses `e11y_buffer_overflows_total`; Yabeda — `e11y_buffer_overflow_total`. BufferMonitor не wired. |

---

## 4. Дополнительные ADR (Low/Info, gaps)

### ADR-002: Metrics (Yabeda)

| ID | Описание |
|----|----------|
| F1 | **Four-Layer vs Three-Layer inconsistency** — §4.1 header says "Three-Layer"; §4.2–4.5 и ToC — four layers. |
| F2 | **Layer 2 (Safe Allowlist) not implemented** — ADR §4.3 defines SAFE_LABELS; CardinalityProtection не имеет allowlist. |

### ADR-003: SLO Observability

| ID | Описание |
|----|----------|
| F3 | **slo.yml не реализован** — ADR §4. Per-endpoint SLO только через DSL. |
| F4 | **Multi-window burn rate alerts** — ADR §5. Нет BurnRateCalculator, alert generation. |
| F5 | **ConfigValidator** — ADR §6. Нет rake e11y:slo:validate. |
| F6 | **ErrorBudget** — ADR §7. Не реализован. |
| F7 | **Grafana dashboard generator** — ADR §8.1. Не реализован. |

### ADR-004: Adapter Architecture

| ID | Описание |
|----|----------|
| F1 | **Registry vs config.adapters** — ADR §5 описывает Registry; routing использует `config.adapters` (Hash). Два механизма. |
| F2 | **Registry validation** — требует `healthy?`; ADR только write/write_batch. |

*Реализовано:* Base contract, Stdout, File, Loki, Sentry, InMemory, Retention-Based Routing. Elasticsearch отменён.

### ADR-017: Multi-Rails Compatibility

| ID | Описание |
|----|----------|
| F-001 | **ADR-001 vs ADR-017 conflict** — ADR-001: Rails 8.0+ exclusive. ADR-017 добавляет 7.0, 7.1. Implementation следует ADR-017. |
| F-003 | **Version-specific code** — ADR пример exception handling с `Rails.version` не найден; dummy app использует show_exceptions=false. |

### ADR-018: Memory Optimization

**Статус:** В основном реализован. Event::Base — hash-based, class methods only. Ring buffer, Adaptive buffer — aligned. Backpressure: drop_oldest, drop_newest, block.

---

## 5. Рекомендации по приоритетам

### Немедленно (Critical)

1. **ADR-013 F3:** Подключить `@dlq_filter` и `@dlq_storage` из `E11y.config` в Base adapter.
2. **ADR-001/015:** Согласовать и исправить middleware order (Versioning last, RateLimit before Sampling).

### Высокий приоритет (High)

1. **ADR-006:** BaggageProtection middleware (C08); PII skip для DLQ replayed (C07).
2. **ADR-016:** e11y_events_tracked_total, e11y_dlq_size, SLO targets.
3. **ADR-010:** Dev vs prod config, DevLog adapter, Web UI (или пересмотреть scope в ADR).
4. **ADR-011:** RSpec matchers, spec/support/e11y.rb, snapshot testing.
5. **ADR-007:** OpenTelemetryCollector adapter, span creation, trace context integration.

### Средний приоритет (Medium)

1. **ADR-002:** Layer 2 (Safe Allowlist) или обновить ADR.
2. **ADR-005:** sampled, baggage, trace-consistent sampling.
3. **ADR-008:** Logger Bridge config, job buffer config, 3-phase migration.
4. **ADR-009:** Stratified sampling integration, OTLP cardinality, Loki default.
5. **ADR-010:** Registry API, Console helpers, Rake tasks.
6. **ADR-014:** slo.yml custom_slos, SLO linters.

---

## 6. Примечание

**Устные договорённости:** Часть несоответствий может быть результатом устно согласованных решений. Перед внесением изменений рекомендуется уточнить у команды.

---

**Status:** Complete  
**Source reports (consolidated):** ADR-001, 002, 003, 004, 005, 006, 007, 008, 009, 010, 011, 012, 013, 014, 016, 017, 018
