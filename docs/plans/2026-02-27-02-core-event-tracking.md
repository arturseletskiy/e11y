# Core Event Tracking API — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that events are correctly tracked through the dummy app's HTTP endpoints and that known gaps in the public API surface are caught by tagged scenarios.

**Approach:** Every scenario makes one or more real HTTP requests via `Rack::Test` to the dummy Rails app, then inspects what the `E11y.config.adapters[:memory]` instance captured. No mocking of the E11y pipeline is used. The full middleware stack (TraceContext → Validation → PIIFilter → AuditSigning → Sampling → Routing) runs for every request, exactly as it would in production. Because the dummy app's pipeline is configured with `default_sample_rate: 1.0` and all severity rates set to `1.0`, every event produced during a test request is guaranteed to land in the memory adapter.

**Known bugs covered:**
- `E11y.track(event_instance)` raises `NotImplementedError` at `lib/e11y.rb:68` — the README documents this as the primary entry point for the library but it is completely unimplemented. The `@wip` scenario in this plan calls the method directly from a custom route and captures the exception.
- The public-API discrepancy: `EventClass.track(**payload)` works correctly while `E11y.track(instance)` does not. This plan documents both behaviors.

---

## Files to create

```
features/event_tracking.feature
features/step_definitions/event_tracking_steps.rb
```

Prerequisites: Plan 01 (Cucumber Infrastructure) must be complete.

---

## Task 1 — Write `features/event_tracking.feature`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/event_tracking.feature`

### Step 1 — Write the feature file

```gherkin
# features/event_tracking.feature
#
# Verifies the core event tracking API:
#   - EventClass.track(**payload) — the working path
#   - E11y.track(event_instance)  — @wip: currently raises NotImplementedError
#   - Schema field capture in the memory adapter
#   - No phantom events on failed Rails validations
#   - Error-level events on unhandled exceptions
#
# Tag legend:
#   @wip  — scenario exposes a known bug; expected to FAIL until the bug is fixed.
#           Run: bundle exec rake cucumber:wip

Feature: Core event tracking API

  Background:
    Given the application is running

  # ---------------------------------------------------------------------------
  # @wip — BUG: E11y.track(instance) raises NotImplementedError
  #
  # The README Quick Start shows:
  #   E11y.track(Events::UserSignup.new(user_id: 123))
  #
  # In reality lib/e11y.rb:66-68 contains:
  #   def track(event)
  #     raise NotImplementedError, "E11y.track will be implemented in Phase 1"
  #   end
  #
  # Expected (when fixed): the event reaches the memory adapter without error.
  # Actual (current):       NotImplementedError is raised before any adapter is called.
  # ---------------------------------------------------------------------------
  @wip
  Scenario: Calling E11y.track with an event instance delivers the event
    Given the application is running
    When I call E11y.track with a new Events::OrderCreated instance
    Then no exception should have been raised
    And 1 event of type "Events::OrderCreated" should have been tracked

  # ---------------------------------------------------------------------------
  # Happy path — EventClass.track works correctly
  # ---------------------------------------------------------------------------
  Scenario: POST /orders tracks an Events::OrderCreated event via EventClass.track
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked

  Scenario: Tracked event payload contains the submitted fields
    When I POST to "/orders" with order params:
      | order[status]   | confirmed |
      | order[order_id] | ord-99    |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event's field "status" should equal "confirmed"

  Scenario: Tracked event has required metadata fields set by middleware
    When I POST to "/orders" with order params:
      | order[status] | pending |
    Then the response status should be 201
    And 1 event of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event has a non-nil timestamp
    And the last "Events::OrderCreated" event has a non-nil severity

  Scenario: POST /users with valid params tracks a UserRegistered event
    When I POST to "/users" with user params:
      | user[email]                 | alice@example.com |
      | user[password]              | s3cr3t            |
      | user[password_confirmation] | s3cr3t            |
      | user[name]                  | Alice             |
    Then the response status should be 201
    And 1 event of type "Events::UserRegistered" should have been tracked

  Scenario: Multiple sequential requests each track one event
    When I POST to "/orders" with order params:
      | order[status] | pending |
    And I POST to "/orders" with order params:
      | order[status] | confirmed |
    Then 2 events of type "Events::OrderCreated" should have been tracked

  # ---------------------------------------------------------------------------
  # No phantom events on Rails validation failure
  # The PostsController does NOT track any E11y event on its own —
  # it uses standard ActiveRecord validation. A missing required field
  # should return 422 and produce zero E11y events.
  # ---------------------------------------------------------------------------
  Scenario: POST /posts with a missing required title returns 422 and tracks no event
    When I POST to "/posts" with body params:
      | post[body] | Some body text without a title |
    Then the response status should be 422
    And no event of type "Events::OrderCreated" should have been tracked
    And the memory adapter should be empty

  # ---------------------------------------------------------------------------
  # Unhandled exception path
  # GET /test_error triggers PostsController#error which does:
  #   raise StandardError, "Test error for E11y instrumentation"
  # Because config.action_dispatch.show_exceptions = false, Rack::Test
  # re-raises the exception. We rescue it in the step definition and verify
  # the memory adapter state AFTER the request.
  # Note: The E11y middleware (E11y::Middleware::Request) calls
  # RequestScopedBuffer.flush_on_error in its rescue block when
  # request_buffer.enabled is true. With default config (disabled),
  # no E11y-level event is automatically created for the exception.
  # This scenario therefore verifies the absence of spurious events
  # when the exception handling feature is disabled.
  # ---------------------------------------------------------------------------
  Scenario: GET /test_error raises StandardError and produces no automatic E11y events
    When I make a GET request to "/test_error" ignoring exceptions
    Then the memory adapter should be empty
```

