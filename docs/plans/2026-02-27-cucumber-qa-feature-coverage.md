# E11y QA Coverage Plan: Cucumber Feature Tests

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Write Cucumber feature files + step definitions that expose every documented feature and every known discrepancy between the README/docs and the actual implementation.

**Architecture:** Cucumber scenarios live in `features/` at the repo root. Each feature file maps to one documented capability. Step definitions use `RSpec::Matchers` under the hood and the `InMemory` adapter for observation. A `features/support/env.rb` bootstraps E11y in a clean state before each scenario.

**Tech Stack:** `cucumber` gem, `rspec-expectations`, `e11y` (local), minimal Rails dummy app already in `spec/dummy` (can be reused via `ENV["RAILS_ENV"] = "test"`).

**How to run:**
```bash
bundle exec cucumber features/          # all scenarios
bundle exec cucumber features/event_tracking.feature  # single file
bundle exec cucumber features/event_tracking.feature:42  # single scenario
```

**Expected outcome at plan start:** Nearly every scenario FAILS, exposing real implementation gaps.

---

## Setup Tasks

### Task 0: Add Cucumber to Gemfile and bootstrap

**Files:**
- Modify: `Gemfile`
- Create: `features/support/env.rb`
- Create: `features/support/hooks.rb`
- Create: `features/support/world_helpers.rb`
- Create: `features/step_definitions/shared_steps.rb`

**Step 1: Add dependencies to Gemfile**

In the `group :development, :test` block (after existing entries), add:

```ruby
gem "cucumber", "~> 9.0"
gem "cucumber-rails", require: false
gem "rspec-expectations", "~> 3.0"
```

**Step 2: Run bundle install**

```bash
bundle install
```
Expected: resolves cleanly.

**Step 3: Create `features/support/env.rb`**

```ruby
# frozen_string_literal: true

require "cucumber/rails" rescue nil  # optional rails integration
require "e11y"
require "rspec/expectations"

World(RSpec::Matchers)

# Point at the dummy Rails app for Rails-dependent scenarios
ENV["RAILS_ENV"] ||= "test"
```

**Step 4: Create `features/support/hooks.rb`**

```ruby
# frozen_string_literal: true

Before do
  # Reset E11y configuration before every scenario
  E11y.instance_variable_set(:@configuration, nil)
  E11y.instance_variable_set(:@built_pipeline, nil)
end
```

**Step 5: Create `features/support/world_helpers.rb`**

```ruby
# frozen_string_literal: true

module WorldHelpers
  def configure_with_in_memory_adapter
    E11y.configure do |c|
      c.adapters[:default] = E11y::Adapters::InMemory.new
    end
  end

  def in_memory_adapter
    E11y.configuration.adapters[:default]
  end

  def define_minimal_event(name = "TestEvent", schema: {}, &block)
    klass = Class.new(E11y::Event::Base)
    klass.class_eval(&block) if block
    Object.const_set(name, klass) unless Object.const_defined?(name)
    Object.const_get(name)
  end
end

World(WorldHelpers)
```

**Step 6: Create `features/step_definitions/shared_steps.rb`**

```ruby
# frozen_string_literal: true

Given("E11y is configured with an in-memory adapter") do
  configure_with_in_memory_adapter
end

Then("no error should be raised") do
  # passes if we reach this point
end
```

**Step 7: Commit**

```bash
git add Gemfile features/support/ features/step_definitions/shared_steps.rb
git commit -m "test: bootstrap Cucumber infrastructure for QA coverage"
```

---

## Feature 1: Core Event Tracking API

**Files:**
- Create: `features/event_tracking.feature`
- Create: `features/step_definitions/event_tracking_steps.rb`

### Task 1: Write scenario — `E11y.track` raises NotImplementedError

**Background:** README Quick Start shows `E11y.track(event)` as the primary API. Code raises `NotImplementedError`.

**Step 1: Write the feature file**

```gherkin
# features/event_tracking.feature
Feature: Core event tracking API

  Background:
    Given E11y is configured with an in-memory adapter

  Scenario: E11y.track delegates to the pipeline (documented primary API)
    # README Quick Start shows: E11y.track(Events::UserSignup.new(user_id: 123))
    # BUG: lib/e11y.rb:66 raises NotImplementedError
    When I call E11y.track with a valid event instance
    Then the event should be written to the in-memory adapter
    And no error should be raised

  Scenario: EventClass.track is the working class-method API
    Given an event class "OrderCreated" with required field "order_id" of type string
    When I track an OrderCreated event with order_id "abc-123"
    Then the in-memory adapter should have received 1 event
    And the last event should have event_name "order_created"
    And the last event should have field "order_id" equal to "abc-123"

  Scenario: Tracking with missing required field raises validation error
    Given an event class "StrictEvent" with required field "user_id" of type string
    When I track a StrictEvent event without the "user_id" field
    Then a validation error should be raised

  Scenario: Tracking with extra fields is silently ignored
    Given an event class "SimpleEvent" with required field "name" of type string
    When I track a SimpleEvent event with name "hello" and extra field "bogus" equal to "data"
    Then the in-memory adapter should have received 1 event
    And the last event should not contain field "bogus"
```

**Step 2: Run to verify all scenarios fail**

```bash
bundle exec cucumber features/event_tracking.feature
```
Expected: 4 scenarios FAILING (undefined steps or assertion failures).

**Step 3: Write step definitions**

```ruby
# features/step_definitions/event_tracking_steps.rb
# frozen_string_literal: true

Given("an event class {string} with required field {string} of type string") do |class_name, field_name|
  @event_classes ||= {}
  klass = Class.new(E11y::Event::Base) do
    schema do
      required(field_name.to_sym).filled(:string)
    end
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
  @event_classes[class_name] = Object.const_get(class_name)
end

When("I call E11y.track with a valid event instance") do
  @error = nil
  begin
    E11y.track(double("event", to_h: { event_name: "test" }))
  rescue => e
    @error = e
  end
end

Then("the event should be written to the in-memory adapter") do
  expect(@error).to be_nil, "Expected no error but got: #{@error&.class}: #{@error&.message}"
  expect(in_memory_adapter.events.size).to be >= 1
end

When("I track an {word} event with order_id {string}") do |class_name, order_id|
  @error = nil
  begin
    Object.const_get(class_name).track(order_id: order_id)
  rescue => e
    @error = e
  end
end

Then("the in-memory adapter should have received {int} event(s)") do |count|
  expect(@error).to be_nil, "Unexpected error: #{@error&.class}: #{@error&.message}"
  expect(in_memory_adapter.event_count).to eq(count)
end

Then("the last event should have event_name {string}") do |expected_name|
  last = in_memory_adapter.last_events(1).first
  expect(last).not_to be_nil
  expect(last[:event_name]).to eq(expected_name)
end

Then("the last event should have field {string} equal to {string}") do |field, value|
  last = in_memory_adapter.last_events(1).first
  expect(last[field.to_sym].to_s).to eq(value)
end

When("I track a {word} event without the {string} field") do |class_name, _field|
  @error = nil
  begin
    Object.const_get(class_name).track({})
  rescue => e
    @error = e
  end
end

Then("a validation error should be raised") do
  expect(@error).not_to be_nil
  expect(@error).to be_a(E11y::ValidationError).or be_a(ArgumentError)
end

When("I track a {word} event with name {string} and extra field {string} equal to {string}") do |class_name, name, extra_key, extra_val|
  @error = nil
  begin
    Object.const_get(class_name).track(name: name, extra_key.to_sym => extra_val)
  rescue => e
    @error = e
  end
end

Then("the last event should not contain field {string}") do |field|
  last = in_memory_adapter.last_events(1).first
  expect(last).not_to have_key(field.to_sym)
end
```

**Step 4: Run and record failures**

```bash
bundle exec cucumber features/event_tracking.feature
```
Expected: "E11y.track delegates" FAILS with `NotImplementedError`, others pass/fail based on real behavior.

**Step 5: Commit**

```bash
git add features/event_tracking.feature features/step_definitions/event_tracking_steps.rb
git commit -m "test(cucumber): event tracking API coverage — E11y.track stub exposed"
```

---

## Feature 2: InMemory Adapter API

**Files:**
- Create: `features/in_memory_adapter.feature`
- Create: `features/step_definitions/in_memory_adapter_steps.rb`

### Task 2: Scenarios for all InMemory adapter methods

**Background:** README documents `.last_event`, `.event_count("Name")`, `.events_for("Name")`, `.clear`. Actual API differs.

**Step 1: Write feature file**

```gherkin
# features/in_memory_adapter.feature
Feature: InMemory adapter API for testing

  Background:
    Given E11y is configured with an in-memory adapter
    And an event class "PingEvent" with required field "host" of type string

  Scenario: last_event returns the most recent single event (documented API)
    # BUG: README shows test_adapter.last_event — method does not exist
    # Actual: last_events(1).first
    Given I have tracked 3 PingEvent events
    When I call last_event on the adapter
    Then I should receive the 3rd tracked event
    And no NoMethodError should be raised

  Scenario: event_count with positional event name argument (documented API)
    # BUG: event_count("PingEvent") raises ArgumentError
    # Actual: event_count(event_name: "PingEvent")
    Given I have tracked 2 PingEvent events
    When I call event_count with positional argument "ping_event"
    Then the result should equal 2
    And no ArgumentError should be raised

  Scenario: event_count with keyword argument works
    Given I have tracked 2 PingEvent events
    When I call event_count with keyword argument event_name: "ping_event"
    Then the result should equal 2

  Scenario: event_count with no argument returns total count
    Given I have tracked 2 PingEvent events
    When I call event_count with no arguments
    Then the result should equal 2

  Scenario: clear removes all events
    Given I have tracked 2 PingEvent events
    When I call clear on the adapter
    Then the adapter should have 0 events

  Scenario: events_for filters by event name
    Given I have tracked 2 PingEvent events
    When I call events_for with "ping_event"
    Then the result should contain 2 events
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/in_memory_adapter.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/in_memory_adapter_steps.rb
# frozen_string_literal: true

Given("I have tracked {int} {word} events") do |count, class_name|
  count.times { |i| Object.const_get(class_name).track(host: "host-#{i}") }
end

When("I call last_event on the adapter") do
  @error = nil
  begin
    @result = in_memory_adapter.last_event
  rescue => e
    @error = e
    @result = nil
  end
end

Then("I should receive the {int}rd tracked event") do |_n|
  expect(@result).not_to be_nil
  expect(@result).to be_a(Hash)
end

Then("no NoMethodError should be raised") do
  expect(@error).not_to be_a(NoMethodError),
    "Got NoMethodError: #{@error&.message}. README documents #last_event but method does not exist."
end

When("I call event_count with positional argument {string}") do |name|
  @error = nil
  begin
    @result = in_memory_adapter.event_count(name)
  rescue => e
    @error = e
    @result = nil
  end
end

When("I call event_count with keyword argument event_name: {string}") do |name|
  @error = nil
  begin
    @result = in_memory_adapter.event_count(event_name: name)
  rescue => e
    @error = e
  end
end

When("I call event_count with no arguments") do
  @result = in_memory_adapter.event_count
end

Then("no ArgumentError should be raised") do
  expect(@error).not_to be_a(ArgumentError),
    "Got ArgumentError: #{@error&.message}. README documents positional arg but method requires keyword."
end

Then("the result should equal {int}") do |expected|
  expect(@result).to eq(expected)
end

When("I call clear on the adapter") do
  in_memory_adapter.clear
end

Then("the adapter should have {int} events") do |count|
  expect(in_memory_adapter.event_count).to eq(count)
end

When("I call events_for with {string}") do |name|
  @result = in_memory_adapter.events_for(name)
end

Then("the result should contain {int} events") do |count|
  expect(@result.size).to eq(count)
end
```

