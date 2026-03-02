# Event Versioning — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that the `Versioning` middleware correctly extracts version numbers and normalises event names from class names, and expose the known bug where it silently overwrites custom `event_name` overrides.

**Approach:** Black-box Cucumber scenarios use `Rack::Test` to POST to dummy app routes and then inspect events stored in `E11y.config.adapters[:memory]`. The `Versioning` middleware is opt-in, so each scenario that requires it explicitly adds it to the pipeline via a `Before` hook helper and resets the pipeline afterwards. Scenarios marked `@wip` are expected to fail because they document confirmed bugs.

**Known bugs covered:**
- `Versioning#call` unconditionally overwrites `event_data[:event_name]` using `normalize_event_name(class_name)` even when the event class has a custom `event_name` defined — custom names are silently replaced.
- `normalize_event_name` may mis-handle acronyms: `UserID` could produce `user.i.d` instead of `user_id` due to the per-character camelCase regex.
- The `Versioning` middleware is not in the default pipeline; the README does not state this clearly.

---

## Task structure

### Files to create

- `features/event_versioning.feature`
- `features/step_definitions/event_versioning_steps.rb`

---

### Step 1 — Write `features/event_versioning.feature` (full content)

```gherkin
# features/event_versioning.feature
@event_versioning
Feature: Event Versioning middleware

  The Versioning middleware (opt-in) extracts a version number from the event
  class name suffix (e.g. V2, V3) and normalises the event_name field for
  consistent storage queries. It must NOT overwrite a custom event_name set
  explicitly on the event class.

  Background:
    Given the memory adapter is registered and cleared

  # -----------------------------------------------------------------------
  # Scenario 1 — Standard class name normalisation (V1 — no version suffix)
  # -----------------------------------------------------------------------
  Scenario: OrderCreated class name produces normalised event_name in tracked payload
    Given the Versioning middleware is added to the pipeline
    When I POST to "/orders" with params:
      | order_id | order-001 |
      | status   | pending   |
    Then the last "Events::OrderCreated" event has event_name "order.created"
    And  the last "Events::OrderCreated" event does not have a "v" field

  # -----------------------------------------------------------------------
  # Scenario 2 — Nested namespace normalisation
  # -----------------------------------------------------------------------
  Scenario: Nested namespace Events::PaymentProcessed produces correct event_name
    Given the Versioning middleware is added to the pipeline
    When I POST to "/api/v1/payments" with params:
      | payment_id | pay-001   |
      | status     | completed |
    Then the last "Events::PaymentProcessed" event has event_name "payment.processed"
    And  the last "Events::PaymentProcessed" event does not have a "v" field

  # -----------------------------------------------------------------------
  # Scenario 3 — Custom event_name override preserved  (KNOWN BUG — @wip)
  # -----------------------------------------------------------------------
  @wip
  Scenario: Custom event_name override on event class is preserved when Versioning middleware is active
    Given the Versioning middleware is added to the pipeline
    And   an inline event class "Events::CustomNamedEvent" with event_name "my.custom.name"
    When  the event "Events::CustomNamedEvent" is tracked directly with payload:
      | key   | value |
      | field | data  |
    Then the last "Events::CustomNamedEvent" event has event_name "my.custom.name"

  # -----------------------------------------------------------------------
  # Scenario 4 — V2 versioned event  (KNOWN BUG — @wip)
  # -----------------------------------------------------------------------
  @wip
  Scenario: V2 versioned event sets v:2 in payload and strips version from event_name
    Given the Versioning middleware is added to the pipeline
    And   an inline event class "Events::OrderPaidV2" inheriting from "Events::OrderPaid"
    When  the event "Events::OrderPaidV2" is tracked directly with payload:
      | order_id | ord-002 |
      | currency | USD     |
    Then the last "Events::OrderPaidV2" event has event_name "order.paid"
    And  the last "Events::OrderPaidV2" event has a "v" field equal to 2

  # -----------------------------------------------------------------------
  # Scenario 5 — Versioning NOT active by default
  # -----------------------------------------------------------------------
  Scenario: Without Versioning middleware the event_name comes from Event::Base not Versioning
    Given the Versioning middleware is NOT added to the pipeline
    When I POST to "/orders" with params:
      | order_id | order-002 |
      | status   | pending   |
    Then the last "Events::OrderCreated" event is present
    And  the last "Events::OrderCreated" event has event_name "Events::OrderCreated"

  # -----------------------------------------------------------------------
  # Scenario 6 — Acronym edge case  (KNOWN BUG — @wip)
  # -----------------------------------------------------------------------
  @wip
  Scenario: Acronym in class name is handled correctly
    Given the Versioning middleware is added to the pipeline
    And   an inline event class "Events::UserID" with no custom event_name
    When  the event "Events::UserID" is tracked directly with payload:
      | key   | value |
      | field | data  |
    Then the last "Events::UserID" event has event_name "user.id"
```

