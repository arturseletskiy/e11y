# Trace-Consistent Sampling (F-023) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement ADR-005 §7 trace-consistent sampling — sampling decision at trace entry, propagated via HTTP and jobs.

**Architecture:** Sampler at trace entry; E11y::Current.sampled; Propagator and job middleware propagate/restore.

**Tech Stack:** Ruby, Rack, W3C Trace Context, Sidekiq, ActiveJob.

---

## Task 1: Extend TracingConfig with sampling options

**Files:**
- Modify: `lib/e11y.rb` (TracingConfig class, ~745–756)

**Step 1: Add sampling attributes to TracingConfig**

Add to TracingConfig:
```ruby
def initialize
  @source = :e11y
  @default_sample_rate = 0.1
  @respect_parent_sampling = true
  @per_event_sample_rates = {}
  @debug_users = []
end

def default_sample_rate(value = nil)
  return @default_sample_rate if value.nil?
  @default_sample_rate = value.to_f
end

def respect_parent_sampling(value = nil)
  return @respect_parent_sampling if value.nil?
  @respect_parent_sampling = value
end

def per_event_sample_rates(&block)
  return @per_event_sample_rates unless block_given?
  dsl = Class.new do
    attr_reader :rates
    def initialize; @rates = {}; end
    def event(name, sample_rate:); @rates[name.to_s] = sample_rate.to_f; end
  end.new
  dsl.instance_eval(&block)
  @per_event_sample_rates = dsl.rates
end

def debug_users(ids = nil)
  return @debug_users if ids.nil?
  @debug_users = Array(ids)
end
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/ --tag ~integration 2>/dev/null | tail -5`
Expected: No regressions.

**Step 3: Commit**

```bash
git add lib/e11y.rb
git commit -m "feat(tracing): add sampling config to TracingConfig (F-023)"
```

---

## Task 2: Add E11y::Current.sampled attribute

**Files:**
- Modify: `lib/e11y/current.rb`

**Step 1: Add attribute**

Add `attribute :sampled` after existing attributes (around line 44).

**Step 2: Run tests**

Run: `bundle exec rspec spec/ -e "Current" --tag ~integration 2>/dev/null | tail -5`
Expected: PASS.

**Step 3: Commit**

```bash
git add lib/e11y/current.rb
git commit -m "feat(current): add sampled attribute for trace-consistent sampling (F-023)"
```

---

## Task 3: Create E11y::TraceContext::Sampler

**Files:**
- Create: `lib/e11y/trace_context/sampler.rb`
- Create: `spec/e11y/trace_context/sampler_spec.rb`

**Step 1: Create Sampler class**

```ruby
# frozen_string_literal: true

module E11y
  module TraceContext
    # Trace entry sampler (ADR-005 §7).
    # Decides if trace should be sampled; respects parent decision when configured.
    class Sampler
      class << self
        def should_sample?(context = {})
          cfg = E11y.config&.tracing
          respect = cfg&.respect_parent_sampling != false

          return context[:sampled] if respect && context.key?(:sampled)

          rate = determine_sample_rate(context, cfg)
          rand < rate
        end

        private

        def determine_sample_rate(context, cfg)
          return 1.0 if context[:error]
          return 1.0 if cfg&.debug_users&.include?(context[:user_id])

          if context[:event_name] && cfg&.per_event_sample_rates
            rate = cfg.per_event_sample_rates[context[:event_name].to_s]
            return rate if rate
          end

          (cfg&.default_sample_rate || 0.1).to_f
        end
      end
    end
  end
end
```

**Step 2: Write unit test**

Create sampler_spec.rb with tests for: respect parent, ignore parent, error, debug_users, per_event_sample_rates.

**Step 3: Run test**

Run: `bundle exec rspec spec/e11y/trace_context/sampler_spec.rb`
Expected: PASS.

**Step 4: Commit**

```bash
git add lib/e11y/trace_context/sampler.rb spec/e11y/trace_context/sampler_spec.rb
git commit -m "feat(trace_context): add Sampler for trace entry (F-023)"
```

---

## Task 4: Request middleware — parse traceparent, set sampled

**Files:**
- Modify: `lib/e11y/middleware/request.rb`

**Step 1: Update extract logic**

- Use `Propagator.parse(traceparent)` when traceparent present; get `{ trace_id:, parent_span_id:, sampled: }`
- If parsed: set `E11y::Current.sampled = parsed[:sampled]`
- If no traceparent: call `E11y::TraceContext::Sampler.should_sample?({ trace_id:, span_id:, user_id: })` and set
- Refactor extract_trace_id to return parsed hash or nil

**Step 2: Run tests**

Run: `bundle exec rspec spec/e11y/middleware/request_spec.rb spec/integration/`
Expected: PASS.

