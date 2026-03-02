# Adaptive Sampling — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify adaptive sampling behavior end-to-end against the dummy Rails app, including known off-by-one and trace-consistency bugs.

**Approach:** Scenarios drive HTTP requests through the dummy app via `Rack::Test` (reusing the `spec/dummy` Rails app bootstrapped in `features/support/env.rb`). The `E11y.config.adapters[:memory]` adapter is the sole observation point. For load-level and threshold tests the `E11y::Sampling::LoadMonitor` class is manipulated directly inside step definitions — it is public API. For each statistical sampling scenario, 100 requests are made and the count is asserted within a tolerance band.

**Known bugs covered:**
- `LoadMonitor#load_level` off-by-one: when rate is exactly at the `normal` threshold (e.g. 100 events/sec with the default threshold of 1 000), the final `elsif rate >= @thresholds[:normal]` branch returns `:high` instead of `:normal` (line 104-105 of `lib/e11y/sampling/load_monitor.rb`). This makes `recommended_sample_rate` return `0.5` instead of `1.0` at normal load.
- Consequence of the above: events tracked at exactly the normal threshold are sampled at 50 % rather than 100 %.
- `cleanup_trace_decisions` in `lib/e11y/middleware/sampling.rb` (lines 269-272) evicts a random 50 % of the `@trace_decisions` hash, which can remove the decision for an in-flight trace, causing subsequent events from the same trace to receive an independent (potentially different) sampling decision.

---

## Files to create

| File | Purpose |
|------|---------|
| `features/adaptive_sampling.feature` | 8 Gherkin scenarios |
| `features/step_definitions/sampling_steps.rb` | Step definitions |

---

## Task 1 — Write the feature file

### Step 1: Create `features/adaptive_sampling.feature`

```gherkin
# features/adaptive_sampling.feature
Feature: Adaptive Sampling

  Background:
    Given the memory adapter is cleared
    And E11y is configured with the memory adapter as fallback
    And the Sampling middleware is reconfigured with trace_aware false and default_sample_rate 1.0

  # -----------------------------------------------------------------------
  # Scenario 1: sample_rate 1.0 always tracked
  # -----------------------------------------------------------------------
  Scenario: Events with sample_rate 1.0 are always tracked
    Given an event class "Events::AlwaysTracked" with sample_rate 1.0
    When I track 100 "Events::AlwaysTracked" events
    Then the memory adapter should contain exactly 100 "Events::AlwaysTracked" events

  # -----------------------------------------------------------------------
  # Scenario 2: sample_rate 0.0 never tracked
  # -----------------------------------------------------------------------
  Scenario: Events with sample_rate 0.0 are never tracked
    Given an event class "Events::NeverTracked" with sample_rate 0.0
    When I track 100 "Events::NeverTracked" events
    Then the memory adapter should contain exactly 0 "Events::NeverTracked" events

  # -----------------------------------------------------------------------
  # Scenario 3 (@wip): LoadMonitor returns :normal at exactly the normal threshold
  # Bug: load_level returns :high when rate == thresholds[:normal]
  # -----------------------------------------------------------------------
  @wip
  Scenario: Load at exactly normal threshold produces :normal load level
    Given a LoadMonitor with normal threshold 100 events per second and window 1 second
    When I record exactly 100 events in 1 second in the LoadMonitor
    Then the LoadMonitor load_level should be :normal

  # -----------------------------------------------------------------------
  # Scenario 4 (@wip): Normal-threshold load yields 100 % sampling
  # Depends on scenario 3 bug: :high returned instead of :normal → 50 % rate
  # -----------------------------------------------------------------------
  @wip
  Scenario: Load at normal threshold results in 100% sampling rate
    Given a LoadMonitor with normal threshold 100 events per second and window 1 second
    When I record exactly 100 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be 1.0

  # -----------------------------------------------------------------------
  # Scenario 5: High load yields reduced sampling
  # -----------------------------------------------------------------------
  Scenario: Load above high threshold results in reduced sampling rate
    Given a LoadMonitor with normal threshold 10, high threshold 50 events per second and window 1 second
    When I record 60 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be less than 1.0

  # -----------------------------------------------------------------------
  # Scenario 6: Critical (overload) load yields lowest sampling
  # -----------------------------------------------------------------------
  Scenario: Load at overload threshold results in 1% sampling rate
    Given a LoadMonitor with normal threshold 10, high threshold 50, very_high threshold 100, overload threshold 200 events per second and window 1 second
    When I record 250 events in 1 second in the LoadMonitor
    Then the LoadMonitor recommended_sample_rate should be 0.01

  # -----------------------------------------------------------------------
  # Scenario 7: Error spike increases sample rate for affected event type
  # -----------------------------------------------------------------------
  Scenario: Error spike detection activates 100% sampling across all event types
    Given the Sampling middleware is reconfigured with error_based_adaptive true and default_sample_rate 0.1
    And an event class "Events::OrderForSpike" with sample_rate 0.1
    When I send 15 GET requests to "/test_error"
    Then the error spike detector should be active
    When I track 20 "Events::OrderForSpike" events
    Then the memory adapter should contain exactly 20 "Events::OrderForSpike" events

  # -----------------------------------------------------------------------
  # Scenario 8 (@wip): Same trace_id gets consistent sampling decision
  # Bug: cleanup_trace_decisions randomly evicts 50% of cache keys,
  # potentially evicting an active trace and breaking consistency.
  # -----------------------------------------------------------------------
  @wip
  Scenario: Events from the same trace_id receive consistent sampling decisions
    Given the Sampling middleware is reconfigured with trace_aware true and default_sample_rate 0.5
    And an event class "Events::TracedOrder" with sample_rate 0.5
    And the trace decisions cache is filled with 1001 dummy entries to trigger cleanup
    When I set the current trace_id to "cucumber-trace-consistency-test"
    And I track 50 "Events::TracedOrder" events
    Then all 50 "Events::TracedOrder" events should have the same sampling outcome
```