---

### Step 2 — Run the feature (expect failures)

```bash
bundle exec cucumber features/event_versioning.feature
```

Expected: Scenarios 1, 2, 5 may pass or fail with "undefined step" errors. Scenarios 3, 4, 6 are tagged `@wip` and should be reported as pending/failing. No step definitions exist yet — all steps will be undefined.

---

### Step 3 — Write `features/step_definitions/event_versioning_steps.rb` (full content)

```ruby
# features/step_definitions/event_versioning_steps.rb
# frozen_string_literal: true

require "rack/test"
require "json"

World(Rack::Test::Methods)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def app
  Rails.application
end

def memory_adapter
  E11y.config.adapters[:memory]
end

# Rebuild the built_pipeline cache so that a freshly mutated pipeline
# is actually used on the next E11y track call.
def rebuild_pipeline!
  E11y.config.instance_variable_set(:@built_pipeline, nil)
end

# ---------------------------------------------------------------------------
# Background
# ---------------------------------------------------------------------------

Given("the memory adapter is registered and cleared") do
  unless memory_adapter
    E11y.config.adapters[:memory] = E11y::Adapters::InMemory.new
    E11y.config.fallback_adapters = [:memory]
  end
  memory_adapter.clear!
  rebuild_pipeline!
end

# ---------------------------------------------------------------------------
# Pipeline control
# ---------------------------------------------------------------------------

Given("the Versioning middleware is added to the pipeline") do
  # Only add once per scenario — guard against double-adding.
  already_present = E11y.config.pipeline.middlewares.any? do |entry|
    entry.middleware_class == E11y::Middleware::Versioning
  end

  unless already_present
    # Versioning belongs to :pre_processing zone — insert before Validation.
    E11y.config.pipeline.middlewares.unshift(
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Versioning,
        args: [],
        options: {}
      )
    )
  end

  rebuild_pipeline!

  # Register cleanup to remove it after the scenario.
  @versioning_added = true
end

Given("the Versioning middleware is NOT added to the pipeline") do
  E11y.config.pipeline.middlewares.reject! do |entry|
    entry.middleware_class == E11y::Middleware::Versioning
  end
  rebuild_pipeline!
end

After do
  if @versioning_added
    E11y.config.pipeline.middlewares.reject! do |entry|
      entry.middleware_class == E11y::Middleware::Versioning
    end
    rebuild_pipeline!
    @versioning_added = false
  end
end

# ---------------------------------------------------------------------------
# Inline event class definitions (for scenarios that need them)
# ---------------------------------------------------------------------------

Given("an inline event class {string} with event_name {string}") do |class_name, custom_event_name|
  # Build module / class path from class_name string.
  # e.g. "Events::CustomNamedEvent" → module Events; class CustomNamedEvent
  parts    = class_name.split("::")
  mod_name = parts[0..-2].join("::")
  cls_name = parts.last

  parent_mod = mod_name.empty? ? Object : Object.const_get(mod_name)

  unless parent_mod.const_defined?(cls_name)
    klass = Class.new(E11y::Event::Base) do
      schema do
        optional(:field).maybe(:string)
      end
      adapters []
    end

    # Override event_name to the custom value.
    custom = custom_event_name
    klass.define_singleton_method(:event_name) { custom }

    parent_mod.const_set(cls_name, klass)
  end

  @inline_class_name = class_name
end

Given("an inline event class {string} with no custom event_name") do |class_name|
  parts    = class_name.split("::")
  mod_name = parts[0..-2].join("::")
  cls_name = parts.last

  parent_mod = mod_name.empty? ? Object : Object.const_get(mod_name)

  unless parent_mod.const_defined?(cls_name)
    klass = Class.new(E11y::Event::Base) do
      schema do
        optional(:field).maybe(:string)
      end
      adapters []
    end

    parent_mod.const_set(cls_name, klass)
  end

  @inline_class_name = class_name
end

Given("an inline event class {string} inheriting from {string}") do |class_name, parent_class_name|
  parts      = class_name.split("::")
  mod_name   = parts[0..-2].join("::")
  cls_name   = parts.last
  parent_cls = Object.const_get(parent_class_name)

  parent_mod = mod_name.empty? ? Object : Object.const_get(mod_name)

  unless parent_mod.const_defined?(cls_name)
    klass = Class.new(parent_cls)
    parent_mod.const_set(cls_name, klass)
  end

  @inline_class_name = class_name
end

# ---------------------------------------------------------------------------
# HTTP steps
# ---------------------------------------------------------------------------

When("I POST to {string} with params:") do |path, table|
  params = table.rows_hash
  post path, params.to_json, "CONTENT_TYPE" => "application/json"
end

# ---------------------------------------------------------------------------
# Direct track step (used for inline event classes)
# ---------------------------------------------------------------------------

When("the event {string} is tracked directly with payload:") do |class_name, table|
  klass   = Object.const_get(class_name)
  payload = table.rows_hash.transform_keys(&:to_sym)
  klass.track(**payload)
end

# ---------------------------------------------------------------------------
# Assertion steps
# ---------------------------------------------------------------------------

Then("the last {string} event is present") do |event_class_name|
  events = memory_adapter.find_events(event_class_name)
  expect(events).not_to be_empty,
    "Expected at least one event for #{event_class_name} but found none. " \
    "All events: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
end

Then("the last {string} event has event_name {string}") do |event_class_name, expected_name|
  events = memory_adapter.find_events(event_class_name)
  expect(events).not_to be_empty,
    "No events found for class #{event_class_name}"

  actual = events.last[:event_name]
  expect(actual).to eq(expected_name),
    "Expected event_name '#{expected_name}' but got '#{actual}'"
end

Then("the last {string} event does not have a {string} field") do |event_class_name, field_name|
  events = memory_adapter.find_events(event_class_name)
  expect(events).not_to be_empty

  last_event = events.last
  expect(last_event).not_to have_key(field_name.to_sym),
    "Expected event to NOT have field '#{field_name}' but it was present: #{last_event[field_name.to_sym].inspect}"
end

Then("the last {string} event has a {string} field equal to {int}") do |event_class_name, field_name, expected_value|
  events = memory_adapter.find_events(event_class_name)
  expect(events).not_to be_empty

  last_event = events.last
  actual = last_event[field_name.to_sym]
  expect(actual).to eq(expected_value),
    "Expected field '#{field_name}' to equal #{expected_value} but got #{actual.inspect}"
end
```

