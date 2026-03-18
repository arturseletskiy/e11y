# frozen_string_literal: true

# features/step_definitions/default_pipeline_steps.rb
# Step definitions for default_pipeline.feature.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def pipeline_middleware_names
  E11y.configuration.pipeline.middlewares.map do |entry|
    entry.middleware_class.name.split("::").last
  end
end

def clear_built_pipeline_cache!
  E11y.configuration.instance_variable_set(:@built_pipeline, nil)
end

def add_rate_limiting_to_pipeline!
  config = E11y.configuration
  entries = config.pipeline.middlewares
  return if entries.any? { |e| e.middleware_class == E11y::Middleware::RateLimiting }

  sampling_idx = entries.find_index { |e| e.middleware_class == E11y::Middleware::Sampling }
  entry = E11y::Pipeline::Builder::MiddlewareEntry.new(
    middleware_class: E11y::Middleware::RateLimiting,
    args: [],
    options: {
      global_limit: config.rate_limiting_global_limit,
      per_event_limit: config.rate_limiting_per_event_limit,
      window: config.rate_limiting_global_window
    }
  )
  entries.insert(sampling_idx || entries.size, entry)
  clear_built_pipeline_cache!
end

def add_event_slo_to_pipeline!
  config = E11y.configuration
  entries = config.pipeline.middlewares
  return if entries.any? { |e| e.middleware_class == E11y::Middleware::EventSlo }

  routing_idx = entries.find_index { |e| e.middleware_class == E11y::Middleware::Routing }
  entry = E11y::Pipeline::Builder::MiddlewareEntry.new(
    middleware_class: E11y::Middleware::EventSlo,
    args: [],
    options: {}
  )
  entries.insert(routing_idx || entries.size, entry)
  clear_built_pipeline_cache!
end

# ---------------------------------------------------------------------------
# Step definitions
# ---------------------------------------------------------------------------

Then("the pipeline should include the {string} middleware") do |name|
  names = pipeline_middleware_names
  expect(names).to include(name),
                   "Expected default pipeline to include '#{name}' middleware, but it was absent. " \
                   "Actual pipeline: #{names.join(' → ')}. " \
                   "BUG: #{name} is defined but never added in configure_default_pipeline (lib/e11y.rb)."
end

When("I POST to {string} with json params {string}") do |path, json_params|
  post path, json_params, "CONTENT_TYPE" => "application/json"
end

Then("at least {int} event should be in the memory adapter") do |min|
  count = memory_adapter.event_count
  expect(count).to be >= min,
                   "Expected >= #{min} event(s) in memory adapter after POST, but got #{count}. " \
                   "The event may have been dropped or blocked by the pipeline."
end

Then("{string} should come before {string} in the pipeline") do |first, second|
  names = pipeline_middleware_names
  idx_first  = names.index(first)
  idx_second = names.index(second)

  expect(idx_first).not_to be_nil,
                           "Middleware '#{first}' not found in pipeline. Actual: #{names.join(' → ')}"
  expect(idx_second).not_to be_nil,
                            "Middleware '#{second}' not found in pipeline. Actual: #{names.join(' → ')}"
  expect(idx_first).to be < idx_second,
                       "Expected '#{first}' (position #{idx_first}) to come before " \
                       "'#{second}' (position #{idx_second}). " \
                       "ADR-015 requires this ordering. Actual pipeline: #{names.join(' → ')}"
end

Given("rate limiting is configured with global_limit {int}") do |limit|
  E11y.configuration.rate_limiting_enabled = true
  E11y.configuration.rate_limiting_global_limit = limit
  add_rate_limiting_to_pipeline!
end

Given("rate limiting is enabled") do
  E11y.configuration.rate_limiting_enabled = true
  add_rate_limiting_to_pipeline!
end

Given("EventSlo middleware is enabled") do
  E11y.configuration.slo_tracking_enabled = true
  add_event_slo_to_pipeline!
end

When("I send {int} rapid order events") do |count|
  memory_adapter.clear!
  count.times do |i|
    post "/orders",
         "{\"order\":{\"order_id\":\"ord-rl-#{i}\",\"status\":\"pending\"}}",
         "CONTENT_TYPE" => "application/json"
  end
  @rapid_events_sent = count
end

Then("fewer than {int} events should arrive in the adapter") do |threshold|
  arrived = memory_adapter.event_count
  expect(arrived).to be < threshold,
                     "Expected rate limiting to block some of #{@rapid_events_sent} events. " \
                     "Arrived: #{arrived}. " \
                     "BUG: RateLimiting middleware is absent from the default pipeline — " \
                     "all #{arrived} events passed through unchecked."
end
