# frozen_string_literal: true

# features/step_definitions/sampling_steps.rb
# Step definitions for adaptive_sampling.feature.

require "e11y/sampling/load_monitor"
require "e11y/sampling/error_spike_detector"
require "e11y/middleware/sampling"
require "e11y/pipeline/builder"

# ---------------------------------------------------------------------------
# Background / setup steps
# ---------------------------------------------------------------------------

Given("the memory adapter is cleared") do
  E11y.config.adapters[:memory] ||= E11y::Adapters::InMemory.new
  E11y.config.adapters[:memory].clear!
end

Given("E11y is configured with the memory adapter as fallback") do
  E11y.config.adapters[:memory] ||= E11y::Adapters::InMemory.new
  E11y.config.adapters[:logs]   = E11y.config.adapters[:memory]
  E11y.config.fallback_adapters = [:memory]
  E11y.config.instance_variable_set(:@built_pipeline, nil)
end

Given("the Sampling middleware is reconfigured with trace_aware false and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(default_sample_rate: rate, trace_aware: false)
end

Given("the Sampling middleware is reconfigured with error_based_adaptive true and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(
    default_sample_rate: rate,
    trace_aware: false,
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 10,
      relative_threshold: 3.0,
      spike_duration: 300
    }
  )
end

Given("the Sampling middleware is reconfigured with trace_aware true and default_sample_rate {float}") do |rate|
  reconfigure_sampling_middleware(default_sample_rate: rate, trace_aware: true)
end

# ---------------------------------------------------------------------------
# Event-class creation
# ---------------------------------------------------------------------------

Given("an event class {string} with sample_rate {float}") do |class_name, rate|
  parts  = class_name.split("::")
  parent = parts[0..-2].reduce(Object) { |mod, part| ensure_sampling_module(mod, part) }
  name   = parts.last

  unless parent.const_defined?(name, false)
    klass = Class.new(E11y::Event::Base) do
      sample_rate rate
      validation_mode :never
      adapters []
    end
    parent.const_set(name, klass)
  end
end

# ---------------------------------------------------------------------------
# Tracking helpers
# ---------------------------------------------------------------------------

When("I track {int} {string} events") do |count, class_name|
  klass = class_name.split("::").reduce(Object, :const_get)
  count.times { |i| klass.track(seq: i) }
end

# Track error-severity events directly to trigger the spike detector.
When("I track {int} error events to trigger the spike detector") do |count|
  # Create a minimal error-severity event class under the Events namespace
  events_mod = ensure_sampling_module(Object, "Events")
  unless events_mod.const_defined?("SamplingError", false)
    klass = Class.new(E11y::Event::Base) do
      severity :error
      validation_mode :never
      adapters []
      sample_rate 1.0
    end
    events_mod.const_set("SamplingError", klass)
  end
  count.times { |i| Events::SamplingError.track(seq: i) }
end

# ---------------------------------------------------------------------------
# Memory adapter assertions
# ---------------------------------------------------------------------------

Then("the memory adapter should contain exactly {int} {string} events") do |count, class_name|
  adapter = E11y.config.adapters[:memory]
  events  = adapter.events.select do |e|
    e[:event_name].to_s == class_name ||
      e[:event_class]&.name == class_name
  end
  expect(events.size).to eq(count),
    "Expected #{count} #{class_name} events in memory adapter, got #{events.size}"
end

# ---------------------------------------------------------------------------
# LoadMonitor steps
# ---------------------------------------------------------------------------

Given("a LoadMonitor with normal threshold {int} events per second and window {int} second") do |normal, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: normal * 5, very_high: normal * 10, overload: normal * 20 }
  )
end

Given("a LoadMonitor with normal threshold {int}, high threshold {int} events per second and window {int} second") do |normal, high, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: high, very_high: high * 2, overload: high * 4 }
  )
end

Given("a LoadMonitor with normal threshold {int}, high threshold {int}, very_high threshold {int}, overload threshold {int} events per second and window {int} second") do |normal, high, very_high, overload, window|
  @load_monitor = E11y::Sampling::LoadMonitor.new(
    window: window,
    thresholds: { normal: normal, high: high, very_high: very_high, overload: overload }
  )
end

When("I record exactly {int} events in {int} second in the LoadMonitor") do |count, _window|
  now = Time.now
  @load_monitor.instance_variable_get(:@mutex).synchronize do
    count.times do |i|
      @load_monitor.instance_variable_get(:@events) << (now - (0.5 * i.to_f / count))
    end
  end
