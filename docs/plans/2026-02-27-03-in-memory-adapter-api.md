# InMemory Adapter API — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify every public method on `E11y::Adapters::InMemory` behaves correctly, and explicitly expose the two known API surface bugs with `@wip` scenarios.

**Approach:** Each scenario issues one or more HTTP POST requests to the dummy app via `Rack::Test` to generate real events in the memory adapter, then calls adapter methods directly from Ruby step definitions. This tests the adapter's query API in a fully integrated context — events travel through the complete pipeline (TraceContext → Validation → PIIFilter → AuditSigning → Sampling → Routing) before landing in the adapter. No direct calls to `adapter.write` are made; all events enter via the normal tracking path.

**Known bugs covered:**
- `adapter.last_event` — method does not exist. NoMethodError is raised. Correct API: `adapter.last_events(1).first`. The `@wip` scenario calls `last_event` to document the bug.
- `adapter.event_count("Events::OrderCreated")` — passing a positional string argument raises `ArgumentError` because the method signature is `event_count(event_name: nil)` (keyword argument only). The `@wip` scenario calls it with a positional string to document the bug.
- `adapter.clear` vs `adapter.clear!` — only `clear!` is defined. Calling `adapter.clear` raises `NoMethodError`. This is documented as a `@wip` scenario as well.

---

## Files to create

```
features/in_memory_adapter.feature
features/step_definitions/in_memory_adapter_steps.rb
```

Prerequisites: Plan 01 (Cucumber Infrastructure) must be complete.

---

## Task 1 — Write `features/in_memory_adapter.feature`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/in_memory_adapter.feature`

### Step 1 — Write the feature file