### Step 2: Run to confirm all scenarios fail or are pending

```bash
bundle exec cucumber features/adaptive_sampling.feature
```

Expected: Scenarios 1, 2, 5, 6, 7 fail with undefined steps. Scenarios 3, 4, 8 are tagged `@wip` and should be skipped unless `--tags @wip` is passed.

### Step 3: Create `features/step_definitions/sampling_steps.rb`

```ruby
# features/step_definitions/sampling_steps.rb
# frozen_string_literal: true

require "e11y"
require "e11y/sampling/load_monitor"
require "e11y/sampling/error_spike_detector"
require "e11y/middleware/sampling"
require "e11y/pipeline/builder"

# ---------------------------------------------------------------------------
# Background / setup steps
# ---------------------------------------------------------------------------

Given("the memory adapter is cleared") do
  E11y.config.adapters[:memory] ||= E11y::Adapters::InMemory.new(max_events: nil)
  E11y.config.adapters[:memory].clear!
end

Given("E11y is configured with the memory adapter as fallback") do
  E11y.config.adapters[:memory] ||= E11y::Adapters::InMemory.new(max_events: nil)
  E11y.config.adapters[:logs]   = E11y.config.adapters[:memory]
  E11y.config.fallback_adapters = [:memory]
  # Invalidate cached pipeline
  E11y.config.instance_variable_set(:@built_pipeline, nil)
end

Given("the Sampling middleware is reconfigured with trace_aware false and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(
    default_sample_rate: rate,
    trace_aware: false
  )
end

Given("the Sampling middleware is reconfigured with error_based_adaptive true and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(
    default_sample_rate: rate,
    trace_aware: false,
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 10,   # 10 errors/min triggers spike
      relative_threshold: 3.0,
      spike_duration: 300
    }
  )
end

Given("the Sampling middleware is reconfigured with trace_aware true and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(
    default_sample_rate: rate,
    trace_aware: true
  )
end

# ---------------------------------------------------------------------------
# Event-class creation
# ---------------------------------------------------------------------------

Given("an event class {string} with sample_rate {float}") do |class_name, rate|
  # Resolve nested constant name like "Events::AlwaysTracked"
  parts   = class_name.split("::")
  parent  = parts[0..-2].reduce(Object) { |mod, part| ensure_module(mod, part) }
  name    = parts.last

  unless parent.const_defined?(name, false)
    klass = Class.new(E11y::Event::Base) do
      sample_rate rate
      validation_mode :never  # avoid schema errors for attribute-less event
      adapters []
    end
    parent.const_set(name, klass)
  end
end

# ---------------------------------------------------------------------------
# Tracking helpers
# ---------------------------------------------------------------------------

When("I track {int} {string} events") do |count, class_name|
  klass = class_name.split("::").reduce(Object, :const_get)
  count.times { |i| klass.track(seq: i) }
end

When("I track {int} {string} events and record them") do |count, class_name|
  klass = class_name.split("::").reduce(Object, :const_get)
  count.times { |i| klass.track(seq: i) }
end

# ---------------------------------------------------------------------------
# HTTP requests (error spike triggering)
# ---------------------------------------------------------------------------

When("I send {int} GET requests to {string}") do |count, path|
  # Use Rack::Test against the dummy Rails app
  app = Rails.application
  count.times do
    begin
      env = Rack::MockRequest.env_for(path, method: "GET")
      app.call(env)
    rescue StandardError
      # The /test_error route raises — that is exactly what we want
    end
  end
end

# ---------------------------------------------------------------------------
# Memory adapter assertions
# ---------------------------------------------------------------------------

Then("the memory adapter should contain exactly {int} {string} events") do |count, class_name|
  adapter = E11y.config.adapters[:memory]
  events  = adapter.events.select do |e|
    e[:event_name].to_s == class_name ||
      e[:event_class]&.name == class_name
  end
  expect(events.size).to eq(count),
    "Expected #{count} #{class_name} events in memory adapter, got #{events.size}"
end

# ---------------------------------------------------------------------------
# LoadMonitor steps
# ---------------------------------------------------------------------------

Given("a LoadMonitor with normal threshold {int} events per second and window {int} second") do |normal, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: normal * 5, very_high: normal * 10, overload: normal * 20 }
  )
end

Given("a LoadMonitor with normal threshold {int}, high threshold {int} events per second and window {int} second") do |normal, high, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: high, very_high: high * 2, overload: high * 4 }
  )
end

Given("a LoadMonitor with normal threshold {int}, high threshold {int}, very_high threshold {int}, overload threshold {int} events per second and window {int} second") do |normal, high, very_high, overload, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: high, very_high: very_high, overload: overload }
  )
end

When("I record exactly {int} events in {int} second in the LoadMonitor") do |count, _window|
  # Inject events with timestamps within the window so rate == count/window
  now = Time.now
  @load_monitor.instance_variable_get(:@mutex).synchronize do
    count.times do |i|
      @load_monitor.instance_variable_get(:@events) << (now - (0.5 * i.to_f / count))
    end
  end
end

When("I record {int} events in {int} second in the LoadMonitor") do |count, _window|
  now = Time.now
  @load_monitor.instance_variable_get(:@mutex).synchronize do
    count.times do |i|
      @load_monitor.instance_variable_get(:@events) << (now - (0.9 * i.to_f / count))
    end
  end
end

Then("the LoadMonitor load_level should be :normal") do
  level = @load_monitor.load_level
  expect(level).to eq(:normal),
    "Expected LoadMonitor#load_level to be :normal but got :#{level}. " \
    "Known bug: when rate == thresholds[:normal], load_monitor.rb line 104-105 " \
    "returns :high instead of :normal."
end

Then("the LoadMonitor recommended_sample_rate should be {float}") do |expected_rate|
  rate = @load_monitor.recommended_sample_rate
  expect(rate).to eq(expected_rate),
    "Expected recommended_sample_rate #{expected_rate} but got #{rate}. " \
    "Known bug: off-by-one in load_level causes 50% rate at normal load."
end

Then("the LoadMonitor recommended_sample_rate should be less than {float}") do |threshold|
  rate = @load_monitor.recommended_sample_rate
  expect(rate).to be < threshold,
    "Expected recommended_sample_rate < #{threshold} but got #{rate}"
end

# ---------------------------------------------------------------------------
# Error spike detection assertion
# ---------------------------------------------------------------------------

Then("the error spike detector should be active") do
  # Reach into the pipeline to find the Sampling middleware instance
  pipeline = E11y.config.built_pipeline
  sampling = find_middleware_in_chain(pipeline, E11y::Middleware::Sampling)
  expect(sampling).not_to be_nil, "Sampling middleware not found in pipeline"

  detector = sampling.instance_variable_get(:@error_spike_detector)
  expect(detector).not_to be_nil, "Error spike detector not initialised"
  expect(detector.error_spike?).to be(true),
    "Expected error spike to be active after sending 15 error requests"
end

# ---------------------------------------------------------------------------
# Trace consistency steps
# ---------------------------------------------------------------------------

Given("the trace decisions cache is filled with {int} dummy entries to trigger cleanup") do |count|
  pipeline  = E11y.config.built_pipeline
  sampling  = find_middleware_in_chain(pipeline, E11y::Middleware::Sampling)
  expect(sampling).not_to be_nil

  decisions = sampling.instance_variable_get(:@trace_decisions)
  mutex     = sampling.instance_variable_get(:@trace_decisions_mutex)
  mutex.synchronize do
    count.times { |i| decisions["dummy-trace-#{i}"] = i.even? }
  end
end

When("I set the current trace_id to {string}") do |trace_id|
  E11y::Current.trace_id = trace_id
end

Then("all {int} {string} events should have the same sampling outcome") do |count, class_name|
  adapter = E11y.config.adapters[:memory]
  events  = adapter.events.select do |e|
    e[:event_name].to_s == class_name || e[:event_class]&.name == class_name
  end
  actual = events.size
  expect(actual).to be_in([0, count]),
    "Expected all #{count} #{class_name} events to have the same outcome " \
    "(either all 0 or all #{count}), got #{actual}. " \
    "Known bug: cleanup_trace_decisions in sampling.rb randomly evicts 50% of cache " \
    "keys, breaking trace-level consistency."
end

# ---------------------------------------------------------------------------
# Private helpers (accessible within World via module)
# ---------------------------------------------------------------------------

module SamplingStepHelpers
  def reconfigure_sampling_middleware(options)
    cfg = E11y.config
    cfg.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

    insert_index = pipeline_insert_index(cfg)
    cfg.pipeline.middlewares.insert(
      insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Sampling,
        args: [],
        options: options
      )
    )
    cfg.instance_variable_set(:@built_pipeline, nil)
  end

  def pipeline_insert_index(cfg)
    idx = cfg.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
    idx ? idx + 1 : cfg.pipeline.middlewares.size
  end

  def find_middleware_in_chain(pipeline, klass)
    node = pipeline
    while node && !node.is_a?(Proc)
      return node if node.is_a?(klass)

      node = node.instance_variable_get(:@app)
    end
    nil
  end

  def ensure_module(parent, name)
    return parent.const_get(name) if parent.const_defined?(name, false)

    mod = Module.new
    parent.const_set(name, mod)
    mod
  end
end

World(SamplingStepHelpers)
```

