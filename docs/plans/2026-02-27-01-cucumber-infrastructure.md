# Cucumber Infrastructure — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stand up the complete Cucumber test infrastructure so that all subsequent feature plans can be executed against the dummy Rails app via Rack::Test.

**Approach:** Cucumber is configured to load the dummy Rails app at `spec/dummy/` by requiring its environment file from `features/support/env.rb`. All HTTP interactions use `Rack::Test` mixed into Cucumber's World object, so every step definition that makes an HTTP request goes through the full Rack middleware stack without a real server. The memory adapter (`E11y.config.adapters[:memory]`) is cleared in a `Before` hook so each scenario starts with an empty event log.

**Known bugs covered:**
- None — this plan only sets up infrastructure. Downstream plans expose bugs.

---

## Overview of files to create

```
features/
  support/
    env.rb
    world_extensions.rb
    hooks.rb
  step_definitions/
    common_steps.rb
Rakefile  (additions only — append cucumber tasks to existing file)
```

Gemfile addition (in `:development` group):
```ruby
gem "cucumber",        "~> 9.0"
gem "cucumber-rails",  "~> 3.0", require: false
gem "rack-test",       "~> 2.1"
```

---

## Task 1 — Add Cucumber gems to Gemfile

**Files to edit:** `/Users/aseletskiy/projects/recruit/e11y/Gemfile`

### Step 1 — Edit Gemfile

Add inside the existing `group :development` block (after `pry-byebug`):

```ruby
# Cucumber acceptance tests
gem "cucumber",        "~> 9.0"
gem "cucumber-rails",  "~> 3.0", require: false
gem "rack-test",       "~> 2.1"
```

`rack-test` is already a transitive dependency of `rails` but adding it explicitly pins the version and makes the intent clear.

### Step 2 — Install gems

```bash
bundle install --with development
```

### Step 3 — Verify Cucumber executable is available

```bash
bundle exec cucumber --version
```

Expected: prints a version string such as `9.x.x`. If `cucumber` is not found, diagnose the Gemfile edit.

### Step 4 — Commit

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add cucumber, cucumber-rails, rack-test to development group"
```

---

## Task 2 — Create `features/support/env.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/support/env.rb`

### Step 1 — Write the file

```ruby
# frozen_string_literal: true

# features/support/env.rb
#
# Cucumber environment bootstrap.
# Loads the dummy Rails application and wires Rack::Test into World.
#
# Load order matters:
#   1. Set RAILS_ENV so Rails boots in test mode.
#   2. Require the dummy app's environment (which calls require "e11y" internally).
#   3. Initialize the Rails application exactly once.
#   4. Load all dummy app source files (controllers, events, models) because
#      config.eager_load = false in the dummy app.

ENV["RAILS_ENV"] = "test"
ENV["E11Y_AUDIT_SIGNING_KEY"] ||= "test_signing_key_for_cucumber_tests_only"
ENV["E11Y_RATE_LIMITING_ENABLED"] = "false"

# Locate the dummy app relative to the features/ directory.
DUMMY_APP_PATH = File.expand_path("../../spec/dummy", __dir__)

# Load the dummy Rails application environment.
# This defines the Dummy::Application class and configures E11y with the
# in-memory adapter at config.adapters[:memory].
require File.join(DUMMY_APP_PATH, "config/environment")

# Initialize the Rails application once.
# Guard against double-initialization if the suite is re-run without a fresh
# process (e.g., during interactive development with `binding.pry`).
unless $rails_app_initialized_for_cucumber # rubocop:disable Style/GlobalVars
  dummy_root = DUMMY_APP_PATH
  Rails.application.config.root = dummy_root unless Rails.application.config.root.to_s == dummy_root
  Rails.application.config.hosts.clear if Rails.application.config.respond_to?(:hosts)
  Rails.application.initialize!
  $rails_app_initialized_for_cucumber = true # rubocop:disable Style/GlobalVars
end

# Run pending database migrations.
ActiveRecord::Base.establish_connection
ActiveRecord::Migration.suppress_messages do
  ActiveRecord::MigrationContext.new(
    File.join(DUMMY_APP_PATH, "db/migrate")
  ).migrate
end

