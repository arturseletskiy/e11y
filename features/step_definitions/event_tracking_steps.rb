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
# Exception assertions
# ---------------------------------------------------------------------------

Then("no exception should have been raised") do
  expect(@last_exception).to be_nil,
                             "Expected no exception but got: #{@last_exception&.class}: #{@last_exception&.message}"
end

Then("a {string} exception should have been raised") do |exception_class_name|
  expect(@last_exception).not_to be_nil,
                                 "Expected a #{exception_class_name} to be raised but no exception occurred."
  msg = "Expected #{exception_class_name} but got #{@last_exception.class.name}: #{@last_exception.message}"
  expect(@last_exception.class.name).to eq(exception_class_name), msg
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