```gherkin
# features/in_memory_adapter.feature
#
# Verifies the public API of E11y::Adapters::InMemory.
#
# The memory adapter is the primary tool for asserting events in tests.
# Any regression in its API breaks every integration test that uses it.
#
# Bug tags:
#   @wip  — scenario exposes a known bug; expected to FAIL.
#
# Correct method signatures (from lib/e11y/adapters/in_memory.rb):
#   adapter.clear!                              # clears all events
#   adapter.find_events("Events::OrderCreated") # returns Array<Hash>
#   adapter.event_count                         # total count (no args)
#   adapter.event_count(event_name: "...")      # count by name (keyword arg)
#   adapter.last_events(n)                      # last N events as Array<Hash>
#   adapter.first_events(n)                     # first N events
#   adapter.events_by_severity(:info)           # filter by severity
#   adapter.any_event?("Events::OrderCreated")  # returns Boolean

Feature: InMemory adapter public API

  Background:
    Given the application is running
    And the memory adapter is empty

  # ===========================================================================
  # @wip scenarios — these expose KNOWN BUGS and are expected to FAIL
  # ===========================================================================

  # BUG-002: adapter.last_event does not exist
  #
  # The method `last_event` is NOT defined on E11y::Adapters::InMemory.
  # Calling it raises NoMethodError.
  # The correct call is: adapter.last_events(1).first
  #
  # This is a significant DX (developer experience) bug because `last_event`
  # is the most natural thing to write when asserting the most recent event.
  @wip
  Scenario: adapter.last_event returns the most recently tracked event
    Given I have tracked 1 order event with status "pending"
    When I call adapter.last_event
    Then the result should be a Hash
    And the result's payload field "status" should equal "pending"

  # BUG-003: adapter.event_count("Events::OrderCreated") raises ArgumentError
  #
  # The method signature is: event_count(event_name: nil)
  # Passing a positional string argument raises:
  #   ArgumentError: wrong number of arguments (given 1, expected 0)
  #
  # Callers familiar with Ruby conventions may naturally write:
  #   adapter.event_count("Events::OrderCreated")
  # instead of:
  #   adapter.event_count(event_name: "Events::OrderCreated")
  @wip
  Scenario: adapter.event_count with positional string arg returns count
    Given I have tracked 2 order events
    When I call adapter.event_count with positional argument "Events::OrderCreated"
    Then the result should equal 2

  # BUG-004: adapter.clear (without bang) raises NoMethodError
  #
  # Only adapter.clear! is defined. The no-bang variant is missing.
  # Most Ruby developers expect both forms to exist (with clear! being the
  # "destructive" confirmation). Calling adapter.clear raises NoMethodError.
  @wip
  Scenario: adapter.clear without bang clears all events
    Given I have tracked 1 order event with status "pending"
    When I call adapter.clear without bang
    Then the memory adapter should be empty

  # ===========================================================================
  # Passing scenarios — correct API surface
  # ===========================================================================

  Scenario: adapter.clear! removes all tracked events
    Given I have tracked 3 order events
    When I call adapter.clear!
    Then the memory adapter should be empty

  Scenario: adapter.event_count with no args returns total count of all events
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.event_count with no arguments
    Then the result should equal 3

  Scenario: adapter.event_count with keyword arg counts events of a specific type
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.event_count with keyword event_name "Events::OrderCreated"
    Then the result should equal 2

  Scenario: adapter.find_events returns only events matching the given class name
    Given I have tracked 2 order events
    And I have tracked 1 user registration event
    When I call adapter.find_events with "Events::OrderCreated"
    Then the result should contain 2 items
    And all items in the result should have event_name "Events::OrderCreated"

  Scenario: adapter.find_events returns empty array when no matching events exist
    Given I have tracked 1 user registration event
    When I call adapter.find_events with "Events::OrderCreated"
    Then the result should contain 0 items

  Scenario: adapter.last_events(n) returns the last N events in insertion order
    Given I have tracked 3 order events with statuses "pending", "confirmed", "cancelled"
    When I call adapter.last_events with count 2
    Then the result should contain 2 items

  Scenario: adapter.last_events(1).first is the workaround for missing last_event
    Given I have tracked 1 order event with status "shipped"
    When I call adapter.last_events(1).first
    Then the result should be a Hash
    And the result's payload field "status" should equal "shipped"

  Scenario: adapter.first_events(n) returns the first N events in insertion order
    Given I have tracked 3 order events with statuses "pending", "confirmed", "cancelled"
    When I call adapter.first_events with count 1
    Then the result should contain 1 item

  Scenario: adapter.events_by_severity filters events by severity symbol
    Given I have tracked 1 order event with status "pending"
    When I call adapter.events_by_severity with :info
    Then the result should contain at least 1 item

  Scenario: adapter.any_event? returns true when matching events exist
    Given I have tracked 1 order event with status "pending"
    When I call adapter.any_event? with "Events::OrderCreated"
    Then the boolean result should be true

  Scenario: adapter.any_event? returns false when no matching events exist
    Given the memory adapter is empty
    When I call adapter.any_event? with "Events::OrderCreated"
    Then the boolean result should be false

  Scenario: adapter tracks events across separate requests independently
    Given I have tracked 1 order event with status "first"
    And I have tracked 1 order event with status "second"
    Then 2 events of type "Events::OrderCreated" should have been tracked
    And the last "Events::OrderCreated" event's field "status" should equal "second"

  Scenario: adapter.events returns all events as an array
    Given I have tracked 2 order events
    Then the adapter events array should have 2 items
```

### Step 2 — Run to verify all steps are undefined

```bash
bundle exec cucumber features/in_memory_adapter.feature
```

Expected: "undefined" steps listed. `@wip` scenarios are pending. No Ruby errors.

### Step 3 — Commit the feature file

```bash
git add features/in_memory_adapter.feature
git commit -m "test(cucumber): add in_memory_adapter.feature — adapter API scenarios"
```

---

## Task 2 — Write `features/step_definitions/in_memory_adapter_steps.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/step_definitions/in_memory_adapter_steps.rb`