# Eagerly load all dummy app Ruby files.
# The dummy app disables eager_load to avoid issues during multiple test runs,
# so we manually require every file here once.
Dir[File.join(DUMMY_APP_PATH, "app/**/*.rb")].sort.each do |file|
  require file unless File.basename(file).start_with?(".")
end

# Ensure Rails routes are loaded.
Rails.application.routes_reloader.reload! if Rails.application.routes.empty?

# Disable rate limiting globally — it interferes with test assertions.
E11y.configure do |config|
  config.rate_limiting.enabled = false if config.respond_to?(:rate_limiting)
end

# Require Rack::Test so World modules can include it.
require "rack/test"
```

### Step 2 — Dry-run to verify env.rb loads without error

```bash
bundle exec cucumber --dry-run features/ 2>&1 | head -30
```

Expected output: either "0 scenarios" or a list of undefined step snippets — NOT a Ruby load error or Rails boot failure.

### Step 3 — Commit

```bash
git add features/support/env.rb
git commit -m "test(cucumber): add features/support/env.rb — boots dummy Rails app"
```

---

## Task 3 — Create `features/support/world_extensions.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/support/world_extensions.rb`

### Step 1 — Write the file

```ruby
# frozen_string_literal: true

# features/support/world_extensions.rb
#
# World module mixed into every Cucumber scenario.
# Provides:
#   - Rack::Test HTTP helpers (get, post, last_response, etc.)
#   - memory_adapter   — direct access to E11y::Adapters::InMemory instance
#   - clear_events!    — empties the memory adapter
#   - last_tracked_event(type) — most recent event hash for a given class name
#   - tracked_events(type)     — all events for a given class name
#   - find_event_payload(type) — payload hash of the most recent event

module E11yWorldHelpers
  include Rack::Test::Methods

  # Required by Rack::Test — returns the Rack application under test.
  #
  # @return [Rails application]
  def app
    Rails.application
  end

  # Returns the singleton InMemory adapter registered as :memory.
  #
  # @return [E11y::Adapters::InMemory]
  def memory_adapter
    E11y.config.adapters[:memory]
  end

  # Clears all events from the memory adapter.
  # Called automatically in the Before hook; also available in step definitions.
  #
  # @return [void]
  def clear_events!
    memory_adapter.clear!
  end

  # Returns ALL events of the given class name string.
  #
  # Searches by :event_name key (which the event base class sets to the
  # fully-qualified class name, e.g., "Events::OrderCreated").
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Array<Hash>]
  def tracked_events(event_type)
    memory_adapter.find_events(event_type)
  end

  # Returns the most recently tracked event of the given type.
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Hash, nil]
  def last_tracked_event(event_type)
    tracked_events(event_type).last
  end

  # Returns the payload hash of the most recently tracked event of the given type.
  #
  # @param event_type [String] e.g. "Events::OrderCreated"
  # @return [Hash, nil]
  def find_event_payload(event_type)
    last_tracked_event(event_type)&.dig(:payload)
  end

  # Parses the last HTTP response body as JSON.
  #
  # @return [Hash, Array]
  # @raise [JSON::ParserError] if body is not valid JSON
  def parsed_response
    JSON.parse(last_response.body)
  end
end

World(E11yWorldHelpers)
```

### Step 2 — Verify world loads

```bash
bundle exec cucumber --dry-run features/ 2>&1 | head -20
```

Expected: no `NoMethodError` or `NameError` relating to `E11yWorldHelpers`.

### Step 3 — Commit

```bash
git add features/support/world_extensions.rb
git commit -m "test(cucumber): add World helpers — Rack::Test, memory_adapter, event finders"
```

---

## Task 4 — Create `features/support/hooks.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/support/hooks.rb`

### Step 1 — Write the file

```ruby
# frozen_string_literal: true

# features/support/hooks.rb
#
# Global Cucumber hooks that apply to every scenario unless tagged otherwise.

# Before each scenario: clear the memory adapter so events from one scenario
# do not bleed into the next.
Before do
  clear_events!
end

# After each scenario: clean the database so ActiveRecord models (e.g. Post)
# created during a scenario do not persist into the next.
After do
  if ActiveRecord::Base.connection.table_exists?("posts")
    ActiveRecord::Base.connection.execute("DELETE FROM posts")
  end
