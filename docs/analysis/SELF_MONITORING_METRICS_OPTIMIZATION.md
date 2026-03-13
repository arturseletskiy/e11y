# Анализ self-monitoring метрик E11y: оптимизация

**Дата:** 2025-03-13  
**Цель:** Выявить избыточность, неиспользуемый код и возможности оптимизации метрик self-monitoring.

---

## 1. Сводка: что реально эмитится

### 1.1 Активные метрики (реально вызываются)

| Источник | Метрика | Тип | Labels | Частота вызова |
|----------|---------|-----|--------|----------------|
| **Middleware (pre-registered)** | | | | |
| TraceContext | `e11y.middleware.trace_context.processed` | counter | — | Каждый event |
| Validation | `e11y.middleware.validation.passed` | counter | — | Каждый event |
| Validation | `e11y.middleware.validation.failed` | counter | — | При ошибке валидации |
| Validation | `e11y.middleware.validation.skipped` | counter | — | При пропуске |
| Routing | `e11y.middleware.routing.write_success` | counter | adapter | **Каждая успешная запись в адаптер** |
| Routing | `e11y.middleware.routing.write_error` | counter | adapter | При ошибке адаптера |
| Routing | `e11y.middleware.routing.routed` | counter | adapters_count, routing_type | Каждый event |
| **Base Adapter** | | | | |
| PerformanceMonitor | `e11y_adapter_send_duration_seconds` | histogram | adapter | **Каждая запись в адаптер** |
| ReliabilityMonitor | `e11y_adapter_writes_total` | counter | adapter, status, error_class | **Каждая запись в адаптер** |
| **Event SLO** | `slo_event_result_total` | counter | event_name, slo_status | События с SLO |
| **SLO Tracker** | `slo_http_requests_total` | counter | controller, action, status | HTTP request (если включено) |
| **SLO Tracker** | `slo_http_request_duration_seconds` | histogram | controller, action, status | HTTP request |
| **SLO Tracker** | `slo_background_jobs_total` | counter | job_class, status, queue | Background job |
| **SLO Tracker** | `slo_background_job_duration_seconds` | histogram | job_class, status, queue | Background job |
| **Cardinality** | `e11y_cardinality_overflow_total` | counter | metric, action, strategy | Только при overflow |
| **Cardinality** | `e11y_cardinality_current` | gauge | metric | Только при overflow |

### 1.2 Критическая избыточность: дублирование на каждый adapter write

**При каждой записи в адаптер** вызываются **4 метрики**:

1. `e11y.middleware.routing.write_success` (Routing middleware)
2. `e11y_adapter_send_duration_seconds` (PerformanceMonitor из Base adapter)
3. `e11y_adapter_writes_total{status="success"}` (ReliabilityMonitor из Base adapter)
4. `e11y.middleware.routing.routed` (Routing middleware)

**Проблема:** `write_success` и `e11y_adapter_writes_total{status="success"}` — **дублируют друг друга**. Оба фиксируют успешную запись в адаптер. Аналогично `write_error` и `e11y_adapter_writes_total{status="failure"}`.

**Рекомендация:** Убрать `write_success`/`write_error` из Routing middleware — `e11y_adapter_writes_total` уже даёт эту информацию с более богатыми labels (error_class при failure).

---

## 2. Мёртвый код: определённые, но не вызываемые метрики

### 2.1 BufferMonitor — полностью не используется

| Метод | Метрика | Вызывается из |
|-------|---------|---------------|
| `track_buffer_size` | `e11y_buffer_size` | **Нигде** |
| `track_buffer_overflow` | `e11y_buffer_overflows_total` | **Нигде** |
| `track_buffer_flush` | `e11y_buffer_flushes_total`, `e11y_buffer_flush_events_count` | **Нигде** |
| `track_buffer_utilization` | `e11y_buffer_utilization_percent` | **Нигде** |

**Причина:** Ring buffer, Adaptive buffer, RequestScopedBuffer используют `increment_metric` как placeholder (закомментирован).

### 2.2 PerformanceMonitor — 3 из 4 методов не вызываются

| Метод | Метрика | Вызывается |
|-------|---------|------------|
| `track_latency` | `e11y_track_duration_seconds` | ❌ Нет |
| `track_middleware_latency` | `e11y_middleware_duration_seconds` | ❌ Нет |
| `track_adapter_latency` | `e11y_adapter_send_duration_seconds` | ✅ Base adapter |
| `track_flush_latency` | `e11y_buffer_flush_duration_seconds` | ❌ Нет |

### 2.3 ReliabilityMonitor — 6 из 8 методов не вызываются

| Метод | Метрика | Вызывается |
|-------|---------|------------|
| `track_event_success` | `e11y_events_tracked_total` | ❌ Нет |
| `track_event_failure` | `e11y_events_tracked_total` | ❌ Нет |
| `track_event_dropped` | `e11y_events_dropped_total` | ❌ Нет |
| `track_adapter_success` | `e11y_adapter_writes_total` | ✅ Base adapter |
| `track_adapter_failure` | `e11y_adapter_writes_total` | ✅ Base adapter |
| `track_dlq_save` | `e11y_dlq_saves_total` | ❌ Нет |
| `track_dlq_replay` | `e11y_dlq_replays_total` | ❌ Нет |
| `track_circuit_state` | `e11y_circuit_breaker_state` | ❌ Нет |