### Step 1 — Write the step definitions

```ruby
# frozen_string_literal: true

# features/step_definitions/in_memory_adapter_steps.rb
#
# Step definitions specific to in_memory_adapter.feature.
# Uses Rack::Test to generate real events in the memory adapter via HTTP requests
# to the dummy app, then exercises adapter query methods directly.

# ---------------------------------------------------------------------------
# Setup steps — generate events via HTTP
# ---------------------------------------------------------------------------

Given("the memory adapter is empty") do
  clear_events!
end

Given("I have tracked {int} order event(s)") do |count|
  count.times do
    post "/orders", { "order[status]" => "pending" }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

Given("I have tracked {int} order event(s) with status {string}") do |count, status|
  count.times do
    post "/orders", { "order[status]" => status }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

# Tracks multiple orders using a comma-separated status list.
# Example: "pending", "confirmed", "cancelled"
Given("I have tracked {int} order events with statuses {string}, {string}, {string}") do |_count, s1, s2, s3|
  [s1, s2, s3].each do |status|
    post "/orders", { "order[status]" => status }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

Given("I have tracked {int} user registration event(s)") do |count|
  count.times do |i|
    post "/users", {
      "user[email]"                 => "user#{i}@example.com",
      "user[password]"              => "password123",
      "user[password_confirmation]" => "password123",
      "user[name]"                  => "User #{i}"
    }
    expect(last_response.status).to eq(201),
      "POST /users failed with #{last_response.status}: #{last_response.body}"
  end
end

# ---------------------------------------------------------------------------
# Action steps — call adapter methods and store result in @adapter_result
# ---------------------------------------------------------------------------

# @wip step — calls adapter.last_event which does NOT exist (NoMethodError expected)
When("I call adapter.last_event") do
  @adapter_exception = nil
  begin
    @adapter_result = memory_adapter.last_event
  rescue NoMethodError => e
    @adapter_exception = e
    raise # Re-raise so Cucumber marks the @wip scenario as failed
  end
end

# @wip step — calls adapter.event_count with positional string arg (ArgumentError expected)
When("I call adapter.event_count with positional argument {string}") do |event_name|
  @adapter_exception = nil
  begin
    @adapter_result = memory_adapter.event_count(event_name)
  rescue ArgumentError => e
    @adapter_exception = e
    raise # Re-raise so Cucumber marks the @wip scenario as failed
  end
end

# @wip step — calls adapter.clear (no bang) which does NOT exist (NoMethodError expected)
When("I call adapter.clear without bang") do
  @adapter_exception = nil
  begin
    memory_adapter.clear
  rescue NoMethodError => e
    @adapter_exception = e
    raise # Re-raise so Cucumber marks the @wip scenario as failed
  end
end

When("I call adapter.clear!") do
  memory_adapter.clear!
end

When("I call adapter.event_count with no arguments") do
  @adapter_result = memory_adapter.event_count
end

When("I call adapter.event_count with keyword event_name {string}") do |event_name|
  @adapter_result = memory_adapter.event_count(event_name: event_name)
end

When("I call adapter.find_events with {string}") do |event_name|
  @adapter_result = memory_adapter.find_events(event_name)
end

When("I call adapter.last_events with count {int}") do |count|
  @adapter_result = memory_adapter.last_events(count)
end

When("I call adapter.last_events\({int}).first") do |count|
  @adapter_result = memory_adapter.last_events(count).first
end

When("I call adapter.first_events with count {int}") do |count|
  @adapter_result = memory_adapter.first_events(count)
end

When("I call adapter.events_by_severity with :info") do
  @adapter_result = memory_adapter.events_by_severity(:info)
end

When("I call adapter.any_event? with {string}") do |event_name|
  @adapter_result = memory_adapter.any_event?(event_name)
end

# ---------------------------------------------------------------------------
# Assertion steps — inspect @adapter_result
# ---------------------------------------------------------------------------

Then("the result should be a Hash") do
  expect(@adapter_result).to be_a(Hash),
    "Expected a Hash but got #{@adapter_result.class}: #{@adapter_result.inspect}"
end

Then("the result should equal {int}") do |expected_int|
  expect(@adapter_result).to eq(expected_int),
    "Expected #{expected_int} but got #{@adapter_result.inspect}"
end

Then("the result should contain {int} item(s)") do |count|
  expect(@adapter_result).to be_an(Array),
    "Expected an Array but got #{@adapter_result.class}"
  expect(@adapter_result.size).to eq(count),
    "Expected #{count} items but got #{@adapter_result.size}.\n" \
    "Items: #{@adapter_result.inspect}"
end

Then("the result should contain at least {int} item(s)") do |min_count|
  expect(@adapter_result).to be_an(Array),
    "Expected an Array but got #{@adapter_result.class}"
  expect(@adapter_result.size).to be >= min_count,
    "Expected at least #{min_count} items but got #{@adapter_result.size}."
end

Then("the boolean result should be {word}") do |bool_string|
  expected = (bool_string == "true")
  expect(@adapter_result).to eq(expected),
    "Expected #{expected.inspect} but got #{@adapter_result.inspect}"
end

Then("all items in the result should have event_name {string}") do |event_name|
  expect(@adapter_result).to be_an(Array)
  @adapter_result.each_with_index do |item, idx|
    actual_name = item[:event_name]
    expect(actual_name).to eq(event_name),
      "Item #{idx} has event_name #{actual_name.inspect}, expected #{event_name.inspect}.\n" \
      "Item: #{item.inspect}"
  end
end

Then("the result's payload field {string} should equal {string}") do |field, expected_value|
  payload = @adapter_result[:payload] || @adapter_result.dig(:payload)
  expect(payload).not_to be_nil,
    "Result has no :payload key.\nResult: #{@adapter_result.inspect}"
  actual_value = payload[field.to_sym] || payload[field]
  expect(actual_value.to_s).to eq(expected_value),
    "Expected payload[:#{field}] to equal #{expected_value.inspect} but got #{actual_value.inspect}."
end

Then("the adapter events array should have {int} items") do |count|
  expect(memory_adapter.events.size).to eq(count),
    "Expected adapter.events.size to be #{count} but got #{memory_adapter.events.size}."
end
```