**Step 4: Run and record failures**

```bash
bundle exec cucumber features/in_memory_adapter.feature
```
Expected: "last_event" fails with `NoMethodError`, "event_count positional" fails with `ArgumentError`.

**Step 5: Commit**

```bash
git add features/in_memory_adapter.feature features/step_definitions/in_memory_adapter_steps.rb
git commit -m "test(cucumber): InMemory adapter API discrepancies — last_event and event_count bugs"
```

---

## Feature 3: Request-Scoped Debug Buffering

**Files:**
- Create: `features/request_buffer.feature`
- Create: `features/step_definitions/request_buffer_steps.rb`

### Task 3: Scenarios for request-scoped buffering (the "killer feature")

**Background:** README claims debug events buffer in memory during a request and flush to adapters only on request failure. `flush_event` is a stub — does nothing.

**Step 1: Write feature file**

```gherkin
# features/request_buffer.feature
Feature: Request-scoped debug buffering

  # This is the primary differentiating feature of E11y.
  # README: "Buffer debug logs in memory, flush ONLY if request fails"
  # Bug: flush_event in request_scoped_buffer.rb is a stub

  Background:
    Given E11y is configured with an in-memory adapter
    And request buffering is enabled

  Scenario: Debug events are not written on successful request
    Given a debug event class "VerboseDebug" with required field "msg" of type string
    When a request starts
    And I track 3 VerboseDebug events with msg "step info"
    And the request completes successfully
    Then the in-memory adapter should have received 0 events

  Scenario: Debug events ARE written when request fails
    # BUG: flush_event is a stub, so adapter receives 0 events even on failure
    Given a debug event class "VerboseDebug" with required field "msg" of type string
    When a request starts
    And I track 3 VerboseDebug events with msg "step info"
    And the request fails with a RuntimeError
    Then the in-memory adapter should have received 3 events
    And all flushed events should have severity "debug"

  Scenario: Error events bypass the buffer and are written immediately
    Given an error event class "CriticalFail" with required field "code" of type integer
    When a request starts
    And I track a CriticalFail event with code 500
    Then the in-memory adapter should have received 1 event immediately
    And the buffered event count should be 0

  Scenario: Buffer is cleared after request completes successfully (no memory leak)
    Given a debug event class "VerboseDebug" with required field "msg" of type string
    When a request starts
    And I track 10 VerboseDebug events with msg "step info"
    And the request completes successfully
    When another request starts
    Then the buffer for the new request should be empty

  Scenario: Buffer capacity limit is enforced (ring buffer overflow)
    Given a debug event class "VerboseDebug" with required field "msg" of type string
    And the buffer max size is set to 5
    When a request starts
    And I track 10 VerboseDebug events with msg "overflow test"
    And the request fails with a RuntimeError
    Then the in-memory adapter should have received at most 5 events
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/request_buffer.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/request_buffer_steps.rb
# frozen_string_literal: true

Given("request buffering is enabled") do
  E11y.configuration.request_buffer.enabled = true
end

Given("a debug event class {string} with required field {string} of type string") do |name, field|
  klass = Class.new(E11y::Event::Base) do
    severity :debug
    schema { required(field.to_sym).filled(:string) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

Given("an error event class {string} with required field {string} of type integer") do |name, field|
  klass = Class.new(E11y::Event::Base) do
    severity :error
    schema { required(field.to_sym).filled(:integer) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

Given("the buffer max size is set to {int}") do |size|
  E11y.configuration.request_buffer.max_size = size
end

When("a request starts") do
  E11y::Buffers::RequestScopedBuffer.start_request
end

When("another request starts") do
  E11y::Buffers::RequestScopedBuffer.start_request
end

When("I track {int} {word} events with msg {string}") do |count, class_name, msg|
  count.times { Object.const_get(class_name).track(msg: msg) }
end

When("I track a {word} event with code {int}") do |class_name, code|
  Object.const_get(class_name).track(code: code)
end

When("the request completes successfully") do
  E11y::Buffers::RequestScopedBuffer.end_request(success: true)
end

When("the request fails with a RuntimeError") do
  E11y::Buffers::RequestScopedBuffer.end_request(success: false, error: RuntimeError.new("boom"))
end

Then("all flushed events should have severity {string}") do |sev|
  events = in_memory_adapter.events
  expect(events).to all(include(severity: sev.to_sym))
end

Then("the buffered event count should be {int}") do |count|
  buffer = E11y::Buffers::RequestScopedBuffer.current
  expect(buffer&.size.to_i).to eq(count)
end

Then("the buffer for the new request should be empty") do
  buffer = E11y::Buffers::RequestScopedBuffer.current
  expect(buffer&.size.to_i).to eq(0)
end

Then("the in-memory adapter should have received at most {int} events") do |max|
  expect(in_memory_adapter.event_count).to be <= max
end

Then("the in-memory adapter should have received {int} event(s) immediately") do |count|
  expect(in_memory_adapter.event_count).to eq(count)
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/request_buffer.feature
```
Expected: "request fails → flush 3 events" FAILS because `flush_event` is a stub.

**Step 5: Commit**

```bash
git add features/request_buffer.feature features/step_definitions/request_buffer_steps.rb
git commit -m "test(cucumber): request buffer flush stub exposed — core feature non-functional"
```

---

## Feature 4: SLO Tracking

**Files:**
- Create: `features/slo_tracking.feature`
- Create: `features/step_definitions/slo_tracking_steps.rb`

### Task 4: Scenarios for SLO tracker

**Background:** README documents `.status` method and "Zero-Config SLO Tracking". Neither works.

**Step 1: Write feature file**

```gherkin
# features/slo_tracking.feature
Feature: Zero-Config SLO tracking

  # README: "Zero-Config SLO Tracking – Automatic Service Level Objectives"
  # Bug 1: SLO tracking is disabled by default (enabled: false)
  # Bug 2: E11y::SLO::Tracker.status does not exist (NoMethodError)
  # Bug 3: EventSlo middleware not included in default pipeline

  Scenario: SLO tracking is active by default (zero-config)
    # BUG: SLOTrackingConfig initializes with @enabled = false
    Given E11y is configured with default settings
    Then SLO tracking should be enabled

  Scenario: SLO::Tracker.status returns aggregated SLO data
    # BUG: method does not exist
    Given SLO tracking is enabled
    When I call E11y::SLO::Tracker.status
    Then the result should be a Hash
    And no NoMethodError should be raised

  Scenario: HTTP request success is tracked as SLO event
    Given SLO tracking is enabled
    And E11y is configured with an in-memory adapter
    When an HTTP request to "POST /orders" completes with status 201 in 150ms
    Then the SLO tracker should have recorded a success for "POST /orders"

  Scenario: HTTP request failure updates SLO failure rate
    Given SLO tracking is enabled
    When an HTTP request to "POST /orders" completes with status 500 in 200ms
    Then the SLO tracker should have recorded a failure for "POST /orders"

  Scenario: Background job SLO is tracked
    Given SLO tracking is enabled
    When a background job "OrderProcessor" completes successfully in 1200ms
    Then the SLO tracker should have recorded a success for "OrderProcessor"

  Scenario: Event-level SLO emits metric when EventSlo middleware is in pipeline
    # BUG: EventSlo middleware not in default pipeline
    Given SLO tracking is enabled
    And the EventSlo middleware is in the pipeline
    And a payment event class with SLO defined
    When I track a payment success event
    Then a metric "slo_event_result_total" should have been emitted
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/slo_tracking.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/slo_tracking_steps.rb
# frozen_string_literal: true

Given("E11y is configured with default settings") do
  E11y.configure { |_c| }  # just trigger defaults
end

Given("SLO tracking is enabled") do
  E11y.configure do |c|
    c.slo_tracking.enabled = true
  end
end

Then("SLO tracking should be enabled") do
  expect(E11y.configuration.slo_tracking.enabled).to be(true),
    "Expected SLO tracking to be enabled by default (zero-config), but it is disabled."
end

When("I call E11y::SLO::Tracker.status") do
  @error = nil
  begin
    @result = E11y::SLO::Tracker.status
  rescue => e
    @error = e
  end
end

Then("the result should be a Hash") do
  expect(@result).to be_a(Hash), "Expected Hash result from status, got: #{@result.inspect}"
end

Then("no NoMethodError should be raised") do
  expect(@error).not_to be_a(NoMethodError),
    "NoMethodError: #{@error&.message}. README documents E11y::SLO::Tracker.status but method missing."
end

When("an HTTP request to {string} completes with status {int} in {int}ms") do |path, status, duration_ms|
  E11y::SLO::Tracker.track_http_request(
    path: path,
    method: "POST",
    status: status,
    duration: duration_ms / 1000.0
  )
end

Then("the SLO tracker should have recorded a success for {string}") do |endpoint|
  status = E11y::SLO::Tracker.status
  expect(status).to include(endpoint)
  expect(status[endpoint][:success_rate]).to be > 0
end

Then("the SLO tracker should have recorded a failure for {string}") do |endpoint|
  status = E11y::SLO::Tracker.status
  expect(status).to include(endpoint)
  expect(status[endpoint][:failure_count]).to be > 0
end

When("a background job {string} completes successfully in {int}ms") do |job_name, duration_ms|
  E11y::SLO::Tracker.track_background_job(
    job_class: job_name,
    success: true,
    duration: duration_ms / 1000.0
  )
end

Given("the EventSlo middleware is in the pipeline") do
  E11y.configuration.pipeline.use(E11y::Middleware::EventSlo)
end

Given("a payment event class with SLO defined") do
  @payment_event_class = Class.new(E11y::Event::Base) do
    schema { required(:status).filled(:string) }
    slo do
      enabled true
      success_criteria { |e| e[:status] == "success" }
      latency_threshold 300
    end
  end
  Object.const_set("PaymentTracked", @payment_event_class) unless Object.const_defined?("PaymentTracked")
end

When("I track a payment success event") do
  PaymentTracked.track(status: "success")
end

Then("a metric {string} should have been emitted") do |metric_name|
  metrics_adapter = E11y.configuration.adapters[:metrics]
  expect(metrics_adapter).not_to be_nil, "No metrics adapter configured"
  expect(metrics_adapter.events).to include(a_hash_including(metric_name: metric_name))
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/slo_tracking.feature
```
Expected: "SLO enabled by default" FAILS, "Tracker.status" FAILS with NoMethodError.