### Step 2 — Run the feature to confirm all steps are undefined

```bash
bundle exec cucumber features/event_tracking.feature
```

Expected: all steps reported as "undefined" (yellow). The `@wip` scenario will be pending. No Ruby errors.

### Step 3 — Commit the feature file

```bash
git add features/event_tracking.feature
git commit -m "test(cucumber): add event_tracking.feature — core API scenarios"
```

---

## Task 2 — Write `features/step_definitions/event_tracking_steps.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/step_definitions/event_tracking_steps.rb`

### Step 1 — Write the step definitions

```ruby
# frozen_string_literal: true

# features/step_definitions/event_tracking_steps.rb
#
# Step definitions specific to the event_tracking.feature.
# Generic steps (response status, event count, field equality) live in common_steps.rb.

# ---------------------------------------------------------------------------
# HTTP request steps
# ---------------------------------------------------------------------------

# Sends a POST to the given path with a flat params hash built from a Cucumber
# data table (two-column format: key | value).
When("I POST to {string} with order params:") do |path, table|
  params = table.rows_hash
  post path, params
end

When("I POST to {string} with user params:") do |path, table|
  params = table.rows_hash
  post path, params
end

When("I POST to {string} with body params:") do |path, table|
  params = table.rows_hash
  post path, params
end

# Sends a GET request and rescues any exception raised by the app.
# The exception is stored on the World object so that subsequent steps can
# inspect it (or assert it was absent).
When("I make a GET request to {string} ignoring exceptions") do |path|
  @last_exception = nil
  begin
    get path
  rescue StandardError => e
    @last_exception = e
  end
end

# ---------------------------------------------------------------------------
# @wip step: calls E11y.track directly (currently raises NotImplementedError)
# ---------------------------------------------------------------------------

# This step calls E11y.track(event_instance) and captures any exception.
# When the bug is fixed, @last_exception should be nil and the event should
# appear in the memory adapter.
When("I call E11y.track with a new Events::OrderCreated instance") do
  @last_exception = nil
  begin
    event_instance = Events::OrderCreated.new # rubocop:disable Style/RedundantSelf
    E11y.track(event_instance)
  rescue StandardError => e
    @last_exception = e
  end
end

# ---------------------------------------------------------------------------
# Exception assertions
# ---------------------------------------------------------------------------

Then("no exception should have been raised") do
  expect(@last_exception).to be_nil,
    "Expected no exception but got: #{@last_exception.class}: #{@last_exception&.message}"
end

Then("a {string} exception should have been raised") do |exception_class_name|
  expect(@last_exception).not_to be_nil,
    "Expected a #{exception_class_name} to be raised but no exception occurred."
  expect(@last_exception.class.name).to eq(exception_class_name),
    "Expected #{exception_class_name} but got #{@last_exception.class.name}: #{@last_exception.message}"
end

# ---------------------------------------------------------------------------
# Event metadata assertions
# ---------------------------------------------------------------------------

# Verifies that the most recent event of the given type has a non-nil :timestamp.
Then("the last {string} event has a non-nil timestamp") do |event_type|
  event = last_tracked_event(event_type)
  expect(event).not_to be_nil,
    "No event of type '#{event_type}' was tracked."
  expect(event[:timestamp]).not_to be_nil,
    "Expected :timestamp to be set but it was nil.\nEvent: #{event.inspect}"
end

# Verifies that the most recent event of the given type has a non-nil :severity.
Then("the last {string} event has a non-nil severity") do |event_type|
  event = last_tracked_event(event_type)
  expect(event).not_to be_nil,
    "No event of type '#{event_type}' was tracked."
  expect(event[:severity]).not_to be_nil,
    "Expected :severity to be set but it was nil.\nEvent: #{event.inspect}"
end

# Verifies that the event's :severity matches the expected symbol (passed as string).
Then("the last {string} event should have severity {string}") do |event_type, expected_severity|
  event = last_tracked_event(event_type)
  expect(event).not_to be_nil,
    "No event of type '#{event_type}' was tracked."
  expect(event[:severity].to_s).to eq(expected_severity),
    "Expected severity :#{expected_severity} but got :#{event[:severity]}."
end

# Verifies that the event's :version field matches the expected integer.
Then("the last {string} event should have version {int}") do |event_type, expected_version|
  event = last_tracked_event(event_type)
  expect(event).not_to be_nil,
    "No event of type '#{event_type}' was tracked."
  expect(event[:version]).to eq(expected_version),
    "Expected version #{expected_version} but got #{event[:version]}."
end
```

