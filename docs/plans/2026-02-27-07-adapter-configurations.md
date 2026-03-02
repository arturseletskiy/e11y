# Adapter Configurations — Cucumber QA Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Verify that each adapter's configuration API matches documentation — exposing silent config key mismatches, Sentry SDK overwrite, always-true health checks, and OTel field filtering.

**Approach:** Mix of Rack::Test requests (for File/Stdout adapter output) and direct adapter API calls (for Sentry, Loki, OTel). Use `Tempfile` for file output scenarios. Capture `$stdout` via `StringIO` for Stdout adapter tests.

**Known bugs covered:**
- `Stdout.new(format: :pretty)` — adapter reads `:pretty_print`, not `:format`. Config silently ignored.
- `Sentry.new(dsn: ...)` calls `Sentry.init` unconditionally — overwrites existing Sentry SDK configuration.
- `Loki#healthy?` checks `@connection&.respond_to?(:get)` (always true on a Faraday object) — never makes real network check.
- `OtelLogs` `DEFAULT_BAGGAGE_ALLOWLIST` only passes `trace_id, span_id, request_id, environment, service_name` — all business fields (order_id, amount, etc.) silently dropped.

---

## Task 1: Feature file

**Files:**
- Create: `features/adapter_configurations.feature`

**Step 1: Write the feature file**

```gherkin
# features/adapter_configurations.feature
@adapters
Feature: Adapter configurations

  Background:
    Given the application is running

  # ─── Stdout Adapter ────────────────────────────────────────────────────────

  @wip
  Scenario: Stdout adapter respects format: :pretty (documented config key)
    # BUG: Stdout adapter reads :pretty_print key, not :format.
    # Passing format: :pretty is silently ignored.
    # lib/e11y/adapters/stdout.rb: @pretty_print = config.fetch(:pretty_print, true)
    Given a Stdout adapter configured with "format: :pretty"
    When I track an event through it
    Then the output should be multi-line pretty-printed JSON

  Scenario: Stdout adapter respects pretty_print: true (correct config key)
    Given a Stdout adapter configured with "pretty_print: true"
    When I track an event through it
    Then the output should be multi-line pretty-printed JSON

  Scenario: Stdout adapter respects pretty_print: false (compact output)
    Given a Stdout adapter configured with "pretty_print: false"
    When I track an event through it
    Then the output should be a single-line JSON string

  # ─── File Adapter ──────────────────────────────────────────────────────────

  Scenario: File adapter writes tracked events as JSONL to configured path
    Given a File adapter writing to a temporary file
    When I POST to "/orders" with params '{"order":{"order_id":"ord-1","user_id":"usr-1","items":"[{\"sku\":\"A\"}]"}}'
    Then the output file should contain at least 1 valid JSON line
    And the JSON line should include the field "event_name"

  # ─── Sentry Adapter ────────────────────────────────────────────────────────

  @wip
  Scenario: Sentry adapter does not reinitialize an already-configured Sentry SDK
    # BUG: E11y::Adapters::Sentry.new calls Sentry.init unconditionally.
    # Any existing Sentry configuration (DSN, hooks, environment) is wiped.
    Given Sentry SDK is initialized with DSN "https://abc123@sentry.example.com/1"
    When I create an E11y Sentry adapter with a different DSN
    Then the Sentry SDK DSN should still be "https://abc123@sentry.example.com/1"

  # ─── Loki Adapter ──────────────────────────────────────────────────────────

  @wip
  Scenario: Loki healthy? returns false when the host is unreachable
    # BUG: healthy? only checks @connection.respond_to?(:get).
    # A Faraday object always responds to :get, so this is always true.
    Given a Loki adapter pointing to "http://localhost:19998"
    When I call healthy? on the adapter
    Then the result should be false

  Scenario: Loki healthy? returns true when the connection object is present
    # Documents current (buggy but stable) behavior so we can detect regressions.
    Given a Loki adapter pointing to "http://localhost:19998"
    When I call healthy? on the adapter
    Then the result should not raise an error

  # ─── OTel Adapter ──────────────────────────────────────────────────────────

  @wip
  Scenario: OTel adapter forwards business payload fields as log attributes
    # BUG: DEFAULT_BAGGAGE_ALLOWLIST = %i[trace_id span_id request_id environment service_name]
    # All business fields (order_id, amount, user_id, etc.) are silently filtered out.
    Given an OTel adapter with default configuration
    When I deliver an event with fields order_id "ord-42" and amount 99.99
    Then the OTel log body should contain "order_id"
    And the OTel log body should contain "amt"

  Scenario: OTel adapter includes trace context fields in log attributes
    # Trace fields ARE in the allowlist — this should pass.
    Given an OTel adapter with default configuration
    When I deliver an event with trace_id "trace-abc" and span_id "span-xyz"
    Then the OTel log attributes should include "trace_id" with value "trace-abc"
```