### Step 2 — Run the feature with step definitions

```bash
bundle exec cucumber features/in_memory_adapter.feature
```

Expected results:
- `@wip` "adapter.last_event" — FAILS with `NoMethodError: undefined method 'last_event'`
- `@wip` "adapter.event_count with positional string arg" — FAILS with `ArgumentError`
- `@wip` "adapter.clear without bang" — FAILS with `NoMethodError: undefined method 'clear'`
- All other scenarios — PASS

### Step 3 — Confirm each @wip failure message individually

For BUG-002 (`last_event`):

```bash
bundle exec cucumber --tags "@wip" features/in_memory_adapter.feature \
  --name "adapter.last_event returns the most recently tracked event"
```

Expected: `NoMethodError: undefined method 'last_event' for an instance of E11y::Adapters::InMemory`

For BUG-003 (`event_count` positional arg):

```bash
bundle exec cucumber --tags "@wip" features/in_memory_adapter.feature \
  --name "adapter.event_count with positional string arg"
```

Expected: `ArgumentError: wrong number of arguments (given 1, expected 0)`

For BUG-004 (`clear` without bang):

```bash
bundle exec cucumber --tags "@wip" features/in_memory_adapter.feature \
  --name "adapter.clear without bang clears all events"
```

Expected: `NoMethodError: undefined method 'clear' for an instance of E11y::Adapters::InMemory`

### Step 4 — Run only passing scenarios

```bash
bundle exec cucumber --tags "not @wip" features/in_memory_adapter.feature
```

