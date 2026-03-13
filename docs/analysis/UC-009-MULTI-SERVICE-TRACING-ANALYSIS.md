# UC-009 Multi-Service Tracing: Integration Test Analysis

**Task:** FEAT-5413 - UC-009 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** TraceContext middleware (`E11y::Middleware::TraceContext`) adds trace_id, span_id, parent_trace_id to events
- ✅ **Implemented:** Request middleware (`E11y::Middleware::Request`) extracts trace_id from HTTP headers (W3C Trace Context, X-Request-ID, X-Trace-ID)
- ✅ **Implemented:** E11y::Current stores trace context (trace_id, span_id, parent_trace_id) using ActiveSupport::CurrentAttributes
- ✅ **Implemented:** Trace context extraction from incoming HTTP requests (traceparent header parsing)
- ✅ **Implemented:** Parent-child trace relationships (parent_trace_id field for background jobs)
- ❌ **NOT Implemented:** HTTP Propagator for outgoing requests (no automatic traceparent injection) - per AUDIT-027
- ❌ **NOT Implemented:** Automatic trace context propagation in HTTP clients (Faraday, Net::HTTP, HTTParty)
- ⚠️ **PARTIAL:** Baggage propagation (E11y::Current.baggage exists but propagation not implemented)
- ⚠️ **PARTIAL:** Sampling decisions (sampled flag exists but distributed sampling not implemented)

**Unit Test Coverage:** Good (comprehensive tests for TraceContext middleware, Request middleware, trace_id extraction, span_id generation)

**Integration Test Coverage:** ⚠️ **PARTIAL** - Basic trace context tests exist, but cross-service propagation not fully tested

**Integration Test Status:**
1. ✅ Trace context within single service (trace_id, span_id) - Covered in `spec/integration/end_to_end_spec.rb` and `spec/integration/middleware_integration_spec.rb`
2. ✅ Parent-child span relationships (parent_trace_id linking) - Covered in `spec/integration/sidekiq_integration_spec.rb` (parent_trace_id injection into Sidekiq jobs)
3. ✅ Context propagation across middleware stack - Covered in `spec/integration/middleware_integration_spec.rb`
4. ✅ Unique trace IDs per request - Covered in `spec/integration/end_to_end_spec.rb`
5. ❌ Cross-service trace propagation (Service A → B → C with same trace_id) - Not tested (requires multi-service setup)
6. ⚠️ Baggage propagation - May not be implemented (per analysis: "if implemented, or verify current state")

**Test Files:**
- `spec/integration/end_to_end_spec.rb` - Trace context in request lifecycle (3 scenarios)
- `spec/integration/middleware_integration_spec.rb` - Trace context in middleware (3 scenarios)
- `spec/integration/sidekiq_integration_spec.rb` - Parent trace ID injection into Sidekiq jobs (2 scenarios)

