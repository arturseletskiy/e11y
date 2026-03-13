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
# HTTP request steps
# ---------------------------------------------------------------------------

# Generic HTTP request steps used by smoke test and other features.
When("I send a GET request to {string}") do |path|
  get path
end

When("I send a POST request to {string} with params:") do |path, table|
  params = table.rows_hash
  post path, params
end

When("I GET {string}") do |path|
  get path
end

When("I POST to {string} with params {string}") do |path, json_params|
  post path, json_params, "CONTENT_TYPE" => "application/json"
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
    /\A[0-9a-f]{64}\z/ # hash strategy (SHA256 hex)
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
  msg = "Expected adapter to be empty but found #{memory_adapter.event_count} events.\n" \
        "Event types: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
  expect(memory_adapter.event_count).to eq(0), msg
end