end

When("I record {int} events in {int} second in the LoadMonitor") do |count, _window|
  now = Time.now
  @load_monitor.instance_variable_get(:@mutex).synchronize do
    count.times do |i|
      @load_monitor.instance_variable_get(:@events) << (now - (0.9 * i.to_f / count))
    end
  end
end

Then("the LoadMonitor load_level should be :normal") do
  level = @load_monitor.load_level
  expect(level).to eq(:normal),
    "Expected LoadMonitor#load_level to be :normal but got :#{level}. " \
    "Known bug: when rate == thresholds[:normal], load_monitor.rb returns :high instead of :normal."
end

Then("the LoadMonitor recommended_sample_rate should be {float}") do |expected_rate|
  rate = @load_monitor.recommended_sample_rate
  expect(rate).to eq(expected_rate),
    "Expected recommended_sample_rate #{expected_rate} but got #{rate}. " \
    "Known bug: off-by-one in load_level causes 50% rate at normal load."
end

Then("the LoadMonitor recommended_sample_rate should be less than {float}") do |threshold|
  rate = @load_monitor.recommended_sample_rate
  expect(rate).to be < threshold,
    "Expected recommended_sample_rate < #{threshold} but got #{rate}"
end

# ---------------------------------------------------------------------------
# Error spike detection assertion
# ---------------------------------------------------------------------------

Then("the error spike detector should be active") do
  pipeline = E11y.config.built_pipeline
  sampling = find_middleware_in_chain(pipeline, E11y::Middleware::Sampling)
  expect(sampling).not_to be_nil, "Sampling middleware not found in pipeline"

  detector = sampling.instance_variable_get(:@error_spike_detector)
  expect(detector).not_to be_nil, "Error spike detector not initialized"
  expect(detector.error_spike?).to be(true),
    "Expected error spike to be active after tracking 15 error events. " \
    "absolute_threshold=10, tracked=15, but spike not detected."
end

# ---------------------------------------------------------------------------
# Trace consistency steps
# ---------------------------------------------------------------------------

Given("the trace decisions cache is filled with {int} dummy entries to trigger cleanup") do |count|
  pipeline  = E11y.config.built_pipeline
  sampling  = find_middleware_in_chain(pipeline, E11y::Middleware::Sampling)
  expect(sampling).not_to be_nil

  decisions = sampling.instance_variable_get(:@trace_decisions)
  mutex     = sampling.instance_variable_get(:@trace_decisions_mutex)
  mutex.synchronize do
    count.times { |i| decisions["dummy-trace-#{i}"] = i.even? }
  end
end

When("I set the current trace_id to {string}") do |trace_id|
  E11y::Current.trace_id = trace_id
end

Then("all {int} {string} events should have the same sampling outcome") do |count, class_name|
  adapter = E11y.config.adapters[:memory]
  events  = adapter.events.select do |e|
    e[:event_name].to_s == class_name || e[:event_class]&.name == class_name
  end
  actual = events.size
  expect(actual).to be_in([0, count]),
    "Expected all #{count} #{class_name} events to have the same outcome " \
    "(either all 0 or all #{count}), got #{actual}. " \
    "Known bug: cleanup_trace_decisions in sampling.rb randomly evicts 50% of cache " \
    "keys, breaking trace-level consistency."
end

# ---------------------------------------------------------------------------
# Helpers (accessible via World module)
# ---------------------------------------------------------------------------

module SamplingStepHelpers
  def reconfigure_sampling_middleware(options)
    cfg = E11y.config
    cfg.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

    insert_index = sampling_insert_index(cfg)
    cfg.pipeline.middlewares.insert(
      insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Sampling,
        args: [],
        options: options
      )
    )
    cfg.instance_variable_set(:@built_pipeline, nil)
  end

  def sampling_insert_index(cfg)
    idx = cfg.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
    idx ? idx + 1 : cfg.pipeline.middlewares.size
  end

  def find_middleware_in_chain(pipeline, klass)
    node = pipeline
    while node && !node.is_a?(Proc)
      return node if node.is_a?(klass)

      node = node.instance_variable_get(:@app)
    end
    nil
  end

  def ensure_sampling_module(parent, name)
    return parent.const_get(name) if parent.const_defined?(name, false)

    mod = Module.new
    parent.const_set(name, mod)
    mod
  end
end

World(SamplingStepHelpers)