**Note:** Basic trace context functionality is tested within single-service scenarios. Cross-service trace propagation would require multi-service integration test setup (not currently implemented).
4. Sampling decisions (sampled flag propagation across services)
5. Trace context across HTTP boundaries (manual header injection/extraction)
6. Mixed services scenarios (3+ services in distributed trace)
7. Trace reconstruction (query all events by trace_id)
8. W3C Trace Context format (traceparent header parsing/generation)
9. Background job trace propagation (parent_trace_id linking)
10. Service boundary events (service_boundary DSL if implemented)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/trace_context.rb`, `lib/e11y/middleware/request.rb`, `lib/e11y/current.rb`

**Key Components:**
- `E11y::Middleware::TraceContext` - Adds trace_id, span_id, parent_trace_id to events
- `E11y::Middleware::Request` - Extracts trace_id from HTTP headers, sets E11y::Current
- `E11y::Current` - Request/job-scoped context storage (ActiveSupport::CurrentAttributes)
- Trace ID extraction from HTTP headers (W3C Trace Context, legacy headers)

**Trace Context Flow:**
1. HTTP Request arrives → Request middleware extracts trace_id from headers
2. Request middleware sets E11y::Current.trace_id, E11y::Current.span_id
3. Event tracked: `Event.track(...)` → TraceContext middleware reads E11y::Current
4. TraceContext middleware adds trace_id, span_id, parent_trace_id to event_data
5. Event stored with trace context → Can query by trace_id

**Gap:** No automatic HTTP propagation (outgoing requests don't inject traceparent header)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Trace ID extraction (incoming) | ✅ Implemented | Request middleware extracts from traceparent/X-Request-ID |
| Trace ID generation | ✅ Implemented | SecureRandom.hex(16) for trace_id, SecureRandom.hex(8) for span_id |
| Trace context storage | ✅ Implemented | E11y::Current (ActiveSupport::CurrentAttributes) |
| Trace context in events | ✅ Implemented | TraceContext middleware adds trace_id, span_id, parent_trace_id |
| Parent-child relationships | ✅ Implemented | parent_trace_id field for background jobs (C17 Resolution) |
| W3C Trace Context parsing | ⚠️ PARTIAL | Parses traceparent header (basic split, no validation) |
| HTTP Propagator (outgoing) | ❌ NOT Implemented | Per AUDIT-027, no automatic traceparent injection |
| Baggage propagation | ⚠️ PARTIAL | E11y::Current.baggage exists but propagation not implemented |
| Sampling decisions | ⚠️ PARTIAL | sampled flag exists but distributed sampling not implemented |
| Service boundary DSL | ❌ NOT Implemented | service_boundary DSL not found |

### 1.3. Configuration

**Current API:**
```ruby
# Trace context automatically extracted from HTTP headers
# Request middleware extracts trace_id from:
# 1. traceparent header (W3C Trace Context)
# 2. X-Request-ID header (Rails default)
# 3. X-Trace-ID header (custom)
# 4. Auto-generates if none present

# Usage
Events::OrderCreated.track(order_id: 123)
# → trace_id automatically added from E11y::Current.trace_id

# Manual trace_id (preserved, not overridden)
Events::OrderCreated.track(order_id: 123, trace_id: 'custom-trace-id')
```

**W3C Trace Context Format:**
- **traceparent:** `{version}-{trace-id}-{parent-id}-{trace-flags}`
- **Example:** `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
- **Parsing:** Basic split on `-`, extracts trace_id from index [1]

**Gap:** No traceparent generation for outgoing requests (HTTP Propagator missing)

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/trace_context_spec.rb`

**Coverage Summary:**
- ✅ **Trace context enrichment** (trace_id, span_id, parent_trace_id)
- ✅ **E11y::Current integration** (reads from Current, generates if missing)
- ✅ **Timestamp formatting** (ISO8601 format)
- ✅ **Retention calculation** (retention_until from retention_period)
- ✅ **Audit event flag** (audit_event? detection)

**Key Test Scenarios:**
- Trace ID from E11y::Current
- Trace ID generation (if Current empty)
- Span ID generation (always new)
- Parent trace ID (for background jobs)
- Timestamp formatting

### 2.2. Test File: `spec/e11y/middleware/request_spec.rb`

**Coverage Summary:**
- ✅ **Trace ID extraction** (traceparent, X-Request-ID, X-Trace-ID)
- ✅ **Trace ID generation** (if no headers present)
- ✅ **E11y::Current setup** (trace_id, span_id, request_id)
- ✅ **Response headers** (X-E11y-Trace-Id, X-E11y-Span-Id)

**Key Test Scenarios:**
- W3C Trace Context extraction (traceparent header)
- Legacy header extraction (X-Request-ID, X-Trace-ID)
- Auto-generation (no headers)
- Context reset (after request)

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/audit_trail_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Multiple "services" simulated via different event classes or controllers
- HTTP client simulation (manual header injection/extraction)
- Memory adapter for event capture
- Trace context verification (query events by trace_id)

**Test Structure:**
```ruby
RSpec.describe "Multi-Service Tracing Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  
  before do
    memory_adapter.clear!
    E11y::Current.reset
    
    # Configure adapters
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
    E11y::Current.reset
  end
  
  describe "Scenario 1: Cross-service trace propagation" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Trace Propagation Assertions:**
