# frozen_string_literal: true

# features/step_definitions/request_scoped_buffer_steps.rb
#
# Step definitions for request_scoped_buffer.feature.
# Exercises the RequestBufferConfig and the (stub) flush_event mechanism.

Then("request buffering should be disabled in the configuration") do
  msg = "Expected request buffering to be disabled by default, but it was enabled. " \
        "README says 'automatically captures' but config defaults to enabled: false."
  expect(E11y.configuration.request_buffer.enabled).to be(false), msg
end

Given("request buffering is enabled in the configuration") do
  E11y.configuration.request_buffer.enabled = true
end

Then("request buffering should be enabled in the configuration") do
  expect(E11y.configuration.request_buffer.enabled).to be(true)
end

Then("{int} events with severity {string} should be in the adapter") do |count, severity|
  events = begin
    memory_adapter.events_by_severity(severity.to_sym)
  rescue StandardError
    memory_adapter.events.select { |e| e[:severity].to_s == severity }
  end
  expect(events.size).to eq(count),
                         "Expected #{count} #{severity}-severity events in adapter, got #{events.size}. " \
                         "BUG: flush_event in RequestScopedBuffer is a stub — buffered events are never written."
end

Then("events with severity {string} should be in the adapter") do |severity|
  events = memory_adapter.events.select { |e| e[:severity].to_s == severity }
  expect(events.size).to be.positive?,
                         "Expected at least 1 #{severity}-severity event in adapter after failed request, got 0. " \
                         "BUG: flush_event stub in lib/e11y/buffers/request_scoped_buffer.rb:226."
end

Then("those debug events should have been generated during that request") do
  events = memory_adapter.events.select { |e| e[:severity].to_s == "debug" }
  expect(events).to all(include(request_id: be_a(String))),
                    "Expected flushed debug events to carry a request_id from the failed request."
end

Then("at least {int} event with severity {string} should be in the adapter") do |min, severity|
  events = memory_adapter.events.select { |e| e[:severity].to_s == severity }
  expect(events.size).to be >= min,
                         "Expected >= #{min} #{severity}-severity event(s) in adapter, got #{events.size}."
end

When("I GET {string} again") do |path|
  get path
end

Then("the request buffer should be empty between requests") do
  buffer = Thread.current[:e11y_request_buffer]
  msg = "Expected request buffer to be cleared after successful request, but it still has events."
  expect(buffer.nil? || buffer.empty?).to be(true), msg
end
