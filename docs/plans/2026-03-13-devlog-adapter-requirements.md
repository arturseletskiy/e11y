# DevLog Adapter Requirements & Best Practices

**Date:** 2026-03-13  
**Status:** Draft  
**Source:** ADR-010 §4.0, FINAL-ADR-IMPLEMENTATION-REPORT (F-001, F-005), Web research

---

## 1. Executive Summary

DevLog — file-based JSONL adapter для **development/test** только. Хранит события и предоставляет read API для Web UI, консоли и CLI. Не используется в production.

---

## 2. Best Practices (по исследованию)

### 2.1. JSONL для логов

| Источник | Рекомендация |
|----------|--------------|
| NDJSON.com, Uptrace | JSONL — стандарт для structured logging (CloudWatch, Elasticsearch, Fluentd, Datadog, Splunk) |
| Structured Logging | Structured key-value pairs для поиска, фильтрации, анализа |
| Docker | JSONL driver с rotation по размеру |

**Вывод:** JSONL — правильный формат. Один JSON объект на строку.

### 2.2. Контекст и метаданные

| Источник | Рекомендация |
|----------|--------------|
| NDJSON.com | Request IDs, user IDs, timestamps, error stacks, performance metrics |
| Rails 8.1 Rails.event | event name, payload, tags, context, nanosecond timestamp, source location |
| Structured Logging | Uniform key-value formatting across app |

**Вывод:** DevLog должен хранить: event_name, severity, timestamp, payload, trace_id, span_id, metadata (request_id, user_id и т.д.).

### 2.3. Rotation и retention

| Источник | Рекомендация |
|----------|--------------|
| Docker | File size limits (e.g. 10MB) |
| Winston/Node | Log rotation, retention policies |
| ADR-010 | max_lines: 10_000, max_size: 10.megabytes |

**Вывод:** Auto-rotation по размеру и/или количеству строк. Не хранить бесконечно.

### 2.4. Dev-only инструменты

| Инструмент | Паттерн |
|------------|---------|
| **Sentry Spotlight** | Local dev capture; real-time errors, traces, logs; config через env check |
| **Serilog UI** | Log viewer UI; mount at /serilog-ui; auth для production |
| **Serilog UI sinks** | SQLite, PostgreSQL, Elasticsearch — читают из хранилища |
| **AI Observer** | WebSocket dashboard, DuckDB analytics, local-only |

**Вывод:** DevLog + Web UI — только в development/test. Никогда не регистрировать в production.

### 2.5. CLI workflow

| Источник | Паттерн |
|----------|---------|
| tail-jsonl | Streaming JSONL, unwrap exceptions, jq-friendly |
| toolong | Live tail, syntax highlighting, JSONL pretty-print |
| Stack Overflow | `tail -f logfile \| jq .` |

**Вывод:** DevLog должен писать в append-only JSONL, чтобы `tail -f log/e11y_dev.jsonl | jq` работал.

### 2.6. Multi-process safety

| Источник | Рекомендация |
|----------|--------------|
| ADR-010 | Append-only writes; File::LOCK_EX при записи |
| JSONL | Line-based = atomic append per line |

**Вывод:** Mutex + flock(LOCK_EX) при append. Один процесс пишет — не блокировать чтение.

---

## 3. Popular Use Cases: Backend vs Frontend/SPA

### 3.1. Pure Backend Development

| Use Case | Описание | Что нужно в DevLog |
|----------|----------|-------------------|
| **Trace request flow** | "Какой путь прошёл запрос?" — controller → service → DB → external API | `events_by_trace(trace_id)` — все события одного запроса |
| **Debug failed API** | "Почему 500?" — смотреть логи вокруг ошибки | `find_event(id)`, `search("error")`, `events_by_severity(:error)` |
| **Audit API calls** | "Кто что вызвал?" — request_id, user_id, endpoint | payload с request_id, user_id, path, method |
| **Slow request** | "Где тормозит?" — DB query, external API, N+1 | trace_id + latency в payload, waterfall по span_id |
| **Background job** | "Почему job упал?" — Sidekiq/ActiveJob events | events_by_name("job.failed"), payload с job_class, error |
| **External API** | "Что вернул Stripe/Legacy API?" — request/response | event с payload: url, status, duration, response_summary |
| **Auth events** | "Почему login failed?" — OAuth, session | events_by_name("auth.*"), search("login") |
| **Payment flow** | "Где сломался checkout?" — order_id, payment_ref | search(order_id), events_by_trace |

