# Анализ падающих интеграционных тестов

**Дата:** 2025-03-05  
**Цель:** Определить, где проблема — в коде или в тестах

---

## Сводка по категориям

| Категория | Кол-во | Проблема в | Рекомендация |
|-----------|--------|------------|--------------|
| 1. Rate Limiting | 9 | **Тесты** | Добавить `fallback_adapters = [:memory]` |
| 2. PII Filtering | 7 | **Тесты** | Добавить `fallback_adapters` + `find_events_by_class` |
| 3. Critical Adapters (Loki/OTel) | 9 | **Инфраструктура** | Запустить `docker-compose up -d` |
| 4. Audit Trail (tamper detection) | 2 | **Код** | Исправить `verify_signature` — пересчитывать canonical |
| 5. Audit Routing Validation | 2 | **Код** | Исправить `resolved_adapters` для audit events |
| 6. SLO Tracking | 8 | **Тесты** | Изолировать Prometheus метрики между тестами |
| 7. High Cardinality (memory) | 1 | **Тест** | Заменить `pending` на `skip` с условием |
| 8. Pattern Metrics, Validation, etc. | ~10 | Разное | См. детали ниже |

---

## 1. Rate Limiting (9 тестов) — ЧАСТИЧНО ТЕСТЫ, ЧАСТИЧНО КОД

**Исправлено:** fallback_adapters = [:memory] — события теперь попадают в memory.

**Остаётся:** Scenarios 2, 3 — rate limiting не срабатывает (получаем 15 вместо 10, 8 вместо 5).
- Возможные причины: порядок middleware (RateLimiting добавляется в before, но pipeline может кэшироваться), или RateLimiting не применяется к Events::EventA/B/C/TestEvent.
- Требуется отладка: проверить, что RateLimiting в pipeline и вызывается.

---

## 2. PII Filtering (7 тестов) — СМЕШАННО

**Частично исправлено (fallback_adapters, find_events_by_class):**
- Scenario 1 (password) — проходит
- Scenario 3 (authorization header) — проходит

**Остаются проблемы:**

**Scenarios 2, 4, 5, 6 — конфликт тестов и конфигурации событий:**
- `PaymentSubmitted` имеет `allows :card_number` — поле явно разрешено, не фильтруется. Тест ожидает `[FILTERED]`.
- `OrderCreated` имеет `allows :customer` — вложенный email не фильтруется.
- `ReportCreated` имеет `allows :description, :author` — тест ожидает фильтрацию.
- `DocumentUploaded` имеет `allows :filename, :metadata` — тест ожидает фильтрацию.

**Варианты решения:**
- **A)** Изменить конфигурацию событий в dummy app: убрать PII-поля из `allows`, добавить в `masks` (или не указывать, чтобы применялись паттерны по умолчанию)
- **B)** Изменить тесты под текущую конфигурацию (проверять, что разрешённые поля не фильтруются)

**Рекомендация:** Вариант A — тесты описывают желаемое поведение (фильтрация PII)

---

## 3. Critical Adapters — Loki, OTel (9 тестов) — ИНФРАСТРУКТУРА

**Симптом:** `Required service 'Loki' is not available. URL: http://localhost:3100`

**Причина:** Loki не запущен локально.

**Решение:** 
```bash
docker-compose up -d
```
Или пометить тесты как требующие сервисов и пропускать в CI без Loki.

---

## 4. Audit Trail — Tamper Detection (2 теста) — ПРОБЛЕМА В КОДЕ

**Симптом:** `expect(verify_signature(tampered)).to be(false)` — получаем `true` вместо `false`

**Причина:** В `lib/e11y/middleware/audit_signing.rb` метод `verify_signature` использует **сохранённый** `event_data[:audit_canonical]` вместо пересчёта из текущих данных:

```ruby
# Текущий код (НЕПРАВИЛЬНО):
canonical = event_data[:audit_canonical]  # ← при подмене payload canonical не меняется!
actual_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, canonical)
```

При изменении `payload` поле `audit_canonical` остаётся старым, подпись совпадает.

**Решение (в коде):** Пересчитывать canonical из текущего event_data:

```ruby
def self.verify_signature(event_data)
  expected_signature = event_data[:audit_signature]
  return false unless expected_signature

  # Recompute from CURRENT data (detects tampering)
  canonical = canonical_representation(event_data)
  actual_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, canonical)
  actual_signature == expected_signature
end
```

