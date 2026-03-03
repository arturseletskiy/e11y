# frozen_string_literal: true

# features/step_definitions/schema_validation_steps.rb
# Step definitions for schema_validation.feature.

# ---------------------------------------------------------------------------
# Assertion steps
# ---------------------------------------------------------------------------

Then("the last event payload in the memory adapter should include {string}") do |field|
  # Find the last OrderCreated event specifically — the HTTP instrumentation event
  # is also stored in the adapter and would be picked up by last_events(1).
  events = memory_adapter.find_events("Events::OrderCreated")
  event = events.last
  expect(event).not_to be_nil,
    "No Events::OrderCreated event found in memory adapter. " \
    "All stored event_names: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"

  payload = event[:payload] || {}
  has_field = payload.key?(field.to_sym) || payload.key?(field)
  expect(has_field).to be(true),
    "Expected last OrderCreated event payload to include field '#{field}'. " \
    "Payload keys: #{payload.keys.inspect}"
end

Then("the last event payload field {string} should be a string") do |field|
  events = memory_adapter.find_events("Events::OrderCreated")
  event = events.last
  expect(event).not_to be_nil,
    "No Events::OrderCreated event found in memory adapter."

  payload = event[:payload] || {}
  value = payload[field.to_sym] || payload[field]
  expect(value).to be_a(String),
    "Expected payload field '#{field}' to be a String, " \
    "got #{value.class}: #{value.inspect}"
end

Then("defining an event class with a valid schema block should not raise") do
  error = nil
  begin
    Class.new(E11y::Event::Base) do
      schema do
        required(:id).filled(:string)
        required(:amount).filled(:float)
        optional(:description).maybe(:string)
      end
    end
  rescue StandardError => e
    error = e
  end
  expect(error).to be_nil,
    "Defining an event class with a schema block raised: " \
    "#{error&.class}: #{error&.message}"
end

Then("defining and tracking an event class without a schema block should not raise") do
  error = nil
  begin
    klass = Class.new(E11y::Event::Base) do
      adapters []
    end
    # Use a known-existing fallback adapter so the event is delivered
    klass.track(id: "no-schema-#{SecureRandom.hex(4)}")
  rescue StandardError => e
    error = e
  end
  expect(error).to be_nil,
    "Schemaless event tracking raised: #{error&.class}: #{error&.message}"
end