---

### Step 4 — Run again and confirm `@wip` scenarios fail for the right reasons

```bash
bundle exec cucumber features/event_versioning.feature
```

Expected outcome:
- Scenarios 1 and 2: PASS — `normalize_event_name` works for standard names.
- Scenario 3: FAIL (`@wip`) — `event_name` is overwritten by Versioning; assertion sees `"custom.named.event"` not `"my.custom.name"`.
- Scenario 4: FAIL (`@wip`) — `v: 2` may or may not appear depending on `event_class` availability; `event_name` suffix removal behaviour is the focus.
- Scenario 5: PASS — default `event_name` from `Event::Base` is the raw class name string.
- Scenario 6: FAIL (`@wip`) — `normalize_event_name("Events::UserID")` produces `"user.i.d"` instead of `"user.id"`.

---

### Step 5 — Commit

```bash
git add features/event_versioning.feature \
        features/step_definitions/event_versioning_steps.rb
git commit -m "feat(cucumber): add event versioning QA scenarios (plan 13)"
```

---

## Reference: key source locations

| File | Relevance |
|------|-----------|
| `lib/e11y/middleware/versioning.rb` | `normalize_event_name` regex and unconditional overwrite on line 75 |
| `lib/e11y/event/base.rb` line 348–353 | Default `event_name` implementation (strips `V\d+$` but does not use dot notation) |
| `lib/e11y/pipeline/builder.rb` | `MiddlewareEntry` struct; `build` / `use` methods |
| `lib/e11y.rb` line 201–215 | `configure_default_pipeline` — Versioning absent |
| `spec/dummy/app/events/events/order_created.rb` | Used in scenarios 1 and 5 |
| `spec/dummy/app/events/events/order_paid.rb` | Parent class for scenario 4 |
| `spec/dummy/app/events/events/payment_processed.rb` | Used in scenario 2 |