Документ `docs/quality-assurance/AUDIT-TRAIL-FIX.md` описывает именно это исправление, но в коде оно не применено/откачено.

---

## 5. Audit Routing Validation (2 теста) — ПРОБЛЕМА В КОДЕ

**Симптом:** Ожидается `raise_error(E11y::Error, /CRITICAL: Audit event/)`, но исключение не выбрасывается.

**Причина:** Audit events без явных adapters получают `adapters` из `resolved_adapters` → `adapters_for_severity(:info)` → `[:logs]`. В `validate_audit_routing!` проверка `has_explicit_adapters = event_data[:adapters]&.any?` даёт true (т.к. `[:logs]`), и валидация пропускается. Событие уходит в logs, а не в fallback, и ошибка не возникает.

По AUDIT-TRAIL-FIX audit events без explicit adapters должны иметь `adapters = []`, чтобы использовались routing rules.

**Решение (в коде):** В `lib/e11y/event/base.rb` в `resolved_adapters` добавить:

```ruby
def resolved_adapters
  # Audit events without explicit adapters use routing rules (UC-012)
  return [] if audit_event? && !@adapters
  E11y.configuration.adapters_for_severity(severity)
end
```

И в `adapters()` при вызове `resolved_adapters` для audit events без @adapters возвращать `[]`:

```ruby
def adapters(*list)
  if list.any?
    @adapters = list.flatten
    @explicit_adapters = true
  end
  return @adapters if @adapters
  return superclass.adapters if superclass != E11y::Event::Base && superclass.instance_variable_get(:@adapters)

  # Audit events without explicit adapters → [] (use routing rules)
  return [] if audit_event? && !explicit_adapters?
  resolved_adapters
end
```

(Нужно аккуратно согласовать с текущей логикой `adapters`/`resolved_adapters`.)

---

## 6. SLO Tracking (8 тестов) — ПРОБЛЕМА В ТЕСТАХ

**Симптом:** `Prometheus::Client::Registry::AlreadyRegisteredError: e11y_slo_http_requests_total has already been registered`

**Причина:** Метрики регистрируются в `Yabeda.configure` в `before` каждого теста. Prometheus registry глобальный — повторная регистрация той же метрики вызывает ошибку.

**Решение:** 
- Либо регистрировать метрики один раз (в общем `before` или shared context)
- Либо использовать `Yabeda.reset!` / unregister между тестами (если API позволяет)
- Либо оборачивать регистрацию в `rescue AlreadyRegisteredError` и продолжать

---

## 7. High Cardinality — Memory Impact (1 тест) — ПРОБЛЕМА В ТЕСТЕ

**Симптом:** `Expected pending '...' to fail. No error was raised.`

**Причина:** Тест помечен `pending` с сообщением про memory_profiler. При этом тело теста выполняется и проходит. RSpec при `pending` ожидает, что тест упадёт; если не падает — выдаёт эту ошибку.

**Решение:** Заменить на условный skip:
```ruby
it "maintains acceptable memory usage..." do
  skip "Memory profiling requires memory_profiler gem" unless defined?(MemoryProfiler)
  # ... rest of test
end
```
Или убрать `pending` и сделать тест реально проверяющим память при наличии memory_profiler.

---

## 8. Остальные тесты

- **Middleware, End-to-End:** В текущем прогоне проходят — возможно, падали в другом окружении.
- **Sampling:** Проходят.
- **Pattern Metrics, Validation:** Требуют отдельного прогона для уточнения.

---

## Рекомендуемый порядок исправлений

1. **Тесты (низкий риск):** Rate Limiting, PII Filtering, SLO Tracking, High Cardinality
2. **Код (нужно согласование):** AuditSigning.verify_signature, resolved_adapters для audit events
3. **Инфраструктура:** Loki/OTel — документировать требования и CI-настройку

---

## Вопросы для уточнения

1. **AuditSigning.verify_signature:** Подтверждаете изменение на пересчёт canonical из текущего event_data? (Это соответствует AUDIT-TRAIL-FIX и ожидаемому поведению.)
2. **Audit routing:** Подтверждаете, что audit events без explicit adapters должны иметь `adapters = []` и идти только через routing rules?
3. **SLO metrics:** Предпочтительный вариант — один раз регистрировать метрики, или оборачивать в rescue AlreadyRegisteredError?
4. **Loki/OTel тесты:** Оставляем как требующие docker-compose, или добавляем условный skip при недоступности сервисов?