**Step 5: Commit**

```bash
git add features/slo_tracking.feature features/step_definitions/slo_tracking_steps.rb
git commit -m "test(cucumber): SLO tracker — default disabled, missing .status method, EventSlo not in pipeline"
```

---

## Feature 5: PII Filtering

**Files:**
- Create: `features/pii_filtering.feature`
- Create: `features/step_definitions/pii_filtering_steps.rb`

### Task 5: Scenarios for PII filtering correctness

**Background:** README documents GDPR-compliant PII filtering. Known bugs: PASSWORD_FIELDS pattern applied to string VALUES (not field names), corrupting legitimate strings; Tier2 crashes without Rails.

**Step 1: Write feature file**

```gherkin
# features/pii_filtering.feature
Feature: PII filtering

  # README: "PII Filtering – GDPR-compliant data masking and hashing"
  # Bug 1: PASSWORD_FIELDS regex applied to string values, corrupting legitimate data
  # Bug 2: Tier2 filtering calls Rails.application — crashes without Rails

  Background:
    Given E11y is configured with an in-memory adapter
    And PII filtering is enabled

  Scenario: Email addresses in event payload are masked
    Given a tracked event with field "description" containing "user@example.com"
    Then the stored event should have "description" masked or replaced

  Scenario: Credit card numbers in payload are masked
    Given a tracked event with field "notes" containing "4111 1111 1111 1111"
    Then the stored event should have "notes" masked or replaced

  Scenario: Field named "password" has its value filtered
    Given a tracked event with field "password" equal to "mysecretpassword"
    Then the stored event should have "password" filtered

  Scenario: Legitimate string containing "token" word is NOT corrupted
    # BUG: PASSWORD_FIELDS applied to values — "token_rotation_completed" becomes "[FILTERED]_rotation_completed"
    Given a tracked event with field "action" containing "api_key_rotation_completed"
    Then the stored event field "action" should be "api_key_rotation_completed"
    And the stored event field "action" should not contain "[FILTERED]"

  Scenario: Status message containing word "password" is NOT corrupted
    # BUG: "password validation passed" → "[FILTERED] validation passed"
    Given a tracked event with field "message" containing "password validation passed"
    Then the stored event field "message" should be "password validation passed"
    And the stored event field "message" should not contain "[FILTERED]"

  Scenario: User ID field named "user_id" is hashed, not removed
    Given a tracked event with field "user_id" equal to "usr_12345"
    Then the stored event should have "user_id" as a hash (not original value)

  Scenario: Tier2 PII filtering works without Rails application context
    # BUG: pii_filter.rb calls Rails.application.config.filter_parameters
    Given Rails application context is NOT available
    And a Tier2 event is tracked
    Then no NameError or NoMethodError should be raised
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/pii_filtering.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/pii_filtering_steps.rb
# frozen_string_literal: true

Given("PII filtering is enabled") do
  E11y.configure do |c|
    c.pii.enabled = true
    c.pipeline.use(E11y::Middleware::PIIFilter)
  end
end

Given("a tracked event with field {string} containing {string}") do |field, value|
  klass = Class.new(E11y::Event::Base) do
    schema { required(field.to_sym).maybe(:string) }
  end
  @tracked_field = field
  klass.track(field.to_sym => value)
end

Given("a tracked event with field {string} equal to {string}") do |field, value|
  klass = Class.new(E11y::Event::Base) do
    schema { required(field.to_sym).filled(:string) }
  end
  @tracked_field = field
  @original_value = value
  klass.track(field.to_sym => value)
end

Then("the stored event should have {string} masked or replaced") do |field|
  last = in_memory_adapter.last_events(1).first
  original = @original_value
  actual = last[field.to_sym]
  expect(actual).not_to eq(original),
    "Expected PII in '#{field}' to be masked, but original value was stored: #{actual.inspect}"
end

Then("the stored event should have {string} filtered") do |field|
  last = in_memory_adapter.last_events(1).first
  actual = last[field.to_sym]
  expect(actual).to eq("[FILTERED]").or match(/\[FILTERED\]/)
end

Then("the stored event field {string} should be {string}") do |field, expected|
  last = in_memory_adapter.last_events(1).first
  actual = last[field.to_sym]
  expect(actual).to eq(expected),
    "Field '#{field}': expected #{expected.inspect} but got #{actual.inspect}. " \
    "PII password/token regex is corrupting legitimate string values!"
end

Then("the stored event field {string} should not contain {string}") do |field, substring|
  last = in_memory_adapter.last_events(1).first
  actual = last[field.to_sym].to_s
  expect(actual).not_to include(substring),
    "Field '#{field}' contains '#{substring}': #{actual.inspect}"
end

Then("the stored event should have {string} as a hash (not original value)") do |field|
  last = in_memory_adapter.last_events(1).first
  actual = last[field.to_sym]
  expect(actual).not_to eq(@original_value)
  expect(actual).to match(/\A[a-f0-9]{8,}\z/), "Expected hashed value but got: #{actual.inspect}"
end

Given("Rails application context is NOT available") do
  @rails_available = defined?(::Rails)
  hide_const("Rails") if @rails_available
end

Given("a Tier2 event is tracked") do
  klass = Class.new(E11y::Event::Base) do
    pii_tier :tier2
    schema { required(:email).filled(:string) }
  end
  @pii_error = nil
  begin
    klass.track(email: "test@example.com")
  rescue NameError, NoMethodError => e
    @pii_error = e
  end
end

Then("no NameError or NoMethodError should be raised") do
  expect(@pii_error).to be_nil,
    "Got #{@pii_error&.class}: #{@pii_error&.message}. " \
    "Tier2 PII filter crashes without Rails (calls Rails.application directly)."
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/pii_filtering.feature
```
Expected: "api_key_rotation_completed not corrupted" and "password validation passed not corrupted" FAIL.

**Step 5: Commit**

```bash
git add features/pii_filtering.feature features/step_definitions/pii_filtering_steps.rb
git commit -m "test(cucumber): PII filtering — value regex corruption bug and Tier2 Rails dependency"
```

---

## Feature 6: Adapter Configurations

**Files:**
- Create: `features/adapters.feature`
- Create: `features/step_definitions/adapters_steps.rb`

### Task 6: Adapter configuration correctness scenarios

**Background:** Stdout adapter ignores `format: :pretty`; Sentry adapter reinitializes SDK.

**Step 1: Write feature file**

