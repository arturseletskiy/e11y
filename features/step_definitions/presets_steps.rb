# frozen_string_literal: true

# features/step_definitions/presets_steps.rb
# Step definitions for presets.feature.
# Exercises AuditEvent, DebugEvent, and HighValueEvent preset modules.

PRESET_MAP = {
  "E11y::Presets::AuditEvent" => E11y::Presets::AuditEvent,
  "E11y::Presets::DebugEvent" => E11y::Presets::DebugEvent,
  "E11y::Presets::HighValueEvent" => E11y::Presets::HighValueEvent
}.freeze

Given("an event class including {string}") do |preset_name|
  preset = PRESET_MAP.fetch(preset_name) { raise "Unknown preset: #{preset_name}" }

  @preset_event_class = Class.new(E11y::Event::Base) do
    include preset

    schema { required(:id).filled(:string) }
    # Do NOT override adapters — preset configures them
  end
end

Then("the event class should respond to audit_event? with true") do
  result = @preset_event_class.audit_event?
  expect(result).to be(true),
                    "Expected #{@preset_event_class}.audit_event? to return true after including " \
                    "E11y::Presets::AuditEvent, but got: #{result.inspect}. " \
                    "BUG: lib/e11y/presets/audit_event.rb has an empty class_eval block — " \
                    "audit_event true is never called."
end

Then("the event class should have resolve_sample_rate {float}") do |expected_rate|
  actual = @preset_event_class.resolve_sample_rate
  expect(actual).to eq(expected_rate),
                    "Expected resolve_sample_rate #{expected_rate}, got #{actual.inspect}"
end

Given("the AuditSigning middleware is in the pipeline") do
  already = E11y.configuration.pipeline.middlewares.any? do |entry|
    entry.middleware_class == E11y::Middleware::AuditSigning
  end
  unless already
    E11y.configuration.pipeline.use(E11y::Middleware::AuditSigning)
    E11y.configuration.instance_variable_set(:@built_pipeline, nil)
  end
end

When("I track the preset event") do
  E11y.configuration.adapters[:memory] ||= E11y::Adapters::InMemory.new
  E11y.configuration.fallback_adapters = [:memory]
  E11y.configuration.instance_variable_set(:@built_pipeline, nil)
  @preset_event_class.track(id: "preset-#{SecureRandom.hex(4)}")
end

Then("the tracked event should have a {string} field") do |field|
  last = memory_adapter.last_events(1).first
  expect(last).not_to be_nil, "No events in memory adapter"
  has_field = last.key?(field.to_sym) || last.key?(field)
  expect(has_field).to be(true),
                       "Expected tracked event to have '#{field}' but keys are: #{last.keys.inspect}. " \
                       "BUG: AuditSigning skips signing because audit_event? returns false."
end

Then("the event class should have severity :{word}") do |sev|
  actual = @preset_event_class.severity
  expect(actual).to eq(sev.to_sym),
                    "Expected severity :#{sev}, got #{actual.inspect}"
end

Then("the event class adapter list should equal {string}") do |adapter_list_str|
  expected = adapter_list_str
             .delete("[]\"'")
             .split(",")
             .map { |s| s.strip.to_sym }
  actual = Array(@preset_event_class.adapters)
  expect(actual).to match_array(expected),
                    "Expected adapters #{expected.inspect}, got #{actual.inspect}"
end