- ✅ Same trace_id: All events in distributed trace have same trace_id
- ✅ Parent-child relationships: parent_trace_id links child traces to parent
- ✅ Span ID uniqueness: Each event has unique span_id
- ✅ Trace reconstruction: Can query all events by trace_id

**HTTP Propagation Assertions:**
- ✅ Header extraction: traceparent header extracted correctly
- ✅ Header injection: traceparent header injected (if HTTP Propagator implemented, or manual)
- ✅ W3C format: traceparent format matches W3C spec

**Baggage Assertions:**
- ✅ Baggage propagation: Baggage preserved across services (if implemented)
- ✅ Baggage format: Baggage in tracestate header (if implemented)

**Sampling Assertions:**
- ✅ Sampling decisions: sampled flag propagated across services (if implemented)
- ✅ Sampling consistency: Same sampling decision for all spans in trace

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Cross-Service Trace Propagation

**Objective:** Verify trace_id propagates across Service A → B → C.

**Setup:**
- Service A: Tracks event, sets trace_id
- Service B: Receives trace_id (via manual header or E11y::Current), tracks event
- Service C: Receives trace_id, tracks event

**Test Steps:**
1. Service A: Set E11y::Current.trace_id = "abc-123", track Events::OrderCreated
2. Service B: Set E11y::Current.trace_id = "abc-123" (simulated propagation), track Events::PaymentReceived
3. Service C: Set E11y::Current.trace_id = "abc-123", track Events::OrderShipped
4. Verify: All events have same trace_id

**Assertions:**
- Same trace_id: `expect(event_a[:trace_id]).to eq(event_b[:trace_id])`
- Trace reconstruction: Query events by trace_id returns all 3 events

---

### Scenario 2: Parent-Child Span Relationships

**Objective:** Verify parent_trace_id links child traces to parent.

**Setup:**
- Parent trace: HTTP request trace (trace_id: "parent-123")
- Child trace: Background job trace (trace_id: "child-456", parent_trace_id: "parent-123")

**Test Steps:**
1. Parent trace: Track Events::OrderCreated (trace_id: "parent-123")
2. Child trace: Track Events::OrderProcessed (trace_id: "child-456", parent_trace_id: "parent-123")
3. Verify: Parent-child relationship preserved

**Assertions:**
- Parent trace_id: `expect(child_event[:parent_trace_id]).to eq("parent-123")`
- Trace reconstruction: Query by parent_trace_id returns child events

---

### Scenario 3: Baggage Propagation

**Objective:** Verify baggage propagates across services (if implemented).

**Setup:**
- Service A: Sets baggage, tracks event
- Service B: Receives baggage, tracks event

**Test Steps:**
1. Service A: Set E11y::Current.baggage = { user_id: "123", tenant: "acme" }, track event
2. Service B: Verify baggage received (if implemented)
3. Verify: Baggage preserved in events

**Assertions:**
- Baggage present: `expect(event[:baggage]).to eq({ user_id: "123", tenant: "acme" })`
- Baggage propagation: Baggage preserved across services (if implemented)

**Note:** Baggage propagation may not be implemented. Tests should verify current state.

---

### Scenario 4: Sampling Decisions

**Objective:** Verify sampled flag propagates across services (if implemented).

**Setup:**
- Service A: Sets sampled = true, tracks event
- Service B: Receives sampled flag, tracks event

**Test Steps:**
1. Service A: Set E11y::Current.sampled = true, track event
2. Service B: Verify sampled flag received (if implemented)
3. Verify: Sampling decision consistent across trace

**Assertions:**
- Sampled flag: `expect(event[:sampled]).to be(true)`
- Sampling consistency: All events in trace have same sampled value (if implemented)