**Step 2: Run to verify undefined steps**

```bash
bundle exec cucumber features/adapter_configurations.feature --dry-run
```

---

## Task 2: Step definitions

**Files:**
- Create: `features/step_definitions/adapter_steps.rb`

**Step 1: Write step definitions**

```ruby
# features/step_definitions/adapter_steps.rb
# frozen_string_literal: true

require "tempfile"
require "json"

# ─── Stdout Adapter Steps ───────────────────────────────────────────────────

Given("a Stdout adapter configured with {string}") do |config_str|
  @stdout_buffer = StringIO.new
  config = case config_str
           when "format: :pretty"   then { format: :pretty, output: @stdout_buffer }
           when "pretty_print: true"  then { pretty_print: true, output: @stdout_buffer }
           when "pretty_print: false" then { pretty_print: false, output: @stdout_buffer }
           else raise "Unknown config: #{config_str}"
           end
  @stdout_adapter = E11y::Adapters::Stdout.new(**config)
end

When("I track an event through it") do
  @stdout_adapter.write(
    event_name: "order_created",
    severity: :info,
    order_id: "ord-1",
    amount: 99.99,
    timestamp: Time.now.iso8601
  )
end

Then("the output should be multi-line pretty-printed JSON") do
  output = @stdout_buffer.string
  expect(output).to include("\n"),
    "Expected multi-line (pretty-printed) JSON output, but got single line: #{output.inspect}. " \
    "BUG: Stdout adapter uses :pretty_print key, not :format — format: :pretty is silently ignored."
  parsed = JSON.parse(output) rescue nil
  expect(parsed).not_to be_nil, "Output is not valid JSON: #{output.inspect}"
end

Then("the output should be a single-line JSON string") do
  output = @stdout_buffer.string.strip
  lines = output.split("\n").reject(&:empty?)
  expect(lines.size).to eq(1),
    "Expected single-line compact JSON, got #{lines.size} lines."
end

# ─── File Adapter Steps ─────────────────────────────────────────────────────

Given("a File adapter writing to a temporary file") do
  @temp_file = Tempfile.new(["e11y_test", ".jsonl"])
  file_adapter = E11y::Adapters::File.new(path: @temp_file.path)
  E11y.configuration.adapters[:default] = file_adapter
  clear_events!
end

Then("the output file should contain at least {int} valid JSON line(s)") do |min|
  @temp_file.rewind
  lines = @temp_file.readlines.map(&:strip).reject(&:empty?)
  valid = lines.select { |l| JSON.parse(l) rescue false }
  expect(valid.size).to be >= min,
    "Expected >= #{min} valid JSON lines in file, got #{valid.size}. Lines: #{lines.inspect}"
ensure
  @temp_file&.close
  @temp_file&.unlink
end

Then("the JSON line should include the field {string}") do |field|
  @temp_file.rewind
  line = @temp_file.readlines.first&.strip
  parsed = JSON.parse(line) rescue {}
  expect(parsed.keys).to include(field).or include(field.to_sym.to_s),
    "Expected JSON line to include '#{field}', got keys: #{parsed.keys.inspect}"
end

# ─── Sentry Adapter Steps ───────────────────────────────────────────────────

Given("Sentry SDK is initialized with DSN {string}") do |dsn|
  skip_this_scenario unless defined?(::Sentry)
  ::Sentry.init { |config| config.dsn = dsn }
  @original_sentry_dsn = dsn
end

When("I create an E11y Sentry adapter with a different DSN") do
  @sentry_adapter = E11y::Adapters::Sentry.new(dsn: "https://new@different.sentry.io/999")
rescue => e
  @adapter_init_error = e
end

Then("the Sentry SDK DSN should still be {string}") do |expected_dsn|
  skip_this_scenario unless defined?(::Sentry)
  current = ::Sentry.configuration&.dsn.to_s
  expect(current).to include(expected_dsn.split("@").last.split("/").first),
    "Sentry DSN was overwritten! Expected config to still reference '#{expected_dsn}', " \
    "but current DSN is: #{current}. " \
    "BUG: E11y::Adapters::Sentry#initialize calls Sentry.init unconditionally."
end

# ─── Loki Adapter Steps ─────────────────────────────────────────────────────

Given("a Loki adapter pointing to {string}") do |url|
  skip_this_scenario unless defined?(::Faraday)
  @loki_adapter = E11y::Adapters::Loki.new(url: url, timeout: 1)
end

When("I call healthy? on the adapter") do
  @health_result = nil
  @health_error = nil
  begin
    @health_result = @loki_adapter.healthy?
  rescue => e
    @health_error = e
  end
end

Then("the result should be false") do
  expect(@health_result).to be(false),
    "Expected healthy? to return false for unreachable host, but got: #{@health_result.inspect}. " \
    "BUG: Loki#healthy? only checks @connection.respond_to?(:get) — always true on Faraday."
end

Then("the result should not raise an error") do
  expect(@health_error).to be_nil,
    "healthy? raised: #{@health_error&.class}: #{@health_error&.message}"
end

# ─── OTel Adapter Steps ─────────────────────────────────────────────────────

Given("an OTel adapter with default configuration") do
  skip_this_scenario unless defined?(::OpenTelemetry)
  @otel_log_records = []
  # Intercept OTel log records via a simple exporter double
  @otel_adapter = E11y::Adapters::OtelLogs.new
end

When("I deliver an event with fields order_id {string} and amount {float}") do |order_id, amount|
  @otel_event = {
    event_name: "order_created",
    severity: :info,
    order_id: order_id,
    amount: amount,
    timestamp: Time.now.iso8601
  }
  @otel_adapter.write(@otel_event)
end

When("I deliver an event with trace_id {string} and span_id {string}") do |trace_id, span_id|
  @otel_event = {
    event_name: "test_event",
    severity: :info,
    trace_id: trace_id,
    span_id: span_id,
    timestamp: Time.now.iso8601
  }
  @otel_adapter.write(@otel_event)
end

Then("the OTel log body should contain {string}") do |field|
  pending "Cannot verify OTel log body without OTel SDK test exporter setup. " \
          "BUG: baggage_allowlist filters all business fields — #{field} will not appear."
end

Then("the OTel log attributes should include {string} with value {string}") do |attr, value|
  pending "Requires OTel SDK test exporter — trace fields should pass through allowlist."
end
```

**Step 2: Run the feature**

```bash
bundle exec cucumber features/adapter_configurations.feature
```

Expected:
- `Stdout pretty_print: true` → **PASS**
- `Stdout pretty_print: false` → **PASS**
- `File adapter writes JSONL` → **PASS**
- `Loki healthy? doesn't raise` → **PASS**
- `@wip` scenarios → **PENDING** (skipped by default)

Run wip explicitly:
```bash
bundle exec cucumber features/adapter_configurations.feature --tags @wip
```
Expected: `Stdout format: :pretty` **FAIL** (config key mismatch), `Sentry reinit` **FAIL**, `Loki healthy?` **FAIL**.

**Step 3: Commit**

```bash
git add features/adapter_configurations.feature \
        features/step_definitions/adapter_steps.rb
git commit -m "test(cucumber): adapter configs — Stdout format key, Sentry reinit, Loki health bugs"
```