**Ключевые поля:** trace_id, span_id, request_id, event_name, severity, payload (user_id, order_id, path, duration, error).

**Workflow:** `tail -f log/e11y_dev.jsonl | jq 'select(.trace_id == "abc")'` или Web UI filter by trace_id.

### 3.2. Frontend / SPA (много AJAX)

| Use Case | Описание | Что нужно в DevLog |
|----------|----------|-------------------|
| **Which request failed?** | SPA: 10 AJAX на странице, один 4xx/5xx — какой именно? | trace_id в X-Request-ID / traceparent → backend логирует с этим trace_id |
| **Frontend–backend correlation** | "Кнопка нажата → 3 API вызова → один медленный" | W3C Trace Context: frontend генерирует trace_id, backend создаёт child spans |
| **Waterfall view** | "Где время: network, TTFB, download?" | Backend: span с duration. Frontend: отдельный trace (или объединённый) |
| **CORS / 4xx debug** | "Почему preflight failed?" | Backend логирует все requests (включая OPTIONS) с headers |
| **Replay request** | "Воспроизвести тот же запрос" | payload с method, path, headers, body (PII masked) |
| **Batch of requests** | "Загрузка страницы = 15 fetch" — какой упал? | Один trace_id на "page load", все 15 API — child spans |
| **React/Vue state vs API** | "Компонент показывает stale data — API вернул новое?" | События с response body summary (без PII) |

**Ключевая проблема:** Frontend и backend — разные миры. Без trace_id propagation видишь два лога: "API 450ms" и "Page 3.2s" — непонятно, где 2.7s.

**Решение:** Backend (E11y) извлекает `traceparent` из request headers, добавляет trace_id/span_id в каждое событие. DevLog хранит. Web UI / CLI: filter by trace_id = видишь весь путь запроса.

**Что DevLog даёт для SPA:**
- Backend events с trace_id — можно искать по trace_id из браузерного Network tab (если X-Request-ID = trace_id)
- `events_by_trace(trace_id)` — все backend события для одного frontend-initiated request
- Документировать: "Добавь X-Request-ID в fetch/axios — получишь correlation"

### 3.3. Сводка: Must-Have для Use Cases

| Use Case Category | DevLog feature | Приоритет |
|-------------------|----------------|-----------|
| Backend: trace flow | events_by_trace(trace_id) | P0 |
| Backend: debug error | find_event, search, events_by_severity | P0 |
| Backend: slow request | trace_id + duration в payload (от middleware) | P0 |
| SPA: correlation | trace_id из headers, events_by_trace | P1 |
| SPA: which request | X-Request-ID = trace_id в response | P1 |
| Both: replay | payload с request details (masked) | P2 |

---

## 4. Требования к DevLog Adapter

### 4.1. Обязательные (Must Have)

| ID | Требование | Описание |
|----|------------|----------|
| D1 | **Write API** | `write(event_data)` и `write_batch(events)` — стандартный Base adapter contract |
| D2 | **JSONL format** | Один JSON объект на строку. Append-only. |
| D3 | **Event schema** | Хранить: id, timestamp, event_name, severity, payload, trace_id, span_id, metadata |
| D4 | **stored_events(limit:)** | Возврат последних N событий (newest-first). Для Web UI. |
| D5 | **find_event(id)** | Поиск по event id. |
| D6 | **search(query)** | Поиск по подстроке в payload/event_name. |
| D7 | **clear!** | Очистка файла. Для Web UI "Clear" и тестов. |
| D8 | **stats** | Агрегаты: total_events, by_severity, by_event_name, file_size, oldest/newest |
| D9 | **Auto-rotation** | По max_size и/или max_lines. Не расти бесконечно. |
| D10 | **Thread-safe** | Mutex для записи. flock для multi-process. |
| D11 | **Dev-only** | Регистрация только в development/test. Railtie initializer. |

### 4.2. Желательные (Should Have)