### Step 2 — Run the feature again with step definitions in place

```bash
bundle exec cucumber features/event_tracking.feature
```

Expected results:
- `@wip` scenario ("Calling E11y.track...") FAILS with `NotImplementedError` — this is correct and expected. Cucumber will mark it as "failed" (or "pending" if run with `--wip` flag).
- All non-`@wip` scenarios PASS.
- Overall exit code: non-zero (because the `@wip` scenario fails).

To run only passing scenarios (non-`@wip`):

```bash
bundle exec cucumber --tags "not @wip" features/event_tracking.feature
```

Expected: all scenarios pass, exit code 0.

### Step 3 — Confirm the @wip failure message

```bash
bundle exec cucumber --tags "@wip" features/event_tracking.feature
```

Expected output includes:
```
NotImplementedError: E11y.track will be implemented in Phase 1
  lib/e11y.rb:68
```

This confirms the bug is correctly captured.

### Step 4 — Commit

```bash
git add features/step_definitions/event_tracking_steps.rb
git commit -m "test(cucumber): add event_tracking_steps.rb — HTTP POST helpers, exception assertions"
```

---

## Task 3 — Run full feature with Rake

```bash
bundle exec rake cucumber:passing
```

Expected: only non-`@wip` scenarios run; all pass.

```bash
bundle exec rake cucumber:wip
```

Expected: the `@wip` scenario runs and fails with `NotImplementedError`. This is the CORRECT outcome — it means the test suite is correctly tracking the known bug.

---

## Bug reference

### BUG-001: `E11y.track(event_instance)` raises `NotImplementedError`

**Location:** `lib/e11y.rb`, lines 66–68

```ruby
def track(event)
  # TODO: Implement in Phase 1
  raise NotImplementedError, "E11y.track will be implemented in Phase 1"
end
```

**Impact:** The primary public API documented in the README Quick Start is completely non-functional. Any application code that follows the documented pattern will crash immediately.

**Working alternative:** Call `EventClass.track(**payload)` directly on the event class:

```ruby
# This works:
Events::OrderCreated.track(order_id: "123", status: "pending")

# This crashes:
E11y.track(Events::OrderCreated.new(order_id: "123", status: "pending"))
```

**How the Cucumber `@wip` scenario documents this:**
The step "When I call E11y.track with a new Events::OrderCreated instance" calls `E11y.track` and stores any exception in `@last_exception`. The step "Then no exception should have been raised" asserts `@last_exception` is nil — which fails because `NotImplementedError` is raised. When the bug is fixed, the scenario will pass and the `@wip` tag should be removed.

**Fix guidance (out of scope for this plan):** Implement `E11y.track` to accept an event instance, extract its payload, and route it through the pipeline as `EventClass.track` does. The pipeline entry point is `E11y.config.built_pipeline.call(event_data)` where `event_data` is built in `E11y::Event::Base.track`.

---

## Scenario cross-reference

| Scenario | Route | Event class | Expected adapter result |
|---|---|---|---|
| @wip E11y.track instance | — (direct Ruby call) | Events::OrderCreated | 1 event (BUG: NotImplementedError) |
| POST /orders tracks event | POST /orders | Events::OrderCreated | 1 event |
| Payload contains submitted fields | POST /orders | Events::OrderCreated | status field = "confirmed" |
| Event has metadata | POST /orders | Events::OrderCreated | timestamp and severity non-nil |
| POST /users tracks event | POST /users | Events::UserRegistered | 1 event |
| Multiple requests | POST /orders x2 | Events::OrderCreated | 2 events |
| Rails validation failure | POST /posts (no title) | none | 0 events, 422 response |
| Unhandled exception | GET /test_error | none | 0 events (buffer disabled) |