### Step 4: Run the full feature

```bash
bundle exec cucumber features/adaptive_sampling.feature
```

Expected results:
- Scenarios 1 and 2 (sample_rate 1.0 and 0.0): PASS
- Scenario 3 `@wip` (load level off-by-one): FAIL when run with `--tags @wip`
- Scenario 4 `@wip` (sample rate at normal threshold): FAIL when run with `--tags @wip`
- Scenario 5 (high load → reduced rate): PASS
- Scenario 6 (overload → 1 %): PASS
- Scenario 7 (error spike → 100 %): PASS
- Scenario 8 `@wip` (trace consistency after cache eviction): FAIL when run with `--tags @wip`

Run WIP scenarios explicitly to confirm they fail:

```bash
bundle exec cucumber features/adaptive_sampling.feature --tags @wip
```

### Step 5: Commit

```bash
git add features/adaptive_sampling.feature features/step_definitions/sampling_steps.rb
git commit -m "test(cucumber): adaptive sampling QA scenarios including @wip load-level and trace-consistency bugs"
```

---

## Implementation notes

### Bug reproduction for Scenario 3 and 4

The `load_level` method in `lib/e11y/sampling/load_monitor.rb` has the following structure (lines 92-110):

```ruby
def load_level
  rate = current_rate
  if rate >= @thresholds[:overload]
    :overload
  elsif rate >= @thresholds[:very_high]
    :very_high
  elsif rate >= @thresholds[:high]
    :high
  elsif rate >= @thresholds[:normal]
    :high  # BUG: should be :normal
  else
    :normal
  end
end
```