```gherkin
# features/adapters.feature
Feature: Adapter configuration

  Scenario: Stdout adapter accepts format: :pretty (documented config)
    # BUG: Adapter reads :pretty_print key, not :format
    # format: :pretty is silently ignored
    Given I configure a Stdout adapter with format: :pretty
    When I track an event through the Stdout adapter
    Then the output should be pretty-printed
    And no configuration option should be silently ignored

  Scenario: Stdout adapter accepts pretty_print: false (actual key)
    Given I configure a Stdout adapter with pretty_print: false
    When I track an event through the Stdout adapter
    Then the output should be compact (not pretty-printed)

  Scenario: Sentry adapter does not reinitialize an already-configured Sentry SDK
    # BUG: Sentry.init is called unconditionally in initialize, wiping existing Sentry config
    Given Sentry SDK is already initialized with DSN "https://existing@sentry.io/1"
    When I create a Sentry E11y adapter
    Then the Sentry SDK DSN should still be "https://existing@sentry.io/1"
    And the original Sentry configuration should be preserved

  Scenario: Loki healthy? returns false when Loki is unreachable
    # BUG: healthy? returns true if @connection.respond_to?(:get), never makes real check
    Given a Loki adapter pointing to "http://unreachable-host-99999.invalid:3100"
    When I call healthy? on the Loki adapter
    Then the result should be false

  Scenario: OTel adapter forwards business fields in attributes
    # BUG: baggage_allowlist filters out all non-trace fields by default
    Given an OTel adapter with default configuration
    When I track an event with order_id "ord-123" and amount 99.99
    Then the OTel log record should contain attribute "order_id" equal to "ord-123"
    And the OTel log record should contain attribute "amount" equal to "99.99"
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/adapters.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/adapters_steps.rb
# frozen_string_literal: true

Given("I configure a Stdout adapter with format: :pretty") do
  require "stringio"
  @stdout_buffer = StringIO.new
  @adapter = E11y::Adapters::Stdout.new(format: :pretty, output: @stdout_buffer)
  @documented_config = { format: :pretty }
end

Given("I configure a Stdout adapter with pretty_print: false") do
  require "stringio"
  @stdout_buffer = StringIO.new
  @adapter = E11y::Adapters::Stdout.new(pretty_print: false, output: @stdout_buffer)
end

When("I track an event through the Stdout adapter") do
  @adapter.write(event_name: "test_event", severity: :info, payload: { key: "val" })
end

Then("the output should be pretty-printed") do
  output = @stdout_buffer.string
  expect(output).to match(/\n/), "Expected multi-line pretty output but got: #{output.inspect}"
end

Then("no configuration option should be silently ignored") do
  # The adapter should have respected format: :pretty
  # If it silently ignored it and used the default (also pretty), this check is insufficient.
  # We verify by checking the adapter's configuration state
  pretty = @adapter.instance_variable_get(:@pretty_print)
  expect(pretty).to be(true),
    "Adapter has @pretty_print=#{pretty.inspect}. format: :pretty was silently ignored — " \
    "adapter looks for :pretty_print key, not :format."
end

Then("the output should be compact (not pretty-printed)") do
  @adapter.write(event_name: "test_event", severity: :info, payload: { key: "val" })
  output = @stdout_buffer.string
  expect(output).not_to match(/\n\s+\n/)
end

Given("Sentry SDK is already initialized with DSN {string}") do |dsn|
  require "sentry-ruby" rescue nil
  skip_this_scenario unless defined?(::Sentry)
  ::Sentry.init { |c| c.dsn = dsn }
  @original_dsn = dsn
end

When("I create a Sentry E11y adapter") do
  @error = nil
  begin
    @sentry_adapter = E11y::Adapters::Sentry.new(dsn: "https://new@sentry.io/999")
  rescue => e
    @error = e
  end
end

Then("the Sentry SDK DSN should still be {string}") do |expected_dsn|
  current_dsn = ::Sentry.configuration&.dsn&.server
  expect(current_dsn).to include(expected_dsn.split("@").last),
    "Sentry DSN was overwritten! Expected #{expected_dsn}, got #{current_dsn}. " \
    "E11y::Adapters::Sentry calls Sentry.init unconditionally."
end

Then("the original Sentry configuration should be preserved") do
  # If Sentry.init was called again, the configuration is wiped
  expect(::Sentry.configuration).not_to be_nil
end

Given("a Loki adapter pointing to {string}") do |url|
  require "faraday" rescue nil
  skip_this_scenario unless defined?(::Faraday)
  @loki_adapter = E11y::Adapters::Loki.new(url: url, timeout: 1)
end

When("I call healthy? on the Loki adapter") do
  @result = @loki_adapter.healthy?
end

Then("the result should be false") do
  expect(@result).to be(false),
    "Expected healthy? to return false for unreachable host, but returned true. " \
    "Bug: healthy? only checks if @connection.respond_to?(:get), never makes network request."
end

Given("an OTel adapter with default configuration") do
  skip_this_scenario unless defined?(::OpenTelemetry)
  @otel_recorded_logs = []
  @otel_adapter = E11y::Adapters::OtelLogs.new
end

When("I track an event with order_id {string} and amount {float}") do |order_id, amount|
  @otel_adapter.write(
    event_name: "order_created",
    severity: :info,
    order_id: order_id,
    amount: amount
  )
end

Then("the OTel log record should contain attribute {string} equal to {string}") do |attr, value|
  # Inspect what the adapter produced — verify business fields pass through
  # This is currently blocked by baggage_allowlist filtering them out
  pending "OTel adapter drops business fields via baggage_allowlist; #{attr} will not be present"
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/adapters.feature
```
Expected: Stdout `format:` scenario fails, Loki `healthy?` fails, OTel field forwarding fails.

**Step 5: Commit**

```bash
git add features/adapters.feature features/step_definitions/adapters_steps.rb
git commit -m "test(cucumber): adapter config bugs — Stdout format key, Sentry reinit, Loki health, OTel allowlist"
```

---

## Feature 7: Presets

**Files:**
- Create: `features/presets.feature`
- Create: `features/step_definitions/presets_steps.rb`

### Task 7: Scenarios for all three preset modules

**Background:** `AuditEvent` preset is an empty module — does NOT set `audit_event true`. `DebugEvent` correctly sets severity and adapters. `HighValueEvent` sets adapters to `[:logs, :errors_tracker]`.

**Step 1: Write feature file**

```gherkin
# features/presets.feature
Feature: Event presets

  Background:
    Given E11y is configured with an in-memory adapter

  Scenario: AuditEvent preset marks event as an audit event
    # BUG: AuditEvent preset has empty class_eval — does NOT call audit_event true
    # AuditSigning middleware will NOT sign events using this preset
    Given an event class "UserDeleted" including E11y::Presets::AuditEvent
    Then the UserDeleted event class should be marked as audit_event
    And the UserDeleted event class should have sample_rate 1.0

  Scenario: AuditEvent preset enforces 100% sample rate (never sampled)
    Given an event class "UserDeleted" including E11y::Presets::AuditEvent
    When I track 100 UserDeleted events
    Then the in-memory adapter should have received 100 events

  Scenario: AuditSigning middleware signs events using AuditEvent preset
    Given the AuditSigning middleware is in the pipeline
    And an event class "UserDeleted" including E11y::Presets::AuditEvent
    When I track a UserDeleted event
    Then the stored event should have a "_signature" field

  Scenario: DebugEvent preset sets severity to debug
    Given an event class "SlowQuery" including E11y::Presets::DebugEvent
    Then the SlowQuery event class should have severity :debug

  Scenario: DebugEvent preset routes to logs adapter only
    Given an event class "SlowQuery" including E11y::Presets::DebugEvent
    Then the SlowQuery event class should route to adapters [:logs]

  Scenario: HighValueEvent preset routes to logs and errors_tracker
    Given an event class "PaymentProcessed" including E11y::Presets::HighValueEvent
    Then the PaymentProcessed event class should route to adapters [:logs, :errors_tracker]

  Scenario: HighValueEvent preset enforces 100% sample rate
    Given an event class "PaymentProcessed" including E11y::Presets::HighValueEvent
    When I track 10 PaymentProcessed events
    Then the in-memory adapter should have received 10 events
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/presets.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/presets_steps.rb
# frozen_string_literal: true

Given("an event class {string} including {word}") do |class_name, preset_name|
  preset = case preset_name
  when "E11y::Presets::AuditEvent"   then E11y::Presets::AuditEvent
  when "E11y::Presets::DebugEvent"   then E11y::Presets::DebugEvent
  when "E11y::Presets::HighValueEvent" then E11y::Presets::HighValueEvent
  else raise "Unknown preset: #{preset_name}"
  end
  klass = Class.new(E11y::Event::Base) do
    include preset
    schema { required(:id).filled(:string) }
  end
  const_name = class_name.to_sym
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
  @defined_event_class = Object.const_get(class_name)
end

Then("the {word} event class should be marked as audit_event") do |class_name|
  klass = Object.const_get(class_name)
  expect(klass.audit_event?).to be(true),
    "#{class_name}.audit_event? returned false. E11y::Presets::AuditEvent does NOT call " \
    "audit_event true — its class_eval block is empty."
end

Then("the {word} event class should have sample_rate {float}") do |class_name, rate|
  klass = Object.const_get(class_name)
  expect(klass.sample_rate).to eq(rate)
end

Then("the {word} event class should have severity :{word}") do |class_name, sev|
  klass = Object.const_get(class_name)
  expect(klass.severity).to eq(sev.to_sym)
end

Then("the {word} event class should route to adapters {array}") do |class_name, adapters|
  # This step needs a custom parameter type for arrays — or use a different format
  klass = Object.const_get(class_name)
  expected = adapters.map(&:to_sym)
  actual = klass.adapters
  expect(actual).to match_array(expected)
end

Given("the AuditSigning middleware is in the pipeline") do
  E11y.configuration.pipeline.use(E11y::Middleware::AuditSigning)
end

When("I track a {word} event") do |class_name|
  Object.const_get(class_name).track(id: "test-#{rand(1000)}")
end

When("I track {int} {word} events") do |count, class_name|
  count.times { |i| Object.const_get(class_name).track(id: "id-#{i}") }
end

Then("the stored event should have a {string} field") do |field|
  last = in_memory_adapter.last_events(1).first
  expect(last).to have_key(field.to_sym).or have_key(field),
    "Expected event to have '#{field}' but keys are: #{last.keys.inspect}"
end
```

**Step 4: Add array parameter type** — create `features/support/parameter_types.rb`:

```ruby
# features/support/parameter_types.rb
ParameterType(
  name: "array",
  regexp: /\[([^\]]*)\]/,
  transformer: ->(s) { s.split(/,\s*/).map { |x| x.strip.delete("'\":") } }
)
```

**Step 5: Run**

```bash
bundle exec cucumber features/presets.feature
```
Expected: "AuditEvent marks as audit_event" FAILS because preset is empty.

**Step 6: Commit**

```bash
git add features/presets.feature features/step_definitions/presets_steps.rb features/support/parameter_types.rb
git commit -m "test(cucumber): preset bugs — AuditEvent empty, audit signing not triggered"
```

---

## Feature 8: Adaptive Sampling

**Files:**
- Create: `features/sampling.feature`
- Create: `features/step_definitions/sampling_steps.rb`

### Task 8: Scenarios for all sampling modes including LoadMonitor bug

**Background:** `LoadMonitor#load_level` has an off-by-one: normal-threshold load returns `:high` instead of `:normal`.

**Step 1: Write feature file**