---

## 3. Placeholder-метрики (increment_metric закомментирован)

| Компонент | Метрики | Файл |
|-----------|---------|------|
| RequestScopedBuffer | 5 (flushed_on_error, discarded, events_buffered, overflow, event_flushed) | `buffers/request_scoped_buffer.rb` |
| RingBuffer | 2 (overflow.drop_newest, overflow.block_timeout) | `buffers/ring_buffer.rb` |
| AdaptiveBuffer | 3 (memory_exhaustion.dropped, blocked) | `buffers/adaptive_buffer.rb` |
| CircuitBreaker | 9 (rejected, success, failure, half_open_*, opened, closed) | `reliability/circuit_breaker.rb` |
| RetryHandler | 5+ (success, recovered, failed, backoff_delay) | `reliability/retry_handler.rb` |
| RetryRateLimiter | 4 (allowed, exceeded, delayed, dlq) | `reliability/retry_rate_limiter.rb` |
| DLQ FileStorage | 8 (saved, parse_error, replay, rotated, cleaned_up) | `reliability/dlq/file_storage.rb` |
| DLQ Filter | 5 (discarded, saved по reason) | `reliability/dlq/filter.rb` |

**Итого:** ~40 метрик с placeholder-вызовами, не эмитятся.

---

## 4. Несоответствие Prometheus alerts

В `e11y_alerts.yml` используются метрики, которых **нет в коде**:

| Alert | Ожидаемая метрика | Реальность |
|-------|-------------------|------------|
| E11yHighErrorRate | `e11y_events_total{severity="error"}` | ❌ Не существует |
| E11yRateLimitDrops | `e11y_rate_limit_dropped_total` | ❌ Не существует |
| E11yCircuitBreakerOpen | `e11y_circuit_breaker_open_total` | ❌ Есть gauge `e11y_circuit_breaker_state`, но не вызывается |
| E11yDLQGrowing | `e11y_dlq_size` | ❌ Не существует |
| E11yAdapterUnhealthy | `e11y_adapter_healthy` | ❌ Не существует |

**Алерты не будут работать** — метрики не эмитятся.

---

## 5. Рекомендации по оптимизации

### 5.1 Приоритет 1: Убрать дублирование (низкий риск)

**Действие:** Удалить `write_success` и `write_error` из Routing middleware.

**Обоснование:** `e11y_adapter_writes_total` уже даёт success/failure с labels `adapter`, `status`, `error_class`. Дублирование увеличивает overhead.

**Эффект:** −2 метрики на каждый adapter write; меньше cardinality в Yabeda.

### 5.2 Приоритет 2: Очистить мёртвый код (средний риск)

**Вариант A — Удалить неиспользуемые методы:**
- `BufferMonitor` — удалить весь модуль или оставить как API для будущего использования
- `PerformanceMonitor.track_latency`, `track_middleware_latency`, `track_flush_latency` — удалить
- `ReliabilityMonitor` — удалить `track_event_*`, `track_dlq_*`, `track_circuit_state`

**Вариант B — Оставить как API, документировать:**
- Добавить в README: «Эти методы не вызываются автоматически; вызывайте вручную при необходимости».

**Рекомендация:** Вариант A — меньше кода, меньше путаницы. Если понадобится — добавить позже.

### 5.3 Приоритет 3: Исправить Prometheus alerts

**Действие:** Переписать `e11y_alerts.yml` под реальные метрики:

```yaml
# Вместо e11y_events_total — использовать:
# rate(e11y_middleware_routing_write_error[5m]) / rate(e11y_middleware_routing_write_success[5m]) + rate(e11y_middleware_routing_write_error[5m])

# Circuit breaker — пока не реализован, закомментировать alert

# DLQ — пока не реализован, закомментировать alert

# Adapter health — использовать e11y_adapter_writes_total (есть success/failure)
```

### 5.4 Приоритет 4: Sampling для self-monitoring (опционально)

По AUDIT-011: «PerformanceMonitor/ReliabilityMonitor всегда вызываются» — нет sampling.

**Рекомендация:** Добавить sampling для `e11y_adapter_send_duration_seconds` (например, 1% при высокой нагрузке) — снизит overhead при пиках.

---

## 6. Итоговая картина

| Категория | Количество | Действие |
|-----------|------------|----------|
| Активные метрики | ~15 | Оставить, убрать дублирование |
| Дублирующие | 2 | Удалить write_success/write_error |
| Мёртвый код (методы) | ~13 | Удалить или документировать |
| Placeholder | ~40 | Реализовать позже или удалить вызовы |
| Alerts нерабочие | 5 | Переписать под реальные метрики |

**Ожидаемый эффект:** −2 метрики на каждый adapter write; меньше кода; рабочие алерты.