When `rate == thresholds[:normal]` (e.g. exactly 100 rps with threshold 100), the penultimate branch matches and returns `:high`. The comment says "Values between normal and high thresholds intentionally mapped to :high" — but a rate **exactly at** the normal threshold should be `:normal`, not `:high`. Scenario 3 calls `load_level` directly with a rate injected at exactly the threshold; Scenario 4 checks that `recommended_sample_rate` returns `1.0` instead of `0.5`.

### Bug reproduction for Scenario 8

`cleanup_trace_decisions` in `lib/e11y/middleware/sampling.rb` (lines 269-272):

```ruby
def cleanup_trace_decisions
  keys_to_remove = @trace_decisions.keys.sample(@trace_decisions.size / 2)
  keys_to_remove.each { |key| @trace_decisions.delete(key) }
end
```

This is called **inside** `trace_sampling_decision` when `@trace_decisions.size > 1000`. The step pre-fills the cache with 1001 dummy entries so the next call triggers cleanup. The cleanup can delete the key for the active trace (`"cucumber-trace-consistency-test"`), causing its next lookup to generate a fresh random decision instead of returning the cached one. Scenario 8 sends 50 events on the same trace; if cleanup fires mid-batch, some will be sampled and some not.

### How to query events by class name

The memory adapter's `find_events` method matches on `event_name` (string). After the Versioning middleware the name is a dot-separated snake_case string (e.g. `"events.always_tracked"`). Without Versioning middleware, `event_name` is the class name string. The step definitions in this plan match on **both** `event[:event_name]` and `event[:event_class]&.name` to be version-agnostic.
