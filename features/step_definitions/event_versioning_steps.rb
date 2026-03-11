# frozen_string_literal: true

# features/step_definitions/event_versioning_steps.rb
# Step definitions for event_versioning.feature.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Find events that correspond to the given event class name.
#
# After Versioning middleware runs, event_data[:event_name] is changed to
# dot-notation (e.g. "Events::OrderCreated" → "order.created"), so a
# direct event_name match no longer works.
#
# Strategy (in priority order):
#  1. Match stored event_name against the raw class name exactly —
#     works when Versioning is NOT active (event_name stays as class name).
#  2. Match against the Versioning-normalized form of the class name —
#     works when Versioning IS active.
#  3. Fall back to event_class.name if the class object is still present
#     (belt-and-braces; may be nil in some reload contexts).
def find_versioned_events(class_name)
  normalized = versioning_normalized_name(class_name)
  custom_event_name = custom_event_name_for(class_name)

  memory_adapter.events.select do |e|
    event_matches_versioned?(e, class_name, normalized, custom_event_name)
  end
end

def versioning_normalized_name(class_name)
  mw = E11y::Middleware::Versioning.new(nil)
  mw.send(:normalize_event_name, class_name)
rescue StandardError
  nil
end

def custom_event_name_for(class_name)
  klass = Object.const_get(class_name)
  klass.respond_to?(:event_name) ? klass.event_name.to_s : nil
rescue StandardError
  nil
end

def event_matches_versioned?(event, class_name, normalized, custom_event_name)
  stored = event[:event_name].to_s
  stored == class_name ||
    (normalized && stored == normalized) ||
    event[:event_class]&.name == class_name ||
    (custom_event_name && stored == custom_event_name)
end

def rebuild_pipeline!
  E11y.config.instance_variable_set(:@built_pipeline, nil) if
    E11y.config.instance_variable_defined?(:@built_pipeline)
end

# ---------------------------------------------------------------------------
# Pipeline control
# ---------------------------------------------------------------------------

Given("the Versioning middleware is prepended to the pipeline") do
  already_present = E11y.config.pipeline.middlewares.any? do |entry|
    entry.middleware_class == E11y::Middleware::Versioning
  end

  unless already_present
    # Prepend so Versioning runs before TraceContext / Validation / etc.
    E11y.config.pipeline.middlewares.unshift(
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Versioning,
        args: [],
        options: {}
      )
    )
  end

  rebuild_pipeline!
  memory_adapter.clear!
  @versioning_added_for_scenario = true
end

Given("the Versioning middleware is NOT in the pipeline") do
  E11y.config.pipeline.middlewares.reject! do |entry|
    entry.middleware_class == E11y::Middleware::Versioning
  end
  rebuild_pipeline!
  memory_adapter.clear!
end

After("@event_versioning") do
  if @versioning_added_for_scenario
    E11y.config.pipeline.middlewares.reject! do |entry|
      entry.middleware_class == E11y::Middleware::Versioning
    end
    rebuild_pipeline!
    @versioning_added_for_scenario = false
  end
end

# ---------------------------------------------------------------------------
# Inline event class definitions
# ---------------------------------------------------------------------------

Given("an inline versioning event class {string} with event_name {string}") do |class_name, custom_event_name|
  parts    = class_name.split("::")
  cls_name = parts.last
  parent_mod = parts.length > 1 ? Object.const_get(parts[0..-2].join("::")) : Object

  unless parent_mod.const_defined?(cls_name)
    klass = Class.new(E11y::Event::Base) do
      schema { optional(:field).maybe(:string) }
      adapters []
    end

    # Override event_name to return the custom value.
    custom = custom_event_name
    klass.define_singleton_method(:event_name) { custom }
    parent_mod.const_set(cls_name, klass)
  end
end

Given("an inline versioning event class {string} inheriting from {string}") do |class_name, parent_class_name|
  parts      = class_name.split("::")
  cls_name   = parts.last
  parent_mod = parts.length > 1 ? Object.const_get(parts[0..-2].join("::")) : Object
  parent_cls = Object.const_get(parent_class_name)

  parent_mod.const_set(cls_name, Class.new(parent_cls)) unless parent_mod.const_defined?(cls_name)
end

# ---------------------------------------------------------------------------
# HTTP steps
# ---------------------------------------------------------------------------

When("I POST to {string} with versioning params:") do |path, table|
  params = table.rows_hash
  post path, params.to_json, "CONTENT_TYPE" => "application/json"
end

# ---------------------------------------------------------------------------
# Direct track step
# ---------------------------------------------------------------------------

When("the versioning event {string} is tracked directly with payload:") do |class_name, table|
  klass   = Object.const_get(class_name)
  payload = table.rows_hash.transform_keys(&:to_sym)
  klass.track(**payload)
end

# ---------------------------------------------------------------------------
# Assertion steps
# ---------------------------------------------------------------------------

Then("the last versioned {string} event is present") do |event_class_name|
  events = find_versioned_events(event_class_name)
  expect(events).not_to be_empty,
                        "Expected at least one event for class #{event_class_name} but found none. " \
                        "All stored event_names: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"
end

Then("the last versioned {string} event has event_name {string}") do |event_class_name, expected_name|
  events = find_versioned_events(event_class_name)
  expect(events).not_to be_empty,
                        "No events found for class #{event_class_name}. " \
                        "All stored event_names: #{memory_adapter.events.map { |e| e[:event_name] }.inspect}"

  actual = events.last[:event_name]
  expect(actual).to eq(expected_name),
                    "Expected event_name '#{expected_name}' for #{event_class_name} but got '#{actual}'"
end

Then("the last versioned {string} event does not have a {string} field") do |event_class_name, field_name|
  events = find_versioned_events(event_class_name)
  expect(events).not_to be_empty

  last_event = events.last
  key = field_name.to_sym
  expect(last_event).not_to have_key(key),
                            "Expected event for #{event_class_name} to NOT have field '#{field_name}' " \
                            "but it was present with value: #{last_event[key].inspect}"
end

# rubocop:disable Layout/LineLength
Then("the last versioned {string} event has a {string} field equal to {int}") do |event_class_name, field_name, expected_value|
  # rubocop:enable Layout/LineLength
  events = find_versioned_events(event_class_name)
  expect(events).not_to be_empty,
                        "No events found for class #{event_class_name}"

  last_event = events.last
  actual = last_event[field_name.to_sym]
  expect(actual).to eq(expected_value),
                    "Expected field '#{field_name}' to equal #{expected_value} " \
                    "for #{event_class_name} but got #{actual.inspect}. " \
                    "event_name stored: #{last_event[:event_name].inspect}"
end