| ID | Требование | Описание |
|----|------------|----------|
| D12 | **events_by_name(name)** | Фильтр по event_name |
| D13 | **events_by_severity(severity)** | Фильтр по severity |
| D14 | **events_by_trace(trace_id)** | Все события для trace (distributed tracing) |
| D15 | **updated_since?(timestamp)** | Polling для near-realtime Web UI |
| D16 | **Cache** | `@cache` + `@cache_mtime` для read performance |
| D17 | **Config via ENV** | E11Y_MAX_EVENTS, E11Y_MAX_SIZE для override |

### 4.3. Опциональные (Nice to Have)

| ID | Требование | Описание |
|----|------------|----------|
| D18 | **File watcher** | Listen gem (если есть) для инвалидации cache при изменении |
| D19 | **Backup on rotate** | Сохранять rotated file как `.old` для восстановления |
| D20 | **E11y.dev_log_adapter** | Helper для доступа из консоли |

---

## 5. Отличия от File Adapter

| Аспект | File Adapter | DevLog Adapter |
|--------|--------------|----------------|
| **Назначение** | Production logging (Loki, ES backup) | Dev/test event store для Web UI |
| **Write** | write, write_batch | write, write_batch |
| **Read** | ❌ нет | ✅ stored_events, find_event, search, clear!, stats |
| **Rotation** | daily, size, compress | size, max_lines (keep last N%) |
| **Format** | JSONL | JSONL + id на каждое событие |
| **Environment** | любой | только development/test |

**Вывод:** DevLog — это File + Read API. Не дублировать File, а расширить или композировать.

---

## 6. Event Schema (JSONL line)

```json
{
  "id": "uuid",
  "timestamp": "2026-03-13T12:00:00.123Z",
  "event_name": "order.created",
  "severity": "info",
  "payload": { "order_id": 123, "amount": 99.99 },
  "trace_id": "abc123",
  "span_id": "def456",
  "metadata": { "request_id": "req-1", "user_id": 42 }
}
```

**Поля:** id (уникальный), timestamp (ISO8601), event_name, severity, payload, trace_id, span_id, metadata.

---

## 7. API (детализация)

### 7.1. Write (Adapter Contract)

```ruby
def write(event_data)
  # event_data: Hash из pipeline (event_name, severity, timestamp, payload, trace_id, span_id, ...)
  # Append one JSONL line to file
  # Return true/false
end

def write_batch(events)
  # Append N lines. Использовать flock для атомарности.
  # Return { success: true, sent: events.size }
end
```

### 7.2. Read (Web UI / Console)

```ruby
def stored_events(limit: 1000)
  # Read last N lines. Parse JSON. Return Array of Hashes (newest first).
  # Cache: invalidate on file change.

def find_event(id)
  # Scan file (reverse) for event with matching id.

def search(query, limit: 1000)
  # Full-text search in JSON. Return matching events.

def events_by_name(name, limit: 1000)
  # Filter stored_events by event_name.

def events_by_severity(severity, limit: 1000)
  # Filter by severity.

def events_by_trace(trace_id)
  # All events for trace.

def clear!
  # Delete file. Reset cache.

def stats
  # { total_events, file_size, by_severity, by_event_name, oldest_event, newest_event }

def updated_since?(timestamp)
  # File.mtime > timestamp
```

---

## 8. Railtie Integration (F-001)

```ruby
# lib/e11y/railtie.rb
initializer 'e11y.setup_development', after: :load_config_initializers do
  next unless Rails.env.development? || Rails.env.test?
  next if E11y.config.adapters[:dev_log]  # User already configured

  E11y.config.adapters[:dev_log] = E11y::Adapters::DevLog.new(
    path: Rails.root.join('log', 'e11y_dev.jsonl'),
    max_lines: ENV['E11Y_MAX_EVENTS']&.to_i || 10_000,
    max_size: (ENV['E11Y_MAX_SIZE']&.to_i || 10).megabytes,
    enable_watcher: !Rails.env.test?
  )
end
```

**Важно:** Не вызывать в production. `Rails.env.development? || Rails.env.test?`.

---

## 9. Конфигурация (flat config)

```ruby
# Опции в config (если нужны):
# config.dev_log_enabled = true  # default true в dev
# config.dev_log_path = Rails.root.join('log', 'e11y_dev.jsonl')
# config.dev_log_max_lines = 10_000
# config.dev_log_max_size = 10.megabytes
```

