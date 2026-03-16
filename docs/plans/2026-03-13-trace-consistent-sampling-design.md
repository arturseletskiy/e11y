# Trace-Consistent Sampling (F-023) Design

> **For Claude:** After design approval, invoke writing-plans skill to create implementation plan.

**Goal:** Implement ADR-005 §7 trace-consistent sampling — sampling decision at trace entry, propagated via HTTP (traceparent) and jobs (e11y_sampled).

**Architecture:** Sampling decision is made once at trace entry (HTTP Request middleware or Job server) and stored in `E11y::Current.sampled`. Downstream services and events inherit this decision. Propagator uses `sampled` in W3C traceparent flags; Sidekiq/ActiveJob propagate `e11y_sampled` in job metadata.

**Tech Stack:** Ruby, Rack, W3C Trace Context, ActiveSupport::CurrentAttributes, Sidekiq, ActiveJob.

---

## 1. Context & Problem

**Current state:**
- `E11y::Current` has no `sampled` attribute (F-008)
- `E11y::Tracing::Propagator` always uses `"01"` (sampled) in traceparent (F-016)
- Sidekiq/ActiveJob do not propagate `e11y_sampled` (F-017)
- No `E11y::TraceContext::Sampler` class (F-024)
- Request middleware does not parse traceparent flags or set sampled (F-025)

**Desired state (ADR-005 §7):**
- Sampling decision at trace entry
- Parent's sampled decision respected when `respect_parent_sampling` is true
- Sampled propagated in HTTP (traceparent flags) and jobs (e11y_sampled)
- All events in a trace share the same sampling decision

---

## 2. Components

### 2.1 E11y::Current — add `sampled` attribute

- Add `attribute :sampled` to `E11y::Current`
- Type: `Boolean` or `nil` (nil = not yet decided)
- Reset with other attributes in `reset`

### 2.2 E11y::TraceContext::Sampler

**Location:** `lib/e11y/trace_context/sampler.rb`

**Interface:**
```ruby
E11y::TraceContext::Sampler.should_sample?(context)
# context: { trace_id:, span_id:, sampled: (from parent), user_id:, event_name: (optional) }
# Returns: Boolean
```

**Logic (priority order):**
1. If `context[:sampled]` is set and `respect_parent_sampling` → return it
2. If `context[:error]` → return true (always sample errors)
3. If `context[:event_name]` and per_event_rate exists → rand < rate
4. If `context[:user_id]` in debug_users → return true
5. Default: rand < default_sample_rate

**Config:** Extend `TracingConfig` with sampling options:
- `default_sample_rate` (0.1)
- `respect_parent_sampling` (true)
- `per_event_sample_rates` (Hash, optional)
- `debug_users` (Array, optional)

### 2.3 Request Middleware — trace entry for HTTP

**Changes to `lib/e11y/middleware/request.rb`:**
- Use `E11y::Tracing::Propagator.parse(traceparent)` when traceparent present
- If parsed: set `E11y::Current.sampled = parsed[:sampled]` (respect parent)
- If no traceparent (new trace): call `Sampler.should_sample?(context)` and set `E11y::Current.sampled`
- Context for Sampler: `{ trace_id:, span_id:, user_id: extract_user_id(env) }`

### 2.4 Propagator — use E11y::Current.sampled

**Changes to `lib/e11y/tracing/propagator.rb`:**
- `build_traceparent`: use `E11y::Current.sampled` for flags; default to `true` if nil (backward compat)
- Flags: `sampled ? "01" : "00"`

### 2.5 Sidekiq ClientMiddleware — propagate e11y_sampled

**Changes to `lib/e11y/instruments/sidekiq.rb`:**
- ClientMiddleware: `job["e11y_sampled"] = E11y::Current.sampled` when sampled is set

### 2.6 Sidekiq ServerMiddleware — restore sampled

**Changes to `lib/e11y/instruments/sidekiq.rb`:**
- ServerMiddleware `setup_job_context`: restore `E11y::Current.sampled = job["e11y_sampled"]` if present
- If not present (legacy job): call `Sampler.should_sample?(context)` for new trace

### 2.7 ActiveJob — propagate and restore e11y_sampled

**Changes to `lib/e11y/instruments/active_job.rb`:**
- Add `e11y_sampled` to TraceAttributes
- before_enqueue: set `job.e11y_sampled = E11y::Current.sampled`
- setup_job_context_active_job: restore `E11y::Current.sampled = job.e11y_sampled` if present
- If not present: call Sampler for new trace

### 2.8 Sampling Middleware — prefer E11y::Current.sampled

**Changes to `lib/e11y/middleware/sampling.rb`:**
- In `should_sample?`, when `trace_aware` and `event_data[:trace_id]`:
  - If `E11y::Current.sampled` is set (not nil) → use it (trace entry decision)
  - Else → fall back to existing `trace_sampling_decision` (cache for manual API)

---

## 3. Data Flow

```
HTTP Request
  → Request middleware: extract traceparent OR generate
  → If traceparent: parsed[:sampled] → E11y::Current.sampled
  → Else: Sampler.should_sample? → E11y::Current.sampled
  → Events: Sampling middleware uses E11y::Current.sampled when trace_aware
  → Outgoing HTTP: Propagator uses E11y::Current.sampled in traceparent flags
  → Job enqueue: e11y_sampled in job metadata

Job Server
  → setup_job_context: restore E11y::Current.sampled from metadata
  → If no metadata: Sampler.should_sample? (new trace)
  → Events: same as HTTP
```

---

## 4. Configuration

```ruby
E11y.configure do |config|
  config.tracing do
    source :e11y
    # Trace-consistent sampling (ADR-005 §7)
    default_sample_rate 0.1
    respect_parent_sampling true
    per_event_sample_rates do
      event 'payment.processed', sample_rate: 1.0
      event 'health_check', sample_rate: 0.01
    end
    debug_users [123, 456]  # Optional: always sample for these users
  end
end
```

---

## 5. Scope Boundaries

**In scope (F-023):**
- E11y::Current.sampled
- TraceContext::Sampler
- Request middleware: parse traceparent, set sampled
- Propagator: use sampled in flags
- Sidekiq/ActiveJob: propagate and restore e11y_sampled
- Sampling middleware: prefer sampled from Current

**Out of scope (deferred):**
- F-009: E11y::Current.baggage
- F-014: tracestate for baggage
- F-008: baggage is separate finding

---

## 6. Testing Strategy

- **Unit:** Sampler.should_sample? with various contexts (parent sampled, no parent, error, debug_user)
- **Unit:** Propagator.build_traceparent uses sampled when set
- **Integration:** Request middleware sets sampled from traceparent; propagates to downstream
- **Integration:** Sidekiq job receives e11y_sampled; server restores it
- **Integration:** Sampling middleware uses E11y::Current.sampled when trace_aware

---

## 7. Approval

Design complete. Ready for implementation plan and execution.
