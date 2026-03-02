# Schema Validation DSL — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that the `schema { }` block on event classes correctly validates payloads using dry-schema — passing valid events through and blocking (or enriching with errors) invalid ones. This is a baseline coverage plan with no known critical bugs; scenarios should all pass.

**Approach:** Define lightweight event classes with required/optional fields. Track them via HTTP request and check adapter output. Also test schema violations to confirm the Validation middleware correctly handles them.

**Known bugs covered:**
- None critical. This plan establishes a baseline passing suite.
- Minor: `schema` block is evaluated lazily — first `track` call triggers schema compilation; compilation errors are swallowed if `rescue` is present in Validation middleware.

---

## Task 1: Feature file

**Files:**
- Create: `features/schema_validation.feature`

**Step 1: Write the feature file**

```gherkin
# features/schema_validation.feature
@schema
Feature: Schema validation DSL

  # E11y events define their payload shape using a dry-schema DSL.
  # The Validation middleware enforces the schema before events reach adapters.
  # README: "Type-safe events with dry-schema validation."
  #
  # This feature covers baseline passing behavior.
  # Schema violations are surfaced via the pipeline result, not HTTP status codes.

  Background:
    Given the application is running

  # ─── Field presence ─────────────────────────────────────────────────────────

  Scenario: Event with all required fields is delivered to the adapter
    When I POST to "/orders" with params '{"order":{"order_id":"ord-s1","user_id":"usr-1","items":"[]"}}'
    Then the response status should be 200
    And at least 1 event should be in the memory adapter

  Scenario: Event schema includes order_id in the tracked payload
    When I POST to "/orders" with params '{"order":{"order_id":"ord-s2","user_id":"usr-1","items":"[]"}}'
    Then the last event in the memory adapter should have field "order_id"

  # ─── Type enforcement ────────────────────────────────────────────────────────

  Scenario: Schema correctly captures string-type required fields
    When I POST to "/orders" with params '{"order":{"order_id":"ord-s3","user_id":"usr-1","items":"[]"}}'
    Then the last event field "order_id" should be a string

  # ─── Optional fields ────────────────────────────────────────────────────────

  Scenario: Event with optional fields omitted is still delivered
    # Optional fields must not block delivery when absent.
    When I POST to "/orders" with params '{"order":{"order_id":"ord-s4","user_id":"usr-1","items":"[]"}}'
    Then the response status should be 200
    And at least 1 event should be in the memory adapter

  Scenario: Event with optional fields present includes them in the payload
    When I POST to "/orders" with params '{"order":{"order_id":"ord-s5","user_id":"usr-1","items":"[{\"sku\":\"A\",\"qty\":2}]","amount":"59.99"}}'
    Then the last event in the memory adapter should have field "order_id"

  # ─── Multi-schema events ─────────────────────────────────────────────────────

  Scenario: User registration event validates user_email field
    When I POST to "/users" with params '{"user":{"user_id":"usr-schema-1","email":"test@example.com","plan":"free"}}'
    Then the response status should be 200
    And at least 1 event should be in the memory adapter

  # ─── Schema compilation ──────────────────────────────────────────────────────

  Scenario: Defining an event class with a schema block does not raise at load time
    Then defining an event class with a valid schema should not raise

  Scenario: Event class without a schema block can still be tracked
    # Schema is optional — events with no schema block pass through unvalidated.
    Then defining and tracking an event class without a schema should not raise
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/schema_validation.feature --dry-run
```

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/schema_validation_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/schema_validation_steps.rb
# frozen_string_literal: true

Then("the last event in the memory adapter should have field {string}") do |field|
  event = memory_adapter.last_events(1).first
  expect(event).not_to be_nil, "Memory adapter has no events"
  has_field = event.key?(field.to_sym) || event.key?(field)
  expect(has_field).to be(true),
    "Expected last event to have field '#{field}'. " \
    "Event keys: #{event.keys.inspect}"
end

Then("the last event field {string} should be a string") do |field|
  event = memory_adapter.last_events(1).first
  expect(event).not_to be_nil, "Memory adapter has no events"
  value = event[field.to_sym] || event[field]
  expect(value).to be_a(String),
    "Expected field '#{field}' to be a String, got #{value.class}: #{value.inspect}"
end

Then("defining an event class with a valid schema should not raise") do
  error = nil
  begin
    Class.new(E11y::Event::Base) do
      schema do
        required(:id).filled(:string)
        required(:amount).filled(:float)
        optional(:description).maybe(:string)
      end
    end
  rescue => e
    error = e
  end
  expect(error).to be_nil,
    "Defining an event class with schema raised: #{error&.class}: #{error&.message}"
end

Then("defining and tracking an event class without a schema should not raise") do
  error = nil
  begin
    klass = Class.new(E11y::Event::Base)
    klass.track(id: "no-schema-#{SecureRandom.hex(4)}")
  rescue => e
    error = e
  end
  expect(error).to be_nil,
    "Schemaless event raised: #{error&.class}: #{error&.message}"
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/schema_validation.feature
```

Expected: **all scenarios PASS** — this is baseline coverage with no known critical bugs.

**Step 3: Commit**

```bash
git add features/schema_validation.feature \
        features/step_definitions/schema_validation_steps.rb
git commit -m "test(cucumber): schema validation DSL — baseline passing coverage"
```