**Note:** Distributed sampling may not be implemented. Tests should verify current state.

---

### Scenario 5: Trace Context Across HTTP

**Objective:** Verify trace context propagates via HTTP headers (manual or automatic).

**Setup:**
- Service A: Makes HTTP request to Service B
- Service B: Extracts trace_id from headers

**Test Steps:**
1. Service A: Set E11y::Current.trace_id = "abc-123"
2. Service A: Make HTTP request with traceparent header (manual injection or automatic)
3. Service B: Extract trace_id from traceparent header
4. Service B: Track event with extracted trace_id
5. Verify: Trace ID propagated correctly

**Assertions:**
- Header extraction: `expect(extracted_trace_id).to eq("abc-123")`
- Trace propagation: Events from Service A and B have same trace_id

**Note:** HTTP Propagator not implemented. Tests should verify manual header injection/extraction.

---

### Scenario 6: Mixed Services (3+ Services)

**Objective:** Verify trace propagation across multiple services.

**Setup:**
- Service A → Service B → Service C → Service D

**Test Steps:**
1. Service A: Track Events::OrderCreated (trace_id: "abc-123")
2. Service B: Track Events::PaymentReceived (trace_id: "abc-123")
3. Service C: Track Events::InventoryReserved (trace_id: "abc-123")
4. Service D: Track Events::OrderShipped (trace_id: "abc-123")
5. Verify: All events have same trace_id

**Assertions:**
- Trace consistency: All events have same trace_id
- Trace reconstruction: Query by trace_id returns all 4 events
- Service order: Events ordered by timestamp show correct flow

---

### Scenario 7: Trace Reconstruction

**Objective:** Verify all events in distributed trace can be queried by trace_id.

**Setup:**
- Multiple events across services with same trace_id

**Test Steps:**
1. Track events across 3 services (same trace_id)
2. Query events by trace_id: `memory_adapter.events.select { |e| e[:trace_id] == "abc-123" }`
3. Verify: All events returned

**Assertions:**
- Event count: `expect(events.size).to eq(3)`
- Trace completeness: All events from all services included
- Event order: Events ordered by timestamp

---

### Scenario 8: W3C Trace Context Format

**Objective:** Verify W3C Trace Context format parsing and generation.