**Step 3: Commit**

```bash
git add lib/e11y/middleware/request.rb
git commit -m "feat(request): parse traceparent sampled, set E11y::Current.sampled (F-023)"
```

---

## Task 5: Propagator — use E11y::Current.sampled in traceparent

**Files:**
- Modify: `lib/e11y/tracing/propagator.rb`

**Step 1: Update build_traceparent**

```ruby
sampled = E11y::Current.respond_to?(:sampled) ? E11y::Current.sampled : true
flags = (sampled != false) ? "01" : "00"
"#{TRACEPARENT_VERSION}-#{t_id}-#{s_id}-#{flags}"
```

**Step 2: Run tests**

Run: `bundle exec rspec spec/e11y/tracing/ spec/integration/`
Expected: PASS.

**Step 3: Commit**

```bash
git add lib/e11y/tracing/propagator.rb
git commit -m "feat(propagator): use E11y::Current.sampled in traceparent flags (F-023)"
```

---

## Task 6: Sidekiq — propagate and restore e11y_sampled

**Files:**
- Modify: `lib/e11y/instruments/sidekiq.rb`

**Step 1: ClientMiddleware** — add `job["e11y_sampled"] = E11y::Current.sampled` when set

**Step 2: ServerMiddleware setup_job_context** — restore `E11y::Current.sampled = job["e11y_sampled"]` if present; else call Sampler

**Step 3: Run tests**

Run: `bundle exec rspec spec/e11y/instruments/sidekiq_spec.rb spec/integration/`
Expected: PASS.

**Step 4: Commit**

```bash
git add lib/e11y/instruments/sidekiq.rb
git commit -m "feat(sidekiq): propagate and restore e11y_sampled (F-023)"
```

---

## Task 7: ActiveJob — propagate and restore e11y_sampled

**Files:**
- Modify: `lib/e11y/instruments/active_job.rb`

**Step 1: Add e11y_sampled to TraceAttributes**

**Step 2: before_enqueue** — set `job.e11y_sampled = E11y::Current.sampled`

**Step 3: setup_job_context_active_job** — restore sampled; else call Sampler

**Step 4: Run tests**

Run: `bundle exec rspec spec/e11y/instruments/active_job_spec.rb spec/integration/`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/e11y/instruments/active_job.rb
git commit -m "feat(active_job): propagate and restore e11y_sampled (F-023)"
```

---

## Task 8: Sampling middleware — prefer E11y::Current.sampled

**Files:**
- Modify: `lib/e11y/middleware/sampling.rb`

**Step 1: Update should_sample?**

When `@trace_aware && event_data[:trace_id]`:
- If `E11y::Current.respond_to?(:sampled) && !E11y::Current.sampled.nil?` → return `E11y::Current.sampled`
- Else → existing `trace_sampling_decision` logic

**Step 2: Run tests**

Run: `bundle exec rspec spec/e11y/middleware/sampling_spec.rb spec/integration/sampling_integration_spec.rb`
Expected: PASS.

**Step 3: Commit**

```bash
git add lib/e11y/middleware/sampling.rb
git commit -m "feat(sampling): prefer E11y::Current.sampled when trace_aware (F-023)"
```

---

## Task 9: Integration tests for trace-consistent sampling

**Files:**
- Create: `spec/integration/trace_consistent_sampling_integration_spec.rb`

**Step 1: Write integration tests**

- Request: traceparent with sampled=0 → events dropped when trace_aware
- Request: traceparent with sampled=1 → events pass
- Propagator: E11y::Current.sampled=false → traceparent flags 00
- Sidekiq: e11y_sampled in metadata → restored in job context

**Step 2: Run integration suite**

Run: `bundle exec rspec spec/integration/ --tag integration`
Expected: PASS.

**Step 3: Commit**

```bash
git add spec/integration/trace_consistent_sampling_integration_spec.rb
git commit -m "test: integration tests for trace-consistent sampling (F-023)"
```

---

## Task 10: Update FINAL-ADR-IMPLEMENTATION-REPORT

**Files:**
- Modify: `docs/analysis/FINAL-ADR-IMPLEMENTATION-REPORT.md`

**Step 1: Mark F-023 resolved**

Change F-023 row to: `| F-023 | Trace-consistent sampling (§7) — RESOLVED. |`

**Step 2: Commit**

```bash
git add docs/analysis/FINAL-ADR-IMPLEMENTATION-REPORT.md
git commit -m "docs: mark F-023 trace-consistent sampling as resolved"
```

---

## Execution Handoff

**Plan complete and saved to `docs/plans/2026-03-13-trace-consistent-sampling-plan.md`.**

**Two execution options:**

1. **Subagent-Driven (this session)** — Dispatch fresh subagent per task, review between tasks, fast iteration
2. **Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
