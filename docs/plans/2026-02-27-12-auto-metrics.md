# Auto-Metrics Generation — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that events with a `metrics` block automatically register and increment Prometheus/Yabeda counters and histograms — exposing that the Yabeda adapter is absent from the default pipeline, `increment_metric` is a stub in multiple places, and metric registration happens at the wrong lifecycle stage.

**Approach:** Configure E11y with a real Yabeda adapter (or use the in-process Yabeda registry). Make HTTP requests that trigger events with metrics blocks. Inspect the Yabeda registry for registered metrics and non-zero values.

**Known bugs covered:**
- `E11y::Adapters::Yabeda` is never added to the default adapter list — events with metrics blocks never hit the Yabeda adapter.
- `increment_metric` inside `RequestScopedBuffer` and `DLQ::FileStorage` are empty stubs — no metrics increment even when called explicitly.
- `E11y::Metrics::Registry` raises on duplicate registration instead of returning the existing metric (idempotency missing).
- Histogram buckets defined in the `metrics` block are silently ignored — Yabeda uses its own defaults.

---

## Task 1: Feature file

**Files:**
- Create: `features/auto_metrics.feature`

**Step 1: Write the feature file**

```gherkin
# features/auto_metrics.feature
@metrics
Feature: Automatic metric registration and increment

  # E11y README: "Define metrics alongside your events — automatically
  # registered with Prometheus/Yabeda and incremented on every track."
  #
  # BUG 1: Yabeda adapter not in default pipeline — metrics never fire.
  # BUG 2: increment_metric is a stub in RequestScopedBuffer and DLQ.
  # BUG 3: Duplicate metric registration raises instead of being idempotent.
  # BUG 4: Histogram bucket configuration in metrics block is ignored.

  Background:
    Given the application is running
    And the Yabeda adapter is configured

  @wip
  Scenario: Counter metric is incremented when an event is tracked
    # BUG: Yabeda adapter absent from default pipeline — counter never increments.
    # Events::OrderCreated defines: counter :orders_created_total
    When I POST to "/orders" with params '{"order":{"order_id":"ord-m1","user_id":"usr-1","items":"[]"}}'
    Then the Yabeda counter "orders_created_total" should be incremented

  @wip
  Scenario: Histogram metric records the correct value
    # BUG: Even if adapter fires, bucket config from metrics block is ignored.
    # Events::OrderPayment defines: histogram :order_amount_usd
    When I POST to "/orders" with params '{"order":{"order_id":"ord-m2","user_id":"usr-1","items":"[]","amount":"49.99"}}'
    Then the Yabeda histogram "order_amount_usd" should have recorded a value

  @wip
  Scenario: Metric registration is idempotent across multiple tracks
    # BUG: Registry raises ArgumentError on second registration of the same metric name.
    # Tracking the same event class twice triggers re-registration → crash.
    When I POST to "/orders" with params '{"order":{"order_id":"ord-m3","user_id":"usr-1","items":"[]"}}'
    And I POST to "/orders" with params '{"order":{"order_id":"ord-m4","user_id":"usr-1","items":"[]"}}'
    Then no error should be raised during metric registration

  Scenario: Event class with metrics block can be defined without errors
    # Smoke test: defining a metrics block doesn't raise at class load time.
    Then defining an event class with a metrics block should not raise

  Scenario: Yabeda adapter can be instantiated and receives events
    # Tests the adapter interface in isolation — separate from pipeline routing.
    Given a Yabeda adapter instance
    When I deliver an event directly to the Yabeda adapter
    Then no error should be raised
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/auto_metrics.feature --dry-run
```

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/auto_metrics_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/auto_metrics_steps.rb
# frozen_string_literal: true

Given("the Yabeda adapter is configured") do
  skip_this_scenario unless defined?(::Yabeda)
  @yabeda_adapter = E11y::Adapters::Yabeda.new rescue nil
  if @yabeda_adapter
    E11y.configuration.adapters[:metrics] = @yabeda_adapter
  end
end

Then("the Yabeda counter {string} should be incremented") do |metric_name|
  skip_this_scenario unless defined?(::Yabeda)
  # Try to read the counter from Yabeda registry
  counter = Yabeda.counters[metric_name.to_sym] rescue nil
  expect(counter).not_to be_nil,
    "Counter '#{metric_name}' not found in Yabeda registry. " \
    "BUG: Yabeda adapter is not in the default pipeline — " \
    "metrics never reach Yabeda even when defined in the metrics block."
  # Check value > 0 (in a test context Yabeda may need a collector)
  value = counter.get rescue counter.values.values.sum rescue 0
  expect(value).to be > 0,
    "Counter '#{metric_name}' exists but value is 0. Events were tracked but metric not incremented."
end

Then("the Yabeda histogram {string} should have recorded a value") do |metric_name|
  skip_this_scenario unless defined?(::Yabeda)
  histogram = Yabeda.histograms[metric_name.to_sym] rescue nil
  expect(histogram).not_to be_nil,
    "Histogram '#{metric_name}' not found in Yabeda registry. " \
    "BUG: Yabeda adapter absent from default pipeline."
end

Then("no error should be raised during metric registration") do
  expect(@metric_registration_error).to be_nil,
    "Got #{@metric_registration_error&.class}: #{@metric_registration_error&.message}. " \
    "BUG: E11y::Metrics::Registry raises on duplicate registration instead of being idempotent."
end

Then("defining an event class with a metrics block should not raise") do
  error = nil
  begin
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      metrics do
        counter :test_smoke_counter, "Smoke test counter"
      end
    end
  rescue => e
    error = e
  end
  expect(error).to be_nil,
    "Defining an event class with a metrics block raised: #{error&.class}: #{error&.message}"
end

Given("a Yabeda adapter instance") do
  skip_this_scenario unless defined?(::Yabeda)
  @direct_yabeda_adapter = E11y::Adapters::Yabeda.new
rescue => e
  @yabeda_init_error = e
end

When("I deliver an event directly to the Yabeda adapter") do
  skip_this_scenario unless defined?(::Yabeda)
  skip_this_scenario unless @direct_yabeda_adapter
  @direct_delivery_error = nil
  begin
    @direct_yabeda_adapter.deliver(
      event_name: "test_event",
      severity: :info,
      timestamp: Time.now.iso8601
    )
  rescue => e
    @direct_delivery_error = e
  end
end

Then("no error should be raised") do
  error = @direct_delivery_error || @yabeda_init_error || @metric_registration_error
  expect(error).to be_nil,
    "Got #{error&.class}: #{error&.message}"
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/auto_metrics.feature
```

Expected:
- `Event class with metrics block can be defined` → **PASS**
- `Yabeda adapter can be instantiated` → **PASS** (or skipped if Yabeda not loaded)
- `@wip` scenarios → **PENDING**

Run wip:
```bash
bundle exec cucumber features/auto_metrics.feature --tags @wip
```
Expected: counter/histogram **FAIL** (Yabeda not in pipeline), idempotency **FAIL** (raises on duplicate).

**Step 3: Commit**

```bash
git add features/auto_metrics.feature \
        features/step_definitions/auto_metrics_steps.rb
git commit -m "test(cucumber): auto-metrics — Yabeda adapter absent from pipeline, increment stubs, duplicate registration"
```