```gherkin
# features/sampling.feature
Feature: Adaptive sampling

  Background:
    Given E11y is configured with an in-memory adapter
    And the Sampling middleware is in the pipeline

  Scenario: Events with sample_rate 1.0 are always tracked
    Given an event class "AlwaysTracked" with sample_rate 1.0
    When I track 100 AlwaysTracked events
    Then the in-memory adapter should have received 100 events

  Scenario: Events with sample_rate 0.0 are never tracked
    Given an event class "NeverTracked" with sample_rate 0.0
    When I track 100 NeverTracked events
    Then the in-memory adapter should have received 0 events

  Scenario: Load at normal threshold returns :normal load level (not :high)
    # BUG: load_level returns :high when rate == normal_threshold
    # Code: elsif rate >= @thresholds[:normal] → :high  (should be :normal)
    Given a LoadMonitor with thresholds normal: 100, high: 500, critical: 1000
    When the current request rate is 100 events per second
    Then the load level should be :normal
    And the sampling rate should be 1.0 (100%)

  Scenario: Load just below normal threshold returns :normal
    Given a LoadMonitor with thresholds normal: 100, high: 500, critical: 1000
    When the current request rate is 99 events per second
    Then the load level should be :normal

  Scenario: Load between normal and high thresholds returns :normal
    Given a LoadMonitor with thresholds normal: 100, high: 500, critical: 1000
    When the current request rate is 250 events per second
    Then the load level should be :normal

  Scenario: Load at high threshold returns :high
    Given a LoadMonitor with thresholds normal: 100, high: 500, critical: 1000
    When the current request rate is 500 events per second
    Then the load level should be :high
    And the sampling rate should be 0.5 (50%)

  Scenario: Load at critical threshold returns :critical
    Given a LoadMonitor with thresholds normal: 100, high: 500, critical: 1000
    When the current request rate is 1000 events per second
    Then the load level should be :critical
    And the sampling rate should be 0.1 (10%)

  Scenario: Error spike increases sampling rate for affected events
    Given an event class "OrderFailed" with severity :error
    And the error spike detector is configured
    When 5 consecutive errors occur within 10 seconds
    Then the sampling rate for "OrderFailed" should be 1.0

  Scenario: Events from the same trace ID get consistent sampling decisions
    # BUG: cleanup_trace_decisions uses random eviction, breaking trace completeness
    Given an event class "TraceEvent" with required field "trace_id" of type string
    When I track 5 events with trace_id "trace-abc-123"
    Then all 5 events should have the same sampling decision (all tracked or none)
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/sampling.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/sampling_steps.rb
# frozen_string_literal: true

Given("the Sampling middleware is in the pipeline") do
  E11y.configuration.pipeline.use(E11y::Middleware::Sampling)
end

Given("an event class {string} with sample_rate {float}") do |name, rate|
  klass = Class.new(E11y::Event::Base) do
    sample_rate rate
    schema { required(:n).filled(:integer) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

Given("an event class {string} with severity :{word}") do |name, sev|
  klass = Class.new(E11y::Event::Base) do
    severity sev.to_sym
    schema { required(:n).filled(:integer) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

Given("a LoadMonitor with thresholds normal: {int}, high: {int}, critical: {int}") do |normal, high, critical|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    thresholds: { normal: normal, high: high, critical: critical },
    sample_rates: { normal: 1.0, high: 0.5, critical: 0.1 }
  )
end

When("the current request rate is {int} events per second") do |rate|
  @current_rate = rate
  @load_level = @load_monitor.load_level(rate)
  @sample_rate = @load_monitor.sample_rate_for(@load_level)
end

Then("the load level should be :{word}") do |expected_level|
  expect(@load_level).to eq(expected_level.to_sym),
    "Expected load level :#{expected_level} at rate #{@current_rate}, " \
    "but got :#{@load_level}. " \
    "Bug in LoadMonitor#load_level: normal-threshold load returns :high instead of :normal."
end

Then("the sampling rate should be {float} \\({int}%)") do |rate, _pct|
  expect(@sample_rate).to eq(rate)
end

Given("the error spike detector is configured") do
  E11y.configuration.sampling.error_spike_detection.enabled = true
  E11y.configuration.sampling.error_spike_detection.threshold = 5
  E11y.configuration.sampling.error_spike_detection.window = 10
end

When("{int} consecutive errors occur within {int} seconds") do |count, _window|
  count.times { |i| Object.const_get("OrderFailed").track(n: i) }
end

Then("the sampling rate for {string} should be {float}") do |class_name, rate|
  klass = Object.const_get(class_name)
  current_rate = E11y::Sampling::ErrorSpikeDetector.current_rate_for(klass)
  expect(current_rate).to eq(rate)
end

Given("an event class {string} with required field {string} of type string") do |name, field|
  klass = Class.new(E11y::Event::Base) do
    schema { required(field.to_sym).filled(:string) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

When("I track {int} events with trace_id {string}") do |count, trace_id|
  count.times { Object.const_get("TraceEvent").track(trace_id: trace_id) }
end

Then("all {int} events should have the same sampling decision \\(all tracked or none)") do |count|
  actual_count = in_memory_adapter.event_count
  expect(actual_count).to eq(count).or eq(0),
    "Expected all #{count} events or none to be sampled (consistent trace sampling), " \
    "but got #{actual_count}. Random eviction in cleanup_trace_decisions breaks this."
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/sampling.feature
```
Expected: "normal-threshold returns :normal" FAILS (gets `:high`).

**Step 5: Commit**

```bash
git add features/sampling.feature features/step_definitions/sampling_steps.rb
git commit -m "test(cucumber): sampling — LoadMonitor off-by-one bug, trace consistency"
```

---

## Feature 9: DLQ (Dead Letter Queue)

**Files:**
- Create: `features/dlq.feature`
- Create: `features/step_definitions/dlq_steps.rb`

### Task 9: DLQ replay and delete stubs

**Step 1: Write feature file**

```gherkin
# features/dlq.feature
Feature: Dead Letter Queue reliability

  # README: "DLQ for critical events that fail to deliver"
  # Bug 1: DLQ#replay is a stub — does not re-dispatch event
  # Bug 2: DLQ#delete always returns false

  Background:
    Given E11y is configured with an in-memory adapter
    And DLQ uses in-memory storage

  Scenario: Failed event delivery sends event to DLQ
    Given an adapter that always fails
    And a critical event class "PaymentFailed" with required field "code" of type string
    When I track a PaymentFailed event with code "ERR-500"
    Then the DLQ should contain 1 entry

  Scenario: DLQ replay re-dispatches event through the pipeline
    # BUG: replay is a stub — does nothing (E11y::Pipeline.dispatch doesn't exist)
    Given the DLQ contains a failed PaymentFailed event
    When I replay the event from DLQ
    Then the event should appear in the in-memory adapter
    And the DLQ should be empty

  Scenario: DLQ delete removes the entry
    # BUG: delete always returns false
    Given the DLQ contains a failed PaymentFailed event
    When I delete the event from DLQ by ID
    Then the result should be true
    And the DLQ should be empty

  Scenario: DLQ entries persist across process (file storage)
    Given DLQ uses file storage at a temp path
    And the DLQ contains a failed PaymentFailed event
    When I read the DLQ from disk
    Then the DLQ entry should be present in the file

  Scenario: DLQ default file path works without Rails
    # BUG: default_file_path calls Rails.root — crashes without Rails
    Given Rails is not loaded
    When I create a DLQ FileStorage with no explicit path
    Then no NameError should be raised
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/dlq.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/dlq_steps.rb
# frozen_string_literal: true

Given("DLQ uses in-memory storage") do
  @dlq = E11y::Reliability::DLQ::MemoryStorage.new rescue E11y::Reliability::DLQ.new(storage: :memory)
end

Given("an adapter that always fails") do
  @failing_adapter = Class.new(E11y::Adapters::Base) do
    def write(_event_data)
      raise "Delivery failed"
    end
  end.new
  E11y.configuration.adapters[:default] = @failing_adapter
  E11y.configuration.dlq.enabled = true
end

Given("a critical event class {string} with required field {string} of type string") do |name, field|
  klass = Class.new(E11y::Event::Base) do
    schema { required(field.to_sym).filled(:string) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
end

When("I track a {word} event with code {string}") do |class_name, code|
  @error = nil
  begin
    Object.const_get(class_name).track(code: code)
  rescue => e
    @error = e
  end
end

Then("the DLQ should contain {int} entr(y|ies)") do |count|
  size = @dlq.size rescue @dlq.count
  expect(size).to eq(count)
end

Then("the DLQ should be empty") do
  size = @dlq.size rescue @dlq.count
  expect(size).to eq(0)
end

Given("the DLQ contains a failed {word} event") do |class_name|
  @dlq_entry_id = @dlq.push(
    event_name: class_name.downcase,
    event_data: { code: "ERR-test" },
    error: "Delivery failed",
    created_at: Time.now
  )
end

When("I replay the event from DLQ") do
  @replay_result = @dlq.replay(@dlq_entry_id)
end

Then("the event should appear in the in-memory adapter") do
  expect(in_memory_adapter.event_count).to be >= 1,
    "Expected replayed event in adapter, but adapter is empty. " \
    "DLQ#replay is a stub — E11y::Pipeline.dispatch is not implemented."
end

When("I delete the event from DLQ by ID") do
  @delete_result = @dlq.delete(@dlq_entry_id)
end

Then("the result should be true") do
  expect(@delete_result).to be(true),
    "Expected delete to return true but got #{@delete_result.inspect}. " \
    "DLQ#delete always returns false (TODO comment in implementation)."
end

Given("DLQ uses file storage at a temp path") do
  require "tmpdir"
  @temp_file = File.join(Dir.tmpdir, "e11y_dlq_test_#{Process.pid}.jsonl")
  @dlq = E11y::Reliability::DLQ::FileStorage.new(file_path: @temp_file)
end

When("I read the DLQ from disk") do
  @disk_entries = @dlq.all_entries
end

Then("the DLQ entry should be present in the file") do
  expect(@disk_entries.size).to be >= 1
  expect(File.exist?(@temp_file)).to be(true)
  # cleanup
  File.delete(@temp_file) if File.exist?(@temp_file)
end

Given("Rails is not loaded") do
  @rails_was_defined = defined?(::Rails)
end

When("I create a DLQ FileStorage with no explicit path") do
  @error = nil
  begin
    @dlq = E11y::Reliability::DLQ::FileStorage.new
  rescue NameError => e
    @error = e
  end
end

Then("no NameError should be raised") do
  expect(@error).to be_nil,
    "Got NameError: #{@error&.message}. " \
    "DLQ::FileStorage#default_file_path calls Rails.root — requires Rails."
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/dlq.feature
```
Expected: "replay re-dispatches" FAILS, "delete returns true" FAILS, "no NameError" FAILS if Rails not loaded.

**Step 5: Commit**

```bash
git add features/dlq.feature features/step_definitions/dlq_steps.rb
git commit -m "test(cucumber): DLQ replay and delete stubs, Rails dependency in default path"
```