end

# Before hook for @wip scenarios: print a reminder that the scenario is
# expected to FAIL (exposes a known bug).
Before("@wip") do |scenario|
  # Cucumber marks @wip scenarios as pending by default when running with
  # --wip flag. Without --wip they run normally and are expected to fail.
  # No action needed here — the tag is informational for the runner.
end

# After hook for @wip scenarios: emit a warning if the scenario PASSED,
# because that would mean the bug was fixed and the @wip tag should be removed.
After("@wip") do |scenario|
  if scenario.passed?
    warn "\n[cucumber] WARNING: @wip scenario '#{scenario.name}' PASSED — " \
         "the underlying bug may be fixed. Remove @wip tag if confirmed.\n"
  end
end
```

### Step 2 — Verify hooks load

```bash
bundle exec cucumber --dry-run features/ 2>&1 | head -20
```

Expected: no errors, 0 scenarios executed.

### Step 3 — Commit

```bash
git add features/support/hooks.rb
git commit -m "test(cucumber): add Before/After hooks for event cleanup and DB cleanup"
```

---

## Task 5 — Create `features/step_definitions/common_steps.rb`

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/step_definitions/common_steps.rb`

### Step 1 — Write the file

```ruby
# frozen_string_literal: true

# features/step_definitions/common_steps.rb
#
# Step definitions reused across all feature files.
# These steps are generic: HTTP assertions, event count checks, field value checks.
# Feature-specific steps live in their own step_definitions/ file.

# ---------------------------------------------------------------------------
# Application state
# ---------------------------------------------------------------------------

# No-op step that verifies the Rails app is loaded and responding.
# Exists so feature files can document the precondition explicitly.
Given("the application is running") do
  # Rack::Test does not require a running server.
  # We verify the app is accessible by checking that Rails.application exists.
  expect(Rails.application).not_to be_nil
end

# ---------------------------------------------------------------------------
# HTTP response assertions
# ---------------------------------------------------------------------------

Then("the response status should be {int}") do |expected_status|
  expect(last_response.status).to eq(expected_status),
    "Expected HTTP #{expected_status} but got #{last_response.status}.\n" \
    "Response body: #{last_response.body}"
end

Then("the response body should contain {string}") do |expected_text|
  expect(last_response.body).to include(expected_text),
    "Expected response body to contain #{expected_text.inspect}.\n" \
    "Actual body: #{last_response.body}"
end

Then("the response body should be valid JSON") do
  expect { parsed_response }.not_to raise_error
end

# ---------------------------------------------------------------------------
# Event count assertions
# ---------------------------------------------------------------------------

# Matches both "1 event" and "3 events" (the (s) is optional via Cucumber grammar).
Then("{int} event(s) of type {string} should have been tracked") do |count, event_type|
  events = tracked_events(event_type)
  expect(events.size).to eq(count),
    "Expected #{count} event(s) of type '#{event_type}', " \
    "but found #{events.size}.\n" \
    "All events in adapter: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
end

Then("no event of type {string} should have been tracked") do |event_type|
  events = tracked_events(event_type)
  expect(events).to be_empty,
    "Expected no events of type '#{event_type}', but found #{events.size}.\n" \
    "Events: #{events.inspect}"
end

Then("at least {int} event(s) of type {string} should have been tracked") do |min_count, event_type|
  events = tracked_events(event_type)
  expect(events.size).to be >= min_count,
    "Expected at least #{min_count} event(s) of type '#{event_type}', " \
    "but found #{events.size}."
end

# ---------------------------------------------------------------------------
# Event payload field assertions
# ---------------------------------------------------------------------------

# Checks the payload field of the most recent event of the given type.
# Value is compared as a string (Gherkin only parses strings by default).
Then("the last {string} event's field {string} should equal {string}") do |event_type, field, expected_value|
  payload = find_event_payload(event_type)
  expect(payload).not_to be_nil,
    "No event of type '#{event_type}' was tracked. " \
    "Tracked event types: #{memory_adapter.events.map { |e| e[:event_name] }.uniq.inspect}"

  actual_value = payload[field.to_sym] || payload[field]
  expect(actual_value.to_s).to eq(expected_value),
    "Expected field '#{field}' to equal #{expected_value.inspect}, " \
    "but got #{actual_value.inspect}.\nFull payload: #{payload.inspect}"
end

# Checks the payload field against a Ruby Regexp pattern (passed as a string).
Then("the last {string} event's field {string} should match {string}") do |event_type, field, pattern_string|
  payload = find_event_payload(event_type)
  expect(payload).not_to be_nil,
    "No event of type '#{event_type}' was tracked."

  actual_value = payload[field.to_sym] || payload[field]
  expect(actual_value.to_s).to match(Regexp.new(pattern_string)),
    "Expected field '#{field}' to match /#{pattern_string}/, " \
    "but got #{actual_value.inspect}."
end

# Checks that a payload field has been filtered by the PII middleware.
# "Filtered" means the value is "[FILTERED]" or nil (redacted) or a SHA256 hex string (hashed).
Then("the last {string} event's field {string} should be filtered") do |event_type, field|
  payload = find_event_payload(event_type)
  expect(payload).not_to be_nil,
    "No event of type '#{event_type}' was tracked."

  actual_value = payload[field.to_sym] || payload[field]
  filtered_patterns = [
    "[FILTERED]",  # mask strategy
    nil,           # redact strategy removes the key
    /\A[0-9a-f]{64}\z/  # hash strategy (SHA256 hex)
  ]

  is_filtered = filtered_patterns.any? do |pattern|
    if pattern.is_a?(Regexp)
      actual_value.to_s.match?(pattern)
    else
      actual_value == pattern
    end
  end

  expect(is_filtered).to be(true),
    "Expected field '#{field}' to be filtered (nil, '[FILTERED]', or SHA256 hash), " \
    "but got: #{actual_value.inspect}.\nFull payload: #{payload.inspect}"
end

# Checks that a payload field is NOT filtered (i.e., value passes through unchanged).
Then("the last {string} event's field {string} should not be filtered") do |event_type, field|
  payload = find_event_payload(event_type)
  expect(payload).not_to be_nil,
    "No event of type '#{event_type}' was tracked."

  actual_value = payload[field.to_sym] || payload[field]
  expect(actual_value).not_to eq("[FILTERED]"),
    "Field '#{field}' was unexpectedly filtered.\nFull payload: #{payload.inspect}"
  expect(actual_value).not_to be_nil,
    "Field '#{field}' was unexpectedly nil (redacted).\nFull payload: #{payload.inspect}"
end

# ---------------------------------------------------------------------------
# Adapter-level assertions
# ---------------------------------------------------------------------------

Then("the memory adapter should have {int} total event(s)") do |count|
  expect(memory_adapter.event_count).to eq(count),
    "Expected #{count} total events in adapter, " \
    "but found #{memory_adapter.event_count}.\n" \
    "Event types: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
end

Then("the memory adapter should be empty") do
  expect(memory_adapter.event_count).to eq(0),
    "Expected adapter to be empty but found #{memory_adapter.event_count} events.\n" \
    "Event types: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
end
```

