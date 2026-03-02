# Rails Integration — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that the Rails Railtie correctly integrates E11y into a Rails app — exposing that the auto-disable guard for the test environment is broken, ActiveJob callbacks are registered twice, and Rails instrumentation subscriptions reference event classes that don't exist.

**Approach:** Use the dummy Rails app (already running in test env) to introspect integration state. Check configuration flags, callback registration counts, and whether subscriptions raise on event delivery.

**Known bugs covered:**
- `config.enabled = !Rails.env.test? if config.enabled.nil?` — guard never fires: `@enabled` defaults to `true` (not `nil`), so E11y is never auto-disabled in the test environment.
- `E11y::Railtie` registers ActiveJob `around_perform` on both `ApplicationJob` and `ActiveJob::Base` — callbacks fire twice per job.
- `E11y::Events::Rails::Database::Query`, `E11y::Events::Rails::Request::Processed`, etc. — these event classes don't exist; `ActiveSupport::Notifications.subscribe` callbacks will raise `NameError` silently.
- `E11y::LoggerBridge` requires a non-existent file on load → `LoadError` if ever required.

---

## Task 1: Feature file

**Files:**
- Create: `features/rails_integration.feature`

**Step 1: Write the feature file**

```gherkin
# features/rails_integration.feature
@rails
Feature: Rails Railtie integration

  # E11y ships a Railtie that hooks into the Rails lifecycle:
  #   - Auto-disables E11y in test environment
  #   - Registers around_perform on ActiveJob for request context propagation
  #   - Subscribes to ActiveSupport::Notifications for DB queries, requests, etc.
  #
  # BUG 1: Auto-disable guard checks enabled.nil? but @enabled defaults to true.
  #         E11y remains enabled in test env unless user explicitly sets enabled: false.
  # BUG 2: around_perform registered on BOTH ApplicationJob and ActiveJob::Base.
  #         Callbacks fire twice per job execution.
  # BUG 3: ActiveSupport::Notifications subscriptions reference missing event classes
  #         (E11y::Events::Rails::*) — delivers raise NameError silently.

  Background:
    Given the application is running

  @wip
  Scenario: E11y is automatically disabled in the test environment
    # BUG: @enabled = true by default, so the nil? guard never triggers.
    # E11y stays enabled — every tracked event in tests hits real adapters.
    Then E11y should be disabled in the test environment

  Scenario: E11y configuration can be explicitly disabled
    # Workaround: user must manually set enabled: false in test.rb.
    # Verifies the flag itself works when explicitly set.
    When I set E11y enabled to false
    Then E11y should be disabled in the test environment
    And I restore E11y enabled to true

  @wip
  Scenario: ActiveJob around_perform callback is registered exactly once
    # BUG: Railtie registers on ApplicationJob AND ActiveJob::Base.
    # Result: around_perform fires twice per job — double context injection,
    # double event emission, potential double billing in metrics.
    Then the E11y around_perform callback should be registered exactly 1 time on ActiveJob::Base

  Scenario: ActiveJob around_perform callback exists
    # Documents that SOME callback registration happens (even if duplicated).
    Then at least 1 E11y around_perform callback should exist on ActiveJob::Base

  @wip
  Scenario: ActiveSupport::Notifications subscription for sql.active_record does not raise
    # BUG: The subscriber tries to instantiate E11y::Events::Rails::Database::Query
    # which doesn't exist. Fires: NameError: uninitialized constant
    # E11y::Events::Rails::Database::Query
    When ActiveSupport::Notifications publishes "sql.active_record"
    Then no error should have been raised

  @wip
  Scenario: ActiveSupport::Notifications subscription for process_action.action_controller does not raise
    # BUG: The subscriber tries to instantiate E11y::Events::Rails::Request::Processed
    # which doesn't exist → NameError.
    When ActiveSupport::Notifications publishes "process_action.action_controller"
    Then no error should have been raised

  Scenario: Railtie does not break the Rails app boot
    # Smoke test: dummy app loads and responds to requests.
    When I GET "/posts"
    Then the response status should be 200
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/rails_integration.feature --dry-run
```

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/rails_integration_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/rails_integration_steps.rb
# frozen_string_literal: true

Then("E11y should be disabled in the test environment") do
  expect(E11y.configuration.enabled).to be(false),
    "Expected E11y.configuration.enabled to be false in test environment, " \
    "but it was #{E11y.configuration.enabled.inspect}. " \
    "BUG: Railtie guard `if config.enabled.nil?` never fires because " \
    "@enabled defaults to true, not nil."
end

When("I set E11y enabled to {word}") do |value|
  @original_enabled = E11y.configuration.enabled
  E11y.configuration.enabled = (value == "true")
end

And("I restore E11y enabled to {word}") do |value|
  E11y.configuration.enabled = (value == "true")
end

Then("the E11y around_perform callback should be registered exactly {int} time(s) on ActiveJob::Base") do |count|
  skip_this_scenario unless defined?(::ActiveJob)
  callbacks = ActiveJob::Base
    ._around_perform_callbacks
    .select { |cb| cb.filter.to_s.include?("E11y") || cb.filter.to_s.include?("e11y") }
  expect(callbacks.size).to eq(count),
    "Expected exactly #{count} E11y around_perform callback on ActiveJob::Base, " \
    "but found #{callbacks.size}. " \
    "BUG: Railtie registers on both ApplicationJob and ActiveJob::Base — " \
    "callbacks fire twice per job."
end

Then("at least {int} E11y around_perform callback(s) should exist on ActiveJob::Base") do |min|
  skip_this_scenario unless defined?(::ActiveJob)
  callbacks = ActiveJob::Base
    ._around_perform_callbacks
    .select { |cb| cb.filter.to_s.include?("E11y") || cb.filter.to_s.include?("e11y") }
  expect(callbacks.size).to be >= min,
    "Expected >= #{min} E11y around_perform callbacks, found #{callbacks.size}."
end

When("ActiveSupport::Notifications publishes {string}") do |event_name|
  @notification_error = nil
  payload = case event_name
            when "sql.active_record"
              { sql: "SELECT 1", name: "Test Load", duration: 0.5 }
            when "process_action.action_controller"
              { controller: "PostsController", action: "index",
                format: :html, method: "GET", path: "/posts",
                status: 200, view_runtime: 1.0, db_runtime: 0.5 }
            else
              {}
            end
  begin
    ActiveSupport::Notifications.instrument(event_name, payload)
  rescue NameError => e
    @notification_error = e
  end
end

Then("no error should have been raised") do
  expect(@notification_error).to be_nil,
    "Got #{@notification_error&.class}: #{@notification_error&.message}. " \
    "BUG: Railtie subscribes to AS::Notifications but the event class " \
    "(e.g. E11y::Events::Rails::Database::Query) doesn't exist."
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/rails_integration.feature
```

Expected:
- `E11y config can be explicitly disabled` → **PASS**
- `at least 1 around_perform callback exists` → **PASS**
- `Railtie does not break Rails app boot` → **PASS**
- `@wip` scenarios → **PENDING** (skipped by default)

Run wip:
```bash
bundle exec cucumber features/rails_integration.feature --tags @wip
```
Expected: `auto-disable test env` **FAIL**, `exactly 1 callback` **FAIL**, both notification subscriptions **FAIL**.

**Step 3: Commit**

```bash
git add features/rails_integration.feature \
        features/step_definitions/rails_integration_steps.rb
git commit -m "test(cucumber): Rails integration — auto-disable guard, double callback, missing event classes"
```