Expected: all pass.

### Step 5 — Commit

```bash
git add features/step_definitions/in_memory_adapter_steps.rb
git commit -m "test(cucumber): add in_memory_adapter_steps.rb — adapter query method coverage"
```

---

## Task 3 — Run full adapter feature via Rake

```bash
bundle exec rake cucumber:passing
```

Expected: passes (excludes `@wip`).

```bash
bundle exec rake cucumber:wip
```

Expected: 3 scenarios fail (BUG-002, BUG-003, BUG-004). This is correct behavior — the bugs are tracked.

---

## Bug reference

### BUG-002: `adapter.last_event` raises `NoMethodError`

**Location:** `lib/e11y/adapters/in_memory.rb` — method not defined.

**Symptom:**
```ruby
memory_adapter.last_event
# => NoMethodError: undefined method 'last_event' for an instance of E11y::Adapters::InMemory
```

**Workaround:**
```ruby
memory_adapter.last_events(1).first
```

**Fix guidance:** Add the method:
```ruby
def last_event
  @mutex.synchronize { @events.last }
end
```

---

### BUG-003: `adapter.event_count("Events::OrderCreated")` raises `ArgumentError`

**Location:** `lib/e11y/adapters/in_memory.rb:142`

**Actual signature:**
```ruby
def event_count(event_name: nil)
```

**Symptom:**
```ruby
memory_adapter.event_count("Events::OrderCreated")
# => ArgumentError: wrong number of arguments (given 1, expected 0)
```

**Workaround:**
```ruby
memory_adapter.event_count(event_name: "Events::OrderCreated")
```

**Fix guidance:** Either add a positional overload or change the signature to `event_count(event_name = nil)`. The latter is a breaking change if callers already use the keyword form; prefer an overload:
```ruby
def event_count(event_name = nil, event_name: nil)
  resolved = __method_binding_var__ || event_name  # resolve either form
  ...
end
```
Or more simply, support both calling conventions using `*args`:
```ruby
def event_count(*args, event_name: nil)
  event_name ||= args.first
  ...
end
```

---

### BUG-004: `adapter.clear` (without bang) raises `NoMethodError`

**Location:** `lib/e11y/adapters/in_memory.rb` — only `clear!` is defined.

**Symptom:**
```ruby
memory_adapter.clear
# => NoMethodError: undefined method 'clear' for an instance of E11y::Adapters::InMemory
```

**Workaround:** Use `clear!` explicitly.

**Fix guidance:** Add an alias:
```ruby
alias clear clear!
```

Note: Ruby convention allows both `clear` and `clear!` to exist where `clear!` is the "be careful" variant. For a test-only adapter, providing both is reasonable and expected.

---

## Adapter API reference (as-implemented)

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `write` | `write(event_data)` | `true` | Thread-safe via Mutex |
| `write_batch` | `write_batch(events)` | `true` | Thread-safe |
| `clear!` | `clear!` | `void` | BUG: `clear` (no-bang) is missing |
| `find_events` | `find_events(pattern)` | `Array<Hash>` | String or Regexp |
| `event_count` | `event_count(event_name: nil)` | `Integer` | BUG: positional arg raises ArgumentError |
| `last_events` | `last_events(count = 10)` | `Array<Hash>` | — |
| `first_events` | `first_events(count = 10)` | `Array<Hash>` | — |
| `events_by_severity` | `events_by_severity(severity)` | `Array<Hash>` | e.g. `:info`, `:error` |
| `any_event?` | `any_event?(pattern)` | `Boolean` | — |
| `last_event` | — | — | BUG: does not exist; use `last_events(1).first` |
| `events` | `events` (attr_reader) | `Array<Hash>` | — |
| `batches` | `batches` (attr_reader) | `Array<Array<Hash>>` | — |
| `dropped_count` | `dropped_count` (attr_reader) | `Integer` | — |