---

## Feature 10: Rails Integration

**Files:**
- Create: `features/rails_integration.feature`
- Create: `features/step_definitions/rails_integration_steps.rb`

### Task 10: Rails Railtie, auto-disable in tests, ActiveJob double-registration

**Step 1: Write feature file**

```gherkin
# features/rails_integration.feature
Feature: Rails Railtie integration

  # Bug 1: config.enabled = !Rails.env.test? guard never fires (@enabled defaults to true, not nil)
  # Bug 2: ActiveJob callbacks registered twice (ApplicationJob AND ActiveJob::Base)
  # Bug 3: Rails instrumentation event classes don't exist (NameError rescued silently)

  Scenario: E11y is automatically disabled in test environment
    # BUG: @enabled defaults to true, so nil? check never triggers
    Given a Rails application in test environment
    When E11y Railtie initializes
    Then E11y.configuration.enabled should be false

  Scenario: E11y is automatically enabled in production environment
    Given a Rails application in production environment
    When E11y Railtie initializes
    Then E11y.configuration.enabled should be true

  Scenario: ActiveJob callbacks are registered only once when ApplicationJob inherits ActiveJob::Base
    # BUG: both ApplicationJob and ActiveJob::Base get the callbacks included
    Given a Rails app with ApplicationJob inheriting from ActiveJob::Base
    When E11y Railtie sets up ActiveJob integration
    Then the around_perform callback should be registered exactly once on ApplicationJob

  Scenario: SQL query events are tracked via Rails instrumentation
    # BUG: E11y::Events::Rails::Database::Query class does not exist
    Given a Rails application with E11y enabled
    And the Rails instrumentation is configured for SQL queries
    When a SQL query "SELECT 1" is executed
    Then an SQL query event should be tracked

  Scenario: HTTP request events are tracked via Rails instrumentation
    # BUG: E11y::Events::Rails::Http::Request class does not exist
    Given a Rails application with E11y enabled
    When an HTTP request to GET /health completes
    Then an HTTP request event should be tracked
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/rails_integration.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/rails_integration_steps.rb
# frozen_string_literal: true

Given("a Rails application in test environment") do
  skip_this_scenario unless defined?(::Rails)
  allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test")) rescue nil
  E11y.instance_variable_set(:@configuration, nil)
end

Given("a Rails application in production environment") do
  skip_this_scenario unless defined?(::Rails)
  @original_env = Rails.env
end

When("E11y Railtie initializes") do
  E11y.configure { |_c| }
  E11y::Railtie.instance_eval { run_initializers } rescue nil
end

Then("E11y.configuration.enabled should be false") do
  expect(E11y.configuration.enabled).to be(false),
    "Expected E11y to be auto-disabled in test env, but enabled=#{E11y.configuration.enabled}. " \
    "Bug: @enabled defaults to true in initialize, so nil? check in Railtie never fires."
end

Then("E11y.configuration.enabled should be true") do
  expect(E11y.configuration.enabled).to be(true)
end

Given("a Rails app with ApplicationJob inheriting from ActiveJob::Base") do
  skip_this_scenario unless defined?(::ApplicationJob) && defined?(::ActiveJob::Base)
end

When("E11y Railtie sets up ActiveJob integration") do
  E11y::Railtie.send(:setup_active_job) rescue nil
end

Then("the around_perform callback should be registered exactly once on ApplicationJob") do
  skip_this_scenario unless defined?(::ApplicationJob)
  callback_count = ApplicationJob._around_perform_callbacks.select do |cb|
    cb.filter.to_s.include?("E11y")
  end.count
  expect(callback_count).to eq(1),
    "Expected 1 E11y around_perform callback but found #{callback_count}. " \
    "Bug: setup_active_job includes callbacks into both ApplicationJob and ActiveJob::Base, " \
    "causing double-registration since ApplicationJob inherits from ActiveJob::Base."
end

Given("a Rails application with E11y enabled") do
  skip_this_scenario unless defined?(::Rails)
  E11y.configure do |c|
    c.enabled = true
    c.rails_instrumentation.enabled = true
    c.adapters[:default] = E11y::Adapters::InMemory.new
  end
end

Given("the Rails instrumentation is configured for SQL queries") do
  E11y.configuration.rails_instrumentation.track_database_queries = true
end

When("a SQL query {string} is executed") do |sql|
  ActiveSupport::Notifications.instrument("sql.active_record", sql: sql, name: "test")
end

Then("an SQL query event should be tracked") do
  adapter = E11y.configuration.adapters[:default]
  expect(adapter.event_count).to be >= 1,
    "Expected SQL query to generate an E11y event, but none received. " \
    "Bug: E11y::Events::Rails::Database::Query class does not exist — subscription fails silently."
end

When("an HTTP request to {word} {word} completes") do |_method, _path|
  ActiveSupport::Notifications.instrument(
    "process_action.action_controller",
    controller: "HealthController",
    action: "show",
    status: 200,
    method: "GET",
    path: "/health",
    duration: 15.0
  )
end

Then("an HTTP request event should be tracked") do
  adapter = E11y.configuration.adapters[:default]
  expect(adapter.event_count).to be >= 1,
    "Expected HTTP request to generate an E11y event, but none received. " \
    "Bug: E11y::Events::Rails::Http::Request class does not exist."
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/rails_integration.feature
```
Expected: "auto-disabled in test" FAILS, "ActiveJob once" FAILS, instrumentation scenarios FAIL.

**Step 5: Commit**

```bash
git add features/rails_integration.feature features/step_definitions/rails_integration_steps.rb
git commit -m "test(cucumber): Rails integration bugs — test auto-disable, double callback, missing event classes"
```

---

## Feature 11: Auto-Metrics Generation

**Files:**
- Create: `features/auto_metrics.feature`
- Create: `features/step_definitions/auto_metrics_steps.rb`

### Task 11: Scenarios for metrics DSL and Yabeda integration

**Step 1: Write feature file**

```gherkin
# features/auto_metrics.feature
Feature: Auto-metrics generation from event definitions

  # README: "Define metrics alongside events"
  # Example: counter :orders_created_total, "Orders created"

  Background:
    Given E11y is configured with an in-memory adapter

  Scenario: Event with counter metric emits counter on track
    Given an event class "OrderCreated" with a counter metric "orders_created_total"
    When I track an OrderCreated event
    Then the metric "orders_created_total" should have been incremented

  Scenario: Event with histogram metric emits histogram on track
    Given an event class "OrderFulfilled" with a histogram metric "fulfillment_seconds"
    When I track an OrderFulfilled event with value 1.5
    Then the histogram "fulfillment_seconds" should have been observed with value 1.5

  Scenario: Metrics are not emitted if Yabeda middleware is not in pipeline
    # BUG: Yabeda middleware is not in the default pipeline
    Given an event class "Metered" with a counter metric "metered_total"
    And the Yabeda middleware is NOT in the pipeline
    When I track a Metered event
    Then the metric "metered_total" should NOT have been emitted
    But a clear warning should explain how to enable metrics

  Scenario: Metrics cardinality protection refuses high-cardinality labels
    Given metrics cardinality protection is configured with max 100 values per label
    And an event class "HighCard" with a counter metric "highcard_total" labeled by "user_id"
    When I track 101 HighCard events each with a different user_id
    Then the metric should have been emitted for the first 100 user_ids only
    And a cardinality warning should have been logged
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/auto_metrics.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/auto_metrics_steps.rb
# frozen_string_literal: true

Given("an event class {string} with a counter metric {string}") do |class_name, metric_name|
  @metric_name = metric_name
  klass = Class.new(E11y::Event::Base) do
    schema { required(:id).filled(:string) }
    metrics do
      counter metric_name.to_sym, "Test counter"
    end
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
end

Given("an event class {string} with a histogram metric {string}") do |class_name, metric_name|
  @metric_name = metric_name
  klass = Class.new(E11y::Event::Base) do
    schema { required(:value).filled(:float) }
    metrics do
      histogram metric_name.to_sym, "Test histogram"
    end
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
end

Given("an event class {string} with a counter metric {string} labeled by {string}") do |class_name, metric_name, label|
  @metric_name = metric_name
  @label = label
  klass = Class.new(E11y::Event::Base) do
    schema { required(label.to_sym).filled(:string) }
    metrics do
      counter metric_name.to_sym, "High cardinality counter", labels: [label.to_sym]
    end
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
end

Given("the Yabeda middleware is NOT in the pipeline") do
  # default pipeline should not have it — verify
  pipeline = E11y.configuration.pipeline
  middleware_classes = pipeline.middleware_classes rescue []
  expect(middleware_classes).not_to include(E11y::Middleware::Yabeda)
end

Given("metrics cardinality protection is configured with max {int} values per label") do |max|
  E11y.configuration.metrics.cardinality_limit = max
end

When("I track an {word} event") do |class_name|
  @metric_error = nil
  begin
    Object.const_get(class_name).track(id: "test-1")
  rescue => e
    @metric_error = e
  end
end

When("I track an {word} event with value {float}") do |class_name, value|
  Object.const_get(class_name).track(value: value)
end

When("I track {int} {word} events each with a different user_id") do |count, class_name|
  count.times { |i| Object.const_get(class_name).track(user_id: "user-#{i}") }
end

Then("the metric {string} should have been incremented") do |metric_name|
  registry = E11y::Metrics::Registry.instance
  metric = registry.find(metric_name)
  expect(metric).not_to be_nil, "Metric '#{metric_name}' not registered"
  expect(metric.value).to eq(1)
end

Then("the histogram {string} should have been observed with value {float}") do |metric_name, value|
  registry = E11y::Metrics::Registry.instance
  metric = registry.find(metric_name)
  expect(metric).not_to be_nil
  expect(metric.observations).to include(value)
end

Then("the metric {string} should NOT have been emitted") do |metric_name|
  registry = E11y::Metrics::Registry.instance
  metric = registry.find(metric_name)
  expect(metric&.value.to_i).to eq(0)
end

Then("a clear warning should explain how to enable metrics") do
  pending "No warning is currently emitted when metrics are defined but Yabeda middleware is absent"
end

Then("the metric should have been emitted for the first {int} user_ids only") do |max|
  registry = E11y::Metrics::Registry.instance
  metric = registry.find(@metric_name)
  unique_label_values = metric&.label_value_count(@label.to_sym)
  expect(unique_label_values).to be <= max
end

Then("a cardinality warning should have been logged") do
  # Check that E11y self-monitoring emitted a cardinality alert
  adapter = in_memory_adapter
  cardinality_events = adapter.events.select { |e| e[:event_name].to_s.include?("cardinality") }
  expect(cardinality_events.size).to be >= 1
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/auto_metrics.feature
```

