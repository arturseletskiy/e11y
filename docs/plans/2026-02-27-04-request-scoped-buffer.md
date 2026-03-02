# Request-Scoped Debug Buffering — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that request-scoped debug buffering accumulates events in memory during a request and flushes them to adapters only on request failure — exposing that this core feature is currently non-functional.

**Approach:** Use Rack::Test to make real HTTP requests to the dummy Rails app with request buffering enabled. Check what the memory adapter received after successful vs failed requests. The `flush_event` method in `RequestScopedBuffer` is a complete stub, so flush scenarios will fail.

**Known bugs covered:**
- `RequestBufferConfig.enabled` defaults to `false` — contradicts "automatically captures debug-level events"
- `flush_event(_event_data, target: nil)` in `lib/e11y/buffers/request_scoped_buffer.rb:226` is a stub (empty body + empty `increment_metric`) — buffered events are silently lost on flush
- `increment_metric` inside the buffer is also a stub
- Non-debug events must bypass the buffer — need to verify this path actually works

---

## Task 1: Feature file

**Files:**
- Create: `features/request_scoped_buffer.feature`

**Step 1: Write the feature file**

```gherkin
# features/request_scoped_buffer.feature
@request_buffer
Feature: Request-scoped debug buffering

  # E11y's flagship feature: buffer debug events during a request,
  # flush them to adapters ONLY if the request fails.
  # README: "Buffer debug logs in memory, flush ONLY if request fails"
  # Result: -90% noise, full context on errors.
  #
  # BUG: flush_event in lib/e11y/buffers/request_scoped_buffer.rb:226 is a stub.
  # Buffered events are permanently lost — flush does nothing.

  Background:
    Given the application is running

  Scenario: Request buffering is disabled by default
    # Config: RequestBufferConfig.enabled defaults to false
    # This means the "automatically captures" claim in docs is wrong.
    When I GET "/posts"
    Then request buffering should be disabled in the configuration

  Scenario: Request buffering can be enabled via configuration
    Given request buffering is enabled in the configuration
    Then request buffering should be enabled in the configuration

  @wip
  Scenario: Successful request — debug events are NOT written to adapter
    # With buffering enabled, debug events should be held in memory
    # and discarded (not written) when the request succeeds.
    Given request buffering is enabled in the configuration
    When I GET "/posts"
    Then 0 events with severity "debug" should be in the adapter

  @wip
  Scenario: Failed request — buffered debug events ARE flushed to adapter
    # This is the core feature: on error, all buffered debug events
    # are flushed so developers get full context.
    # BUG: flush_event is a stub — 0 events will appear even after failure.
    Given request buffering is enabled in the configuration
    When I GET "/test_error"
    Then events with severity "debug" should be in the adapter
    And those debug events should have been generated during that request

  @wip
  Scenario: Error-level events bypass the buffer and are written immediately
    # Non-debug events (info, error, fatal) must NOT be buffered —
    # they should reach the adapter immediately regardless of buffer state.
    Given request buffering is enabled in the configuration
    When I GET "/test_error"
    Then at least 1 event with severity "error" should be in the adapter

  @wip
  Scenario: Buffer is cleared after a successful request — no memory leak
    # After a successful request, the per-request buffer must be discarded.
    # A subsequent request should start with a clean buffer.
    Given request buffering is enabled in the configuration
    When I GET "/posts"
    And I GET "/posts" again
    Then the request buffer should be empty between requests
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/request_scoped_buffer.feature --dry-run
```

Expected: all steps pending/undefined.

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/request_scoped_buffer_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/request_scoped_buffer_steps.rb
# frozen_string_literal: true

Then("request buffering should be disabled in the configuration") do
  expect(E11y.configuration.request_buffer.enabled).to be(false),
    "Expected request buffering to be disabled by default, but it was enabled. " \
    "README says 'automatically captures' but config defaults to enabled: false."
end

Given("request buffering is enabled in the configuration") do
  E11y.configuration.request_buffer.enabled = true
end

Then("request buffering should be enabled in the configuration") do
  expect(E11y.configuration.request_buffer.enabled).to be(true)
end

Then("{int} events with severity {string} should be in the adapter") do |count, severity|
  events = memory_adapter.find_events_by_severity(severity.to_sym) rescue
    memory_adapter.events.select { |e| e[:severity].to_s == severity }
  expect(events.size).to eq(count),
    "Expected #{count} #{severity}-severity events in adapter, got #{events.size}. " \
    "BUG: flush_event in RequestScopedBuffer is a stub — buffered events are never written."
end

Then("events with severity {string} should be in the adapter") do |severity|
  events = memory_adapter.events.select { |e| e[:severity].to_s == severity }
  expect(events.size).to be > 0,
    "Expected at least 1 #{severity}-severity event in adapter after failed request, got 0. " \
    "BUG: flush_event stub in lib/e11y/buffers/request_scoped_buffer.rb:226."
end

Then("those debug events should have been generated during that request") do
  events = memory_adapter.events.select { |e| e[:severity].to_s == "debug" }
  expect(events).to all(include(request_id: be_a(String))),
    "Expected flushed debug events to carry a request_id from the failed request."
end

Then("at least {int} event with severity {string} should be in the adapter") do |min, severity|
  events = memory_adapter.events.select { |e| e[:severity].to_s == severity }
  expect(events.size).to be >= min,
    "Expected >= #{min} #{severity}-severity event(s) in adapter, got #{events.size}."
end

When("I GET {string} again") do |path|
  get path
  @last_response = last_response
end

Then("the request buffer should be empty between requests") do
  buffer = Thread.current[:e11y_request_buffer] rescue nil
  expect(buffer.nil? || buffer.empty?).to be(true),
    "Expected request buffer to be cleared after successful request, but it still has events."
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/request_scoped_buffer.feature
```

Expected results:
- `Request buffering is disabled by default` → **PASS**
- `Request buffering can be enabled` → **PASS**
- `@wip` scenarios → **PENDING** (skipped by Cucumber for `@wip` tagged scenarios)

To run wip scenarios explicitly:
```bash
bundle exec cucumber features/request_scoped_buffer.feature --tags @wip
```
Expected: all `@wip` scenarios **FAIL** — core flushing is a stub.

**Step 3: Commit**

```bash
git add features/request_scoped_buffer.feature \
        features/step_definitions/request_scoped_buffer_steps.rb
git commit -m "test(cucumber): request-scoped buffer — flush_event stub exposed as @wip scenarios"
```
