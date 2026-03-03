# frozen_string_literal: true

# features/step_definitions/in_memory_adapter_steps.rb
#
# Step definitions specific to in_memory_adapter.feature.
# Uses Rack::Test to generate real events in the memory adapter via HTTP requests
# to the dummy app, then exercises adapter query methods directly.

# ---------------------------------------------------------------------------
# Setup steps — generate events via HTTP
# ---------------------------------------------------------------------------

Given("the memory adapter is empty") do
  clear_events!
end

Given("I have tracked {int} order event(s)") do |count|
  count.times do
    post "/orders", { "order[status]" => "pending" }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

Given("I have tracked {int} order event(s) with status {string}") do |count, status|
  count.times do
    post "/orders", { "order[status]" => status }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

# Tracks multiple orders using a comma-separated status list.
# Example: "pending", "confirmed", "cancelled"
Given("I have tracked {int} order events with statuses {string}, {string}, {string}") do |_count, s1, s2, s3|
  [s1, s2, s3].each do |status|
    post "/orders", { "order[status]" => status }
    expect(last_response.status).to eq(201),
      "POST /orders failed with #{last_response.status}: #{last_response.body}"
  end
end

Given("I have tracked {int} user registration event(s)") do |count|
  count.times do |i|
    post "/users", {
      "user[email]"                 => "user#{i}@example.com",
      "user[password]"              => "password123",
      "user[password_confirmation]" => "password123",
      "user[name]"                  => "User #{i}"
    }
    expect(last_response.status).to eq(201),
      "POST /users failed with #{last_response.status}: #{last_response.body}"
  end
end

# ---------------------------------------------------------------------------
# Action steps — call adapter methods and store result in @adapter_result
# ---------------------------------------------------------------------------

When("I call adapter.last_event") do
  @adapter_result = memory_adapter.last_event
end

When("I call adapter.event_count with positional argument {string}") do |event_name|
  @adapter_result = memory_adapter.event_count(event_name)
end

When("I call adapter.clear without bang") do
  memory_adapter.clear
end

When("I call adapter.clear!") do
  memory_adapter.clear!
end

When("I call adapter.event_count with no arguments") do
  @adapter_result = memory_adapter.event_count
end

When("I call adapter.event_count with keyword event_name {string}") do |event_name|
  @adapter_result = memory_adapter.event_count(event_name: event_name)
end

When("I call adapter.find_events with {string}") do |event_name|
  @adapter_result = memory_adapter.find_events(event_name)
end

When("I call adapter.last_events with count {int}") do |count|
  @adapter_result = memory_adapter.last_events(count)
end

When("I call adapter.last_events\\({int}).first") do |count|
  @adapter_result = memory_adapter.last_events(count).first
end

When("I call adapter.find_events\\({string}).last") do |event_name|
  @adapter_result = memory_adapter.find_events(event_name).last
end

When("I call adapter.first_events with count {int}") do |count|
  @adapter_result = memory_adapter.first_events(count)
end

When("I call adapter.events_by_severity with :info") do
  @adapter_result = memory_adapter.events_by_severity(:info)
end

When("I call adapter.any_event? with {string}") do |event_name|
  @adapter_result = memory_adapter.any_event?(event_name)
end

# ---------------------------------------------------------------------------
# Assertion steps — inspect @adapter_result
# ---------------------------------------------------------------------------

Then("the result should be a Hash") do
  expect(@adapter_result).to be_a(Hash),
    "Expected a Hash but got #{@adapter_result.class}: #{@adapter_result.inspect}"
end

Then("the result should equal {int}") do |expected_int|
  expect(@adapter_result).to eq(expected_int),
    "Expected #{expected_int} but got #{@adapter_result.inspect}"
end

Then("the result should contain {int} item(s)") do |count|
  expect(@adapter_result).to be_an(Array),
    "Expected an Array but got #{@adapter_result.class}"
  expect(@adapter_result.size).to eq(count),
    "Expected #{count} items but got #{@adapter_result.size}.\n" \
    "Items: #{@adapter_result.inspect}"
end

Then("the result should contain at least {int} item(s)") do |min_count|
  expect(@adapter_result).to be_an(Array),
    "Expected an Array but got #{@adapter_result.class}"
  expect(@adapter_result.size).to be >= min_count,
    "Expected at least #{min_count} items but got #{@adapter_result.size}."
end

Then("the boolean result should be {word}") do |bool_string|
  expected = (bool_string == "true")
  expect(@adapter_result).to eq(expected),
    "Expected #{expected.inspect} but got #{@adapter_result.inspect}"
end

Then("all items in the result should have event_name {string}") do |event_name|
  expect(@adapter_result).to be_an(Array)
  @adapter_result.each_with_index do |item, idx|
    actual_name = item[:event_name]
    expect(actual_name).to eq(event_name),
      "Item #{idx} has event_name #{actual_name.inspect}, expected #{event_name.inspect}.\n" \
      "Item: #{item.inspect}"
  end
end

Then("the result's payload field {string} should equal {string}") do |field, expected_value|
  payload = @adapter_result[:payload] || @adapter_result.dig(:payload)
  expect(payload).not_to be_nil,
    "Result has no :payload key.\nResult: #{@adapter_result.inspect}"
  actual_value = payload[field.to_sym] || payload[field]
  expect(actual_value.to_s).to eq(expected_value),
    "Expected payload[:#{field}] to equal #{expected_value.inspect} but got #{actual_value.inspect}."
end

Then("the adapter events array should have {int} items") do |count|
  expect(memory_adapter.events.size).to eq(count),
    "Expected adapter.events.size to be #{count} but got #{memory_adapter.events.size}."
end

Then("the adapter events array should have at least {int} items") do |min_count|
  expect(memory_adapter.events.size).to be >= min_count,
    "Expected adapter.events.size >= #{min_count} but got #{memory_adapter.events.size}."
end

Then("the result should be at least {int}") do |min_value|
  expect(@adapter_result).to be >= min_value,
    "Expected result >= #{min_value} but got #{@adapter_result.inspect}"
end