**Step 5: Commit**

```bash
git add features/auto_metrics.feature features/step_definitions/auto_metrics_steps.rb
git commit -m "test(cucumber): auto-metrics — Yabeda not in pipeline, cardinality protection coverage"
```

---

## Feature 12: Event Name Derivation and Versioning

**Files:**
- Create: `features/event_versioning.feature`
- Create: `features/step_definitions/event_versioning_steps.rb`

### Task 12: Versioning middleware bugs and event_name derivation

**Step 1: Write feature file**

```gherkin
# features/event_versioning.feature
Feature: Event naming and versioning

  Background:
    Given E11y is configured with an in-memory adapter

  Scenario: Event name is derived correctly from class name
    Given an event class "Events::OrderCreated" under the Events namespace
    When I track an Events::OrderCreated event
    Then the stored event should have event_name "order_created"

  Scenario: Custom event_name override is preserved
    # BUG: Versioning middleware unconditionally overwrites event_name
    Given an event class with custom event_name "legacy.order.placed"
    And the Versioning middleware is in the pipeline
    When I track the event
    Then the stored event should have event_name "legacy.order.placed"

  Scenario: V2 event correctly sets version number in payload
    Given a V2 event class "OrderPaidV2"
    And the Versioning middleware is in the pipeline
    When I track an OrderPaidV2 event
    Then the stored event should have version 2
    And the stored event should have event_name "order_paid"

  Scenario: Acronym in event class name is handled correctly
    # Edge case: UserID → should be user_id not user.i.d
    Given an event class "UserID" with no namespace
    And the Versioning middleware is in the pipeline
    When I track a UserID event
    Then the stored event should have event_name "user_id"

  Scenario: Versioning middleware is NOT active by default
    Given an event class "TestVersioned" with custom event_name "custom.name"
    When I track the event WITHOUT the Versioning middleware
    Then the stored event should have event_name "custom.name"
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/event_versioning.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/event_versioning_steps.rb
# frozen_string_literal: true

Given("an event class {string} under the Events namespace") do |full_name|
  parts = full_name.split("::")
  class_name = parts.last
  klass = Class.new(E11y::Event::Base) do
    schema { required(:id).filled(:string) }
  end
  unless Object.const_defined?(full_name)
    mod = parts[0..-2].inject(Object) { |m, p| m.const_defined?(p) ? m.const_get(p) : m.const_set(p, Module.new) }
    mod.const_set(class_name, klass)
  end
  @tracked_event_class = Object.const_get(full_name)
end

Given("an event class with custom event_name {string}") do |custom_name|
  @custom_name = custom_name
  klass = Class.new(E11y::Event::Base) do
    self.event_name = custom_name
    schema { required(:id).filled(:string) }
  end
  Object.const_set("CustomNamedEvent", klass) unless Object.const_defined?("CustomNamedEvent")
  @tracked_event_class = Object.const_get("CustomNamedEvent")
end

Given("the Versioning middleware is in the pipeline") do
  E11y.configuration.pipeline.use(E11y::Middleware::Versioning)
end

Given("a V2 event class {string}") do |name|
  klass = Class.new(E11y::Event::Base) do
    schema { required(:order_id).filled(:string) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
  @tracked_event_class = Object.const_get(name)
end

Given("an event class {string} with no namespace") do |name|
  klass = Class.new(E11y::Event::Base) do
    schema { required(:id).filled(:string) }
  end
  Object.const_set(name, klass) unless Object.const_defined?(name)
  @tracked_event_class = Object.const_get(name)
end

Given("an event class {string} with custom event_name {string}") do |class_name, custom_name|
  @custom_name = custom_name
  klass = Class.new(E11y::Event::Base) do
    self.event_name = custom_name
    schema { required(:id).filled(:string) }
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
  @tracked_event_class = Object.const_get(class_name)
end

When("I track an Events::OrderCreated event") do
  @tracked_event_class.track(id: "1")
end

When("I track the event") do
  @tracked_event_class.track(id: "1")
end

When("I track an OrderPaidV2 event") do
  OrderPaidV2.track(order_id: "ord-1")
end

When("I track a UserID event") do
  UserID.track(id: "1")
end

When("I track the event WITHOUT the Versioning middleware") do
  @tracked_event_class.track(id: "1")
end

Then("the stored event should have event_name {string}") do |expected|
  last = in_memory_adapter.last_events(1).first
  actual = last[:event_name]
  expect(actual).to eq(expected),
    "Expected event_name '#{expected}' but got '#{actual}'. " \
    "Versioning middleware may have overwritten custom event_name."
end

Then("the stored event should have version {int}") do |version|
  last = in_memory_adapter.last_events(1).first
  actual = last[:v] || last[:version]
  expect(actual).to eq(version)
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/event_versioning.feature
```
Expected: "custom event_name preserved" FAILS when Versioning is active, "UserID → user_id" may fail.

**Step 5: Commit**

```bash
git add features/event_versioning.feature features/step_definitions/event_versioning_steps.rb
git commit -m "test(cucumber): versioning — custom event_name overwrite bug, acronym handling"
```

---

## Feature 13: AuditEncrypted Adapter

**Files:**
- Create: `features/audit_encrypted.feature`
- Create: `features/step_definitions/audit_encrypted_steps.rb`

### Task 13: Key stability and thread safety

**Step 1: Write feature file**

```gherkin
# features/audit_encrypted.feature
Feature: AuditEncrypted adapter

  # Bug 1: Default key is random (new key every process start — data unreadable after restart)
  # Bug 2: File write is not thread-safe (no mutex)

  Scenario: Encrypted data is readable after adapter re-initialization (key stability)
    # BUG: Without E11Y_AUDIT_KEY, a new random key is generated each time
    Given an AuditEncrypted adapter without E11Y_AUDIT_KEY set
    And I write an event to the adapter
    When I create a NEW AuditEncrypted adapter instance (simulating restart)
    And I try to read back the event
    Then the event data should be decryptable
    And the decrypted content should match the original

  Scenario: Encrypted data readable when E11Y_AUDIT_KEY is set
    Given E11Y_AUDIT_KEY is set to "a" * 32 hex characters
    And an AuditEncrypted adapter using the env var key
    When I write and then read back an event
    Then the event should be decryptable

  Scenario: Concurrent writes do not corrupt the audit file
    # BUG: File.write in append mode is not thread-safe
    Given an AuditEncrypted adapter writing to a temp file
    When 10 threads each write an event concurrently
    Then the audit file should contain exactly 10 valid JSON entries
    And no entry should be malformed (partial/interleaved JSON)
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/audit_encrypted.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/audit_encrypted_steps.rb
# frozen_string_literal: true

Given("an AuditEncrypted adapter without E11Y_AUDIT_KEY set") do
  ENV.delete("E11Y_AUDIT_KEY")
  require "tmpdir"
  @temp_audit_file = File.join(Dir.tmpdir, "e11y_audit_test_#{Process.pid}.enc")
  @adapter1 = E11y::Adapters::AuditEncrypted.new(file_path: @temp_audit_file)
  @key1 = @adapter1.instance_variable_get(:@encryption_key)
end

Given("I write an event to the adapter") do
  @original_event = { event_name: "user_deleted", user_id: "usr-123", action: "delete" }
  @adapter1.write(@original_event)
end

When("I create a NEW AuditEncrypted adapter instance \\(simulating restart)") do
  # New instance = new random key (the bug)
  @adapter2 = E11y::Adapters::AuditEncrypted.new(file_path: @temp_audit_file)
  @key2 = @adapter2.instance_variable_get(:@encryption_key)
end

When("I try to read back the event") do
  @decrypted = nil
  @decrypt_error = nil
  begin
    @decrypted = @adapter2.read_all.first
  rescue => e
    @decrypt_error = e
  end
end

Then("the event data should be decryptable") do
  expect(@decrypt_error).to be_nil,
    "Decryption failed with #{@decrypt_error&.class}: #{@decrypt_error&.message}. " \
    "Bug: AuditEncrypted generates new random key on each initialization when E11Y_AUDIT_KEY not set."
end

Then("the decrypted content should match the original") do
  expect(@decrypted).to include(@original_event)
  File.delete(@temp_audit_file) if File.exist?(@temp_audit_file)
end

Given("E11Y_AUDIT_KEY is set to {string} hex characters") do |key_spec|
  hex_key = "a" * 64  # 32 bytes as hex
  ENV["E11Y_AUDIT_KEY"] = hex_key
end

Given("an AuditEncrypted adapter using the env var key") do
  require "tmpdir"
  @temp_audit_file = File.join(Dir.tmpdir, "e11y_audit_env_#{Process.pid}.enc")
  @adapter1 = E11y::Adapters::AuditEncrypted.new(file_path: @temp_audit_file)
end

When("I write and then read back an event") do
  @original_event = { event_name: "test", id: "xyz" }
  @adapter1.write(@original_event)
  adapter2 = E11y::Adapters::AuditEncrypted.new(file_path: @temp_audit_file)
  @decrypted = adapter2.read_all.first
  File.delete(@temp_audit_file) if File.exist?(@temp_audit_file)
  ENV.delete("E11Y_AUDIT_KEY")
end

Then("the event should be decryptable") do
  expect(@decrypted).to include(@original_event)
end

Given("an AuditEncrypted adapter writing to a temp file") do
  require "tmpdir"
  ENV["E11Y_AUDIT_KEY"] = "b" * 64
  @temp_audit_file = File.join(Dir.tmpdir, "e11y_audit_concurrent_#{Process.pid}.enc")
  @adapter = E11y::Adapters::AuditEncrypted.new(file_path: @temp_audit_file)
end

When("{int} threads each write an event concurrently") do |thread_count|
  threads = thread_count.times.map do |i|
    Thread.new { @adapter.write(event_name: "concurrent_event", thread_id: i) }
  end
  threads.each(&:join)
end

Then("the audit file should contain exactly {int} valid JSON entries") do |count|
  lines = File.readlines(@temp_audit_file).map(&:strip).reject(&:empty?)
  valid_entries = lines.select do |line|
    JSON.parse(line)
    true
  rescue JSON::ParserError
    false
  end
  malformed = lines.count - valid_entries.count
  expect(valid_entries.count).to eq(count),
    "Expected #{count} valid entries, got #{valid_entries.count} valid + #{malformed} malformed. " \
    "AuditEncrypted#write_to_storage is not thread-safe."
end

Then("no entry should be malformed \\(partial\\/interleaved JSON)") do
  lines = File.readlines(@temp_audit_file).map(&:strip).reject(&:empty?)
  malformed = lines.reject { |line| JSON.parse(line) rescue false }
  expect(malformed).to be_empty,
    "Found #{malformed.count} malformed entries: #{malformed.first(3).inspect}"
  File.delete(@temp_audit_file) if File.exist?(@temp_audit_file)
  ENV.delete("E11Y_AUDIT_KEY")
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/audit_encrypted.feature
```
Expected: "key stability" FAILS (different key after restart), "concurrent writes" MAY fail.