**Setup:**
- traceparent header: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`

**Test Steps:**
1. Parse traceparent header: Extract trace_id, span_id, flags
2. Generate traceparent header: Create W3C format from trace_id, span_id, sampled
3. Verify: Format matches W3C spec

**Assertions:**
- Format validation: traceparent matches `{version}-{trace-id}-{parent-id}-{flags}` pattern
- Trace ID extraction: Correct trace_id extracted from header
- Header generation: Valid traceparent header generated (if HTTP Propagator implemented)

**Note:** W3C format generation may not be implemented. Tests should verify parsing.

---

### Scenario 9: Background Job Trace Propagation

**Objective:** Verify parent_trace_id links background jobs to parent request.

**Setup:**
- HTTP request trace (trace_id: "request-123")
- Background job trace (trace_id: "job-456", parent_trace_id: "request-123")

**Test Steps:**
1. Request trace: Track Events::OrderCreated (trace_id: "request-123")
2. Job trace: Track Events::OrderProcessed (trace_id: "job-456", parent_trace_id: "request-123")
3. Verify: Parent-child relationship

**Assertions:**
- Parent link: `expect(job_event[:parent_trace_id]).to eq("request-123")`
- Trace reconstruction: Query by parent_trace_id returns job events

---

### Scenario 10: Service Boundary Events

**Objective:** Verify service boundary DSL works (if implemented).

**Setup:**
- Service A: Events::OrderCreated with `service_boundary :outgoing`
- Service B: Events::PaymentReceived with `service_boundary :incoming`

**Test Steps:**
1. Define event classes with service_boundary DSL
2. Track events across service boundaries
3. Verify: Service boundaries marked correctly

**Assertions:**
- Service boundary: `expect(event[:service_boundary]).to eq(:outgoing)`
- Boundary detection: Service boundaries detected correctly (if implemented)

**Note:** service_boundary DSL may not be implemented. Tests should verify current state.

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Trace Context Middleware Integration

**Integration Point:** `E11y::Middleware::TraceContext`

**Flow:**
1. Event tracked → `Event.track(...)`
2. TraceContext middleware → Reads E11y::Current.trace_id, adds to event_data
3. Event stored → trace_id included in stored event

**Test Requirements:**
- TraceContext middleware configured in pipeline
- E11y::Current.trace_id set before event tracking
- Events include trace_id, span_id, parent_trace_id

### 5.2. Request Middleware Integration

**Integration Point:** `E11y::Middleware::Request`

**Flow:**
1. HTTP request arrives → Request middleware extracts trace_id from headers
2. Request middleware → Sets E11y::Current.trace_id, E11y::Current.span_id
3. Events tracked → Use trace_id from E11y::Current

**Test Requirements:**
- Request middleware configured
- HTTP headers with traceparent or X-Request-ID
- E11y::Current populated correctly

### 5.3. HTTP Propagation Integration

**Integration Point:** HTTP Propagator (NOT IMPLEMENTED)

**Flow:**
1. Service A: E11y::Current.trace_id set
2. HTTP request → traceparent header injected (if HTTP Propagator implemented)
3. Service B: Extracts trace_id from traceparent header

**Test Requirements:**
- Manual header injection (simulate HTTP Propagator)
- Header extraction verification
- Trace ID propagation verification

**Gap:** HTTP Propagator not implemented. Tests should verify manual propagation or note limitation.

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. HTTP Propagator

**Status:** ❌ **NOT IMPLEMENTED** (per AUDIT-027)

**Gap:** No automatic traceparent header injection in outgoing HTTP requests.

**Current Workaround:** Manual header injection required.

**Impact:** Integration tests should verify manual propagation or note limitation.

### 6.2. Baggage Propagation

**Status:** ⚠️ **PARTIAL** (E11y::Current.baggage exists but propagation not implemented)

**Gap:** Baggage not propagated in HTTP headers (tracestate).

**Impact:** Integration tests should verify current state (baggage stored but not propagated).

### 6.3. Distributed Sampling

**Status:** ⚠️ **PARTIAL** (sampled flag exists but distributed sampling not implemented)

**Gap:** Sampling decisions not propagated across services.

**Impact:** Integration tests should verify current state (sampled flag stored but not propagated).

### 6.4. Service Boundary DSL

**Status:** ❌ **NOT IMPLEMENTED**

**Gap:** service_boundary DSL not found in codebase.

**Impact:** Integration tests should note limitation or verify if implemented.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderCreated` - Service A event
- `Events::PaymentReceived` - Service B event
- `Events::OrderShipped` - Service C event
- `Events::OrderProcessed` - Background job event

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Trace IDs

**Required Trace IDs:**
- Parent trace: `"parent-trace-123"`
- Child trace: `"child-trace-456"`
- Distributed trace: `"distributed-trace-789"`

### 7.3. Test Headers

**Required Headers:**
- W3C Trace Context: `traceparent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"`
- Legacy: `X-Request-ID: "abc-123"`, `X-Trace-ID: "abc-123"`

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 10 scenarios implemented and passing
2. ✅ Cross-service trace propagation tested (same trace_id across services)
3. ✅ Parent-child relationships tested (parent_trace_id linking)
4. ✅ Baggage propagation tested (if implemented, or current state verified)
5. ✅ Sampling decisions tested (if implemented, or current state verified)
6. ✅ HTTP trace context tested (manual header injection/extraction)
7. ✅ Mixed services tested (3+ services in distributed trace)
8. ✅ Trace reconstruction tested (query events by trace_id)
9. ✅ W3C format tested (traceparent parsing/generation)
10. ✅ Background job propagation tested (parent_trace_id linking)
11. ✅ Service boundary events tested (if implemented)
12. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-009:** `docs/use_cases/UC-009-multi-service-tracing.md`
- **ADR-005:** `docs/ADR-005-tracing-context.md` (Sections 5, 6.1, 8)
- **AUDIT-027:** `docs/researches/post_implementation/AUDIT-027-UC-009-CROSS-SERVICE-PROPAGATION.md`
- **TraceContext Implementation:** `lib/e11y/middleware/trace_context.rb`
- **Request Implementation:** `lib/e11y/middleware/request.rb`
- **Current Implementation:** `lib/e11y/current.rb`