### Step 2 — Verify steps register without errors

```bash
bundle exec cucumber --dry-run features/ 2>&1
```

Expected: steps listed as defined (not undefined). If there are no `.feature` files yet, Cucumber will print "0 scenarios (0 undefined)" — that is fine.

### Step 3 — Commit

```bash
git add features/step_definitions/common_steps.rb
git commit -m "test(cucumber): add common_steps.rb — HTTP, event count, payload field assertions"
```

---

## Task 6 — Add Cucumber Rake tasks

**File to edit:** `/Users/aseletskiy/projects/recruit/e11y/Rakefile`

### Step 1 — Append cucumber tasks at the bottom of Rakefile

Add the following after the existing task definitions:

```ruby
# ---------------------------------------------------------------------------
# Cucumber acceptance tests
# ---------------------------------------------------------------------------
begin
  require "cucumber/rake/task"

  namespace :cucumber do
    desc "Run all Cucumber acceptance tests"
    Cucumber::Rake::Task.new(:all) do |t|
      t.cucumber_opts = "--format progress features/"
    end

    desc "Run only @wip (known-bug) Cucumber scenarios"
    Cucumber::Rake::Task.new(:wip) do |t|
      t.cucumber_opts = "--tags @wip --format progress features/"
    end

    desc "Run passing Cucumber scenarios (exclude @wip)"
    Cucumber::Rake::Task.new(:passing) do |t|
      t.cucumber_opts = "--tags 'not @wip' --format progress features/"
    end
  end

  desc "Run all Cucumber acceptance tests (alias for cucumber:all)"
  task cucumber: "cucumber:all"

rescue LoadError
  desc "Cucumber not available — install with: bundle install --with development"
  task :cucumber do
    warn "Cucumber gem is not available. Run: bundle install --with development"
  end
end
```