**Step 5: Commit**

```bash
git add features/audit_encrypted.feature features/step_definitions/audit_encrypted_steps.rb
git commit -m "test(cucumber): AuditEncrypted — random key bug, thread safety"
```

---

## Feature 14: Default Pipeline Completeness

**Files:**
- Create: `features/default_pipeline.feature`
- Create: `features/step_definitions/default_pipeline_steps.rb`

### Task 14: Verify what IS and ISN'T in the default pipeline

**Step 1: Write feature file**

```gherkin
# features/default_pipeline.feature
Feature: Default pipeline middleware composition

  # The default pipeline includes: TraceContext, Validation, PIIFilter,
  #   AuditSigning, Sampling, Routing
  # Documented-but-missing: RateLimiting, EventSlo, Versioning

  Scenario: Validation middleware is active by default
    Given E11y is configured with default settings
    And an event class "Validated" with required field "id" of type string
    When I track a Validated event without required field
    Then a validation error should be raised

  Scenario: RateLimiting middleware is NOT active by default (explicit opt-in required)
    # README implies rate limiting "just works" but it's not in default pipeline
    Given E11y is configured with default settings
    Then the default pipeline should NOT include RateLimiting middleware
    And the rate limiting config should default to disabled

  Scenario: EventSlo middleware is NOT active by default
    # README: "Event-Driven SLO" but EventSlo not in default pipeline
    Given E11y is configured with default settings
    Then the default pipeline should NOT include EventSlo middleware

  Scenario: Pipeline built_pipeline terminal is a no-op (events silently dropped if Routing absent)
    Given E11y is configured with an in-memory adapter
    And the Routing middleware is removed from the pipeline
    When I track an event
    Then the in-memory adapter should have received 0 events

  Scenario: Default pipeline processes events end-to-end
    Given E11y is configured with an in-memory adapter
    And an event class "E2E" with required field "value" of type string
    When I track an E2E event with value "hello"
    Then the in-memory adapter should have received 1 event
    And the last event should have field "value" equal to "hello"
```

**Step 2: Run to verify failures**

```bash
bundle exec cucumber features/default_pipeline.feature
```

**Step 3: Write step definitions**

```ruby
# features/step_definitions/default_pipeline_steps.rb
# frozen_string_literal: true

Then("the default pipeline should NOT include {word} middleware") do |middleware_name|
  middleware_class = E11y::Middleware.const_get(middleware_name) rescue nil
  next unless middleware_class
  pipeline = E11y.configuration.pipeline
  included = pipeline.middleware_classes.include?(middleware_class) rescue false
  expect(included).to be(false),
    "#{middleware_name} should not be in default pipeline per documentation (requires opt-in)"
end

Then("the rate limiting config should default to disabled") do
  expect(E11y.configuration.rate_limiting.enabled).to be(false),
    "Rate limiting should default to disabled (opt-in feature)"
end

And("the Routing middleware is removed from the pipeline") do
  E11y.configuration.pipeline.remove(E11y::Middleware::Routing) rescue nil
end
```

**Step 4: Run**

```bash
bundle exec cucumber features/default_pipeline.feature
```

**Step 5: Commit**

```bash
git add features/default_pipeline.feature features/step_definitions/default_pipeline_steps.rb
git commit -m "test(cucumber): default pipeline — RateLimiting, EventSlo not included, terminal no-op"
```

---

## Feature 15: Schema Validation DSL

**Files:**
- Create: `features/schema_validation.feature`

### Task 15: Schema validation correctness scenarios

**Step 1: Write feature file**

```gherkin
# features/schema_validation.feature
Feature: Schema-validated business events

  Background:
    Given E11y is configured with an in-memory adapter

  Scenario: Event with all required fields passes validation
    Given an event class "OrderPlaced" with schema:
      """
      required(:order_id).filled(:string)
      required(:amount).filled(:float)
      optional(:notes).maybe(:string)
      """
    When I track an OrderPlaced event with order_id "123" and amount 99.99
    Then the in-memory adapter should have received 1 event

  Scenario: Missing required field raises validation error with descriptive message
    Given an event class "OrderPlaced" with schema:
      """
      required(:order_id).filled(:string)
      required(:amount).filled(:float)
      """
    When I track an OrderPlaced event with only order_id "123"
    Then a validation error should be raised
    And the error message should mention "amount"

  Scenario: Wrong type for required field raises validation error
    Given an event class "TypedEvent" with schema:
      """
      required(:count).filled(:integer)
      """
    When I track a TypedEvent event with count "not-a-number"
    Then a validation error should be raised

  Scenario: Optional field can be nil
    Given an event class "NullableEvent" with schema:
      """
      required(:name).filled(:string)
      optional(:description).maybe(:string)
      """
    When I track a NullableEvent event with name "test" and description nil
    Then the in-memory adapter should have received 1 event

  Scenario: Extra undeclared fields are not stored in payload
    Given an event class "StrictEvent" with schema:
      """
      required(:name).filled(:string)
      """
    When I track a StrictEvent event with name "ok" and undeclared extra: "value"
    Then the stored event should not contain field "extra"
```

**Step 2: Add multi-line schema step to shared steps**

In `features/step_definitions/shared_steps.rb`, add:

```ruby
Given("an event class {string} with schema:") do |class_name, schema_text|
  klass = Class.new(E11y::Event::Base)
  klass.schema do
    instance_eval(schema_text)
  end
  Object.const_set(class_name, klass) unless Object.const_defined?(class_name)
end

Then("the error message should mention {string}") do |field|
  expect(@error.message).to include(field),
    "Expected error message to mention '#{field}' but got: #{@error.message}"
end

When("I track a {word} event with only {word} {string}") do |class_name, field, value|
  @error = nil
  begin
    Object.const_get(class_name).track(field.to_sym => value)
  rescue => e
    @error = e
  end
end
```

**Step 3: Run**

```bash
bundle exec cucumber features/schema_validation.feature
```

**Step 4: Commit**

```bash
git add features/schema_validation.feature
git commit -m "test(cucumber): schema validation DSL — required fields, type checking, nil handling"
```

---

## Final Task: Master Run + Failure Report

### Task 16: Run full suite and capture failure inventory

**Step 1: Run all Cucumber features**

```bash
bundle exec cucumber features/ --format progress 2>&1 | tee /tmp/cucumber_run.txt
```

**Step 2: Count failures**

```bash
grep -E "^(F|failing|failed)" /tmp/cucumber_run.txt | wc -l
```

**Step 3: Generate structured failure report**

```bash
bundle exec cucumber features/ --format json --out cucumber_results.json
```

**Step 4: Commit report artifacts**

```bash
git add cucumber_results.json
git commit -m "test(cucumber): initial run — captures all documented feature discrepancies"
```

---

## Summary of Expected Failures

| Feature | Scenario | Expected Failure Reason |
|---------|----------|------------------------|
| Event Tracking | `E11y.track` works | `NotImplementedError` raised |
| InMemory API | `last_event` | `NoMethodError` (method doesn't exist) |
| InMemory API | `event_count("name")` positional | `ArgumentError` (needs keyword) |
| Request Buffer | Debug events flush on error | `flush_event` is a stub, 0 events flushed |
| SLO Tracking | Enabled by default | `@enabled = false` in config |
| SLO Tracking | `Tracker.status` exists | `NoMethodError` |
| SLO Tracking | EventSlo in default pipeline | Middleware not added |
| PII Filtering | `"api_key_rotation_completed"` preserved | Regex corrupts value |
| PII Filtering | `"password validation"` preserved | Regex corrupts value |
| PII Filtering | Tier2 without Rails | `NoMethodError` on `Rails.application` |
| Adapters | `Stdout format: :pretty` respected | Silently ignored, uses `pretty_print:` |
| Adapters | Sentry doesn't wipe existing config | `Sentry.init` called unconditionally |
| Adapters | Loki `healthy?` checks network | Always `true` (never contacts Loki) |
| Adapters | OTel forwards business fields | Blocked by `baggage_allowlist` |
| Presets | `AuditEvent` sets `audit_event true` | Empty `class_eval` block |
| Sampling | Normal-threshold load → `:normal` | Returns `:high` (off-by-one bug) |
| DLQ | `replay` re-dispatches event | Stub, does nothing |
| DLQ | `delete` returns `true` | Always returns `false` |
| DLQ | No Rails for default path | `NameError: Rails` |
| Rails Integration | Auto-disabled in test env | `@enabled = true` default blocks detection |
| Rails Integration | ActiveJob callback once | Registered twice |
| Rails Integration | SQL query tracked | Event class doesn't exist |
| AuditEncrypted | Key stable across restarts | New random key each time |
| AuditEncrypted | Thread-safe writes | `File.write` without mutex |
| Versioning | Custom `event_name` preserved | Unconditionally overwritten |
| Event naming | `UserID` → `user_id` | May produce `user.i.d` |
| Default Pipeline | RateLimiting inactive | Confirmed disabled by default |
| Default Pipeline | EventSlo inactive | Not in pipeline |