---

**Analysis Complete:** 2026-01-26
**Next Step:** UC-009 Phase 2: Planning Complete

---

## 🔍 Production Readiness Audit — 2026-03-10

**Audit Date:** 2026-03-10
**Status:** ✅ PRODUCTION-READY для single-service; ⚠️ Known limitation для outgoing HTTP propagation

### Обновлённый статус компонентов

| Компонент | Статус | Notes |
|-----------|--------|-------|
| TraceContext middleware | ✅ PRODUCTION-READY | trace_id, span_id, parent_trace_id во всех events |
| Request middleware | ✅ PRODUCTION-READY | Extracts from traceparent, X-Request-ID, X-Trace-ID |
| E11y::Current | ✅ PRODUCTION-READY | Thread-local, ActiveSupport::CurrentAttributes |
| W3C Trace Context (incoming) | ✅ PRODUCTION-READY | Basic traceparent parsing works |
| Parent-child (background jobs) | ✅ PRODUCTION-READY | parent_trace_id tested in Sidekiq integration |
| **Outgoing HTTP propagation** | ❌ → **v1.1 Backlog** | Faraday/Net::HTTP не поддерживаются автоматически |
| Baggage propagation | ⚠️ PARTIAL | E11y::Current.baggage существует, API не доступен |
| Distributed sampling | ⚠️ PARTIAL | sampled flag есть, distributed decision нет |

### v1.1 Backlog: Outgoing HTTP Propagation

**Что не работает сейчас:**
- Faraday, Net::HTTP, HTTParty не получают автоматически `traceparent` header
- При вызове downstream сервисов trace context теряется на стыке
- Нет Faraday middleware для автоматического inject

**Временный workaround для v1.0 пользователей:**
```ruby
# Ручной inject traceparent при вызовах к другим сервисам
trace_id = E11y::Current.trace_id
span_id = E11y::Current.span_id
headers = {
  "traceparent" => "00-#{trace_id}-#{span_id[0..15]}-01",
  "X-Trace-ID" => trace_id
}
# Передать headers в HTTP клиент
response = faraday_client.get("/api/endpoint", nil, headers)
```

**Что нужно реализовать в v1.1:**
1. `E11y::Instruments::FaradayMiddleware` — Rack middleware для Faraday
2. `E11y::Instruments::NetHttpInstrumentation` — monkey-patch или prepend для Net::HTTP
3. `config.auto_propagate_trace_context = true` — opt-in (не всегда нужно)
4. Integration tests: cross-service trace propagation с двумя mock-сервисами

### ✅ Что работает и проверено (audit)

- Single-service tracing: полный flow trace_id → events ✅
- Parent-child job tracing: tested in `sidekiq_integration_spec.rb` ✅
- Context through middleware stack: tested in `middleware_integration_spec.rb` ✅
- Response headers include `X-E11y-Trace-Id` и `X-E11y-Span-Id` ✅

### ⚠️ W3C Compliance Note

Текущий traceparent parsing — `split("-")` без полной валидации формата.
Для полного W3C Trace Context compliance нужна валидация:
- version field = "00"
- trace-id = 32 hex chars
- parent-id = 16 hex chars
- flags = valid 8-bit integer
Приоритет: низкий для v1.0 (большинство систем отправляют валидный traceparent).