### Step 2 — Verify Rake tasks are registered

```bash
bundle exec rake --tasks | grep cucumber
```

Expected output (order may vary):
```
rake cucumber          # Run all Cucumber acceptance tests (alias for cucumber:all)
rake cucumber:all      # Run all Cucumber acceptance tests
rake cucumber:passing  # Run passing Cucumber scenarios (exclude @wip)
rake cucumber:wip      # Run only @wip (known-bug) Cucumber scenarios
```

### Step 3 — Run dry-run via Rake

```bash
bundle exec rake cucumber:all -- --dry-run 2>&1 | head -20
```

Expected: exits without error, "0 scenarios" (no feature files written yet).

### Step 4 — Commit

```bash
git add Rakefile
git commit -m "test(cucumber): add Rake tasks cucumber:all, cucumber:wip, cucumber:passing"
```

---

## Task 7 — Smoke test: create a minimal passing feature

This is a one-time sanity check. The feature file is kept permanently as a baseline.

**File to create:** `/Users/aseletskiy/projects/recruit/e11y/features/smoke.feature`

### Step 1 — Write the feature file

```gherkin
# features/smoke.feature
# Smoke test: verifies the Cucumber infrastructure boots correctly.
Feature: Cucumber infrastructure smoke test

  Background:
    Given the application is running

  Scenario: Rails app is reachable via Rack::Test
    When I send a GET request to "/posts"
    Then the response status should be 200

  Scenario: Memory adapter starts empty after Before hook
    Then the memory adapter should be empty
```

### Step 2 — Add the missing "When I send a GET request" step to common_steps.rb

This step is generic enough to belong in common_steps.rb. Append:

```ruby
# Generic HTTP request steps used by smoke test and other features.
When("I send a GET request to {string}") do |path|
  get path
end

When("I send a POST request to {string} with params:") do |path, table|
  params = table.rows_hash
  post path, params
end
```

### Step 3 — Run the smoke test

```bash
bundle exec cucumber features/smoke.feature
```

Expected:
```
2 scenarios (2 passed)
4 steps (4 passed)
```

### Step 4 — Run full dry-run of all features

```bash
bundle exec cucumber --dry-run features/
```

### Step 5 — Commit

```bash
git add features/smoke.feature features/step_definitions/common_steps.rb
git commit -m "test(cucumber): add smoke feature — verifies infrastructure end-to-end"
```

---

## Infrastructure summary

After all tasks are complete, the file layout is:

```
features/
  smoke.feature
  support/
    env.rb                    # Boots dummy Rails app, initializes DB
    world_extensions.rb       # World module: Rack::Test + E11y helpers
    hooks.rb                  # Before (clear events) + After (clean DB)
  step_definitions/
    common_steps.rb           # Generic HTTP, event count, payload field steps
Rakefile                      # Extended with cucumber:all, cucumber:wip, cucumber:passing
Gemfile                       # cucumber, cucumber-rails, rack-test added
```

Key design decisions:
- `env.rb` boots the SAME dummy app used by the existing RSpec integration suite. No separate Rails app is needed.
- `World(E11yWorldHelpers)` mixes `Rack::Test::Methods` in, so every step file automatically has `get`, `post`, `last_response`, etc.
- `memory_adapter.clear!` in `Before` ensures zero bleed between scenarios.
- `@wip` tag marks scenarios that SHOULD FAIL (known bugs). Running `rake cucumber:wip` will run them; `rake cucumber:passing` skips them.
- `rake cucumber:all` runs everything including `@wip`, which will show failures for known bugs — this is intentional and expected.