**Вопрос:** Нужны ли flat config опции для DevLog? Или достаточно Railtie auto-registration с ENV override?

**Предложение:** Пока Railtie + ENV. Flat config добавлять только если пользователь хочет отключить/настроить через initializer.

---

## 10. Зависимости

| Зависимость | Обязательно? | Примечание |
|-------------|--------------|------------|
| Listen gem | Нет | File watcher — optional. Fallback: polling. |
| Rails | Да (в dev) | Rails.root, Rails.env |
| JSON | Да | stdlib |
| FileUtils | Да | stdlib |

**Вывод:** Zero extra gems. Listen — optional enhancement.

---

## 11. Интеграция в IDE, браузер и расширения

### 11.1. IDE / Editor (VS Code, Cursor)

| Подход | Инструмент | Описание |
|--------|------------|----------|
| **File tail** | [Log Watcher](https://marketplace.visualstudio.com/items?itemName=automattic.logwatcher) | Следит за log-файлами, выводит в Output panel. `tail -F` в IDE. Работает с `log/e11y_dev.jsonl`. |
| **Log Viewer** | [Log Viewer](https://marketplace.visualstudio.com/items?itemName=berublan.vscode-log-viewer) | Синтаксис, glob patterns. 205K+ установок. |
| **Tail-File** | [tail-file](https://github.com/montgomerybc/tail-file) | Unix tail в VS Code. |
| **Datadog** | [Datadog Extension](https://docs.datadoghq.com/ide_plugins/vscode/) | Log Annotations — объём логов над кодом. Search Logs from selection. Production (Datadog). |
| **OpenTelemetry** | [OTel Log Viewer](https://oneuptime.com/blog/post/2026-02-06-otel-log-viewer-vscode-extension/view) | Traces, spans, logs в IDE. Real-time. |
| **Lightrun** | [Lightrun VS Code](https://lightrun.com/plugin/vscode/) | Dynamic logs в консоли IDE. Real-time. |
| **JetBrains** | [Rider OTel Plugin](https://blog.jetbrains.com/dotnet/2025/06/16/opentelemetry-plugin-for-jetbrains-rider) | Logs в таблице, click-to-source. |

**Для DevLog (JSONL):** Самый простой путь — **Log Watcher** или **Log Viewer** с путём `log/e11y_dev.jsonl`. Без доп. кода. DevLog пишет JSONL → IDE читает и показывает в Output.

**Опция:** E11y extension для VS Code/Cursor, который tail'ит `e11y_dev.jsonl`, парсит JSON и показывает в панели (с фильтрами, severity, event_name).

### 11.2. Browser Dev Console

| Подход | Инструмент | Описание |
|--------|------------|----------|
| **Console Viewer** | [Chrome Extension](https://chromewebstore.google.com/detail/console-viewer/enichikjaocbomajlidhphmocmlnjcai) | Логи в DevTools даже когда DevTools закрыт. Поиск, фильтр. |
| **ConsoleLog** | [Chrome Extension](https://chromewebstore.google.com/detail/consolelog/bpkeepmeajdffneiimcknfnjodekcgnh) | Popup-алерты. Server-side logging. |
| **Log Viewer** | [Chrome Extension](https://chromewebstore.google.com/detail/log-viewer/lbnkfmnolbefifdccejjijdgdipnfaib) | Pretty-print JSON, ANSI, YAML. |
| **Logbox** | [egoist/logbox](https://github.com/egoist/logbox) | Логи на странице без открытия DevTools. |

**Для E11y:** События — это backend (Rails). В браузер они попадают только если:
1. **Web UI** — `/e11y` показывает события из DevLog (уже в плане).
2. **ActionCable** — WebSocket-стрим событий в браузер (см. [Rails Live Stream Logs](https://prabinpoudel.com.np/articles/live-stream-logs-to-browser-with-rails/)).
3. **ConsoleSpy** — браузерные console.log → Cursor. Обратная связь: frontend → IDE.

### 11.3. MCP (Model Context Protocol) — Cursor

| MCP Server | Описание |
|------------|----------|
| **ConsoleSpy** | [mgsrevolver/consolespy](https://github.com/mgsrevolver/consolespy) — Browser console → Cursor. Extension + server + MCP. |
| **Datadog MCP** | Production logs в Cursor через MCP. |
| **CursorMCPMonitor** | [willibrandon/CursorMCPMonitor](https://github.com/willibrandon/CursorMCPMonitor) — Observability MCP-коммуникаций. |

**Идея для E11y:** **E11y MCP Server** — читает `log/e11y_dev.jsonl`, предоставляет MCP tools:
- `e11y_recent_events` — последние N событий
- `e11y_search_events` — поиск по query
- `e11y_events_by_trace` — события по trace_id

Cursor AI мог бы вызывать эти tools при отладке.

### 11.4. Рекомендуемые варианты для E11y

| Приоритет | Вариант | Усилие | Описание |
|-----------|---------|--------|----------|
| **P0** | Log Watcher / Log Viewer | 0 | Указать в docs путь `log/e11y_dev.jsonl`. |
| **P1** | Web UI (ADR-010) | Высокое | `/e11y` в браузере — основной UI. |
| **P2** | ActionCable stream | Среднее | WebSocket для real-time в браузере без polling. |
| **P3** | E11y VS Code extension | Высокое | Tail JSONL, панель, фильтры. |
| **P4** | E11y MCP Server | Среднее | Tools для Cursor AI. |

---

## 12. Следующие шаги

1. **Реализовать** `lib/e11y/adapters/dev_log.rb` по требованиям D1–D11
2. **Добавить** `e11y.setup_development` в Railtie
3. **Добавить** `E11y.dev_log_adapter` helper (если config.adapters[:dev_log])
4. **Покрыть** specs
5. **Web UI** (F-006, F-007) — отдельный план
6. **Документировать** IDE-интеграцию: Log Watcher + `log/e11y_dev.jsonl`

---

## 13. Ссылки

### DevLog & Best Practices
- [ADR-010 Developer Experience](docs/ADR-010-developer-experience.md) §4.0
- [NDJSON for Logs](https://ndjson.com/use-cases/log-processing/)
- [Structured Logging Best Practices](https://uptrace.dev/glossary/structured-logging)
- [Serilog UI](https://github.com/serilog-contrib/serilog-ui)
- [Sentry Spotlight](https://spotlightjs.com/)
- [Rails 8.1 Rails.event](https://blog.saeloun.com/2025/12/18/rails-introduces-structured-event-reporting/)
- [tail-jsonl](https://tail-jsonl.kyleking.me/)

### Use Cases (Backend / SPA)
- [How to Log API Requests (Nordic APIs)](https://nordicapis.com/how-to-log-api-requests-for-auditing-and-debugging/)
- [Debugging AJAX and SPA](https://odinuv.cz/articles/debugging/ajax-rest-api-and-spa/)
- [Correlate Frontend-Backend Traces (OneUptime)](https://oneuptime.com/blog/post/2026-01-15-correlate-frontend-backend-traces-react/view)
- [Trace Vue.js API Calls with OTel](https://oneuptime.com/blog/post/2026-02-06-trace-vuejs-api-calls-opentelemetry-fetch/view)
- [Inspectr - Frontend API Inspection](https://inspectr.dev/docs/guides/frontend-inspection)
- [DevConsole Network Intelligence](https://devconsole.dev/docs/features/network)

### IDE / Browser Integration
- [Log Watcher (VS Code)](https://marketplace.visualstudio.com/items?itemName=automattic.logwatcher)
- [Log Viewer (VS Code)](https://marketplace.visualstudio.com/items?itemName=berublan.vscode-log-viewer)
- [ConsoleSpy MCP](https://github.com/mgsrevolver/consolespy) — Browser console → Cursor
- [Datadog VS Code Extension](https://docs.datadoghq.com/ide_plugins/vscode/)
- [OpenTelemetry Log Viewer VS Code](https://oneuptime.com/blog/post/2026-02-06-otel-log-viewer-vscode-extension/view)
- [Rails Live Stream Logs](https://prabinpoudel.com.np/articles/live-stream-logs-to-browser-with-rails/)
- [Logbox](https://github.com/egoist/logbox) — Console logs on page without DevTools
