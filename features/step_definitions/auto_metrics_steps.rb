# frozen_string_literal: true

# features/step_definitions/auto_metrics_steps.rb
# Step definitions for auto_metrics.feature.

# Helper: ensure the Registry is clean between scenarios.
After("@metrics") do
  E11y::Metrics::Registry.instance.clear!
end

Then("defining an event class with a metrics block should not raise") do
  error = nil
  begin
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      metrics do
        counter :smoke_counter, tags: []
        histogram :smoke_histogram, value: :id, tags: []
      end
    end
  rescue StandardError => e
    error = e
  end
  expect(error).to be_nil,
                   "Defining an event class with a metrics block raised: #{error&.class}: #{error&.message}"
end

When("I define an event class with a counter named {string}") do |counter_name|
  E11y::Metrics::Registry.instance.clear!
  @metrics_event_class = Class.new(E11y::Event::Base) do
    schema { required(:id).filled(:string) }
    metrics do
      counter counter_name.to_sym, tags: []
    end
  end
end

Then("the Metrics Registry should contain a counter named {string}") do |counter_name|
  registry = E11y::Metrics::Registry.instance
  entry = registry.all.find { |m| m[:name] == counter_name.to_sym && m[:type] == :counter }
  expect(entry).not_to be_nil,
                       "Expected Metrics Registry to contain a counter named #{counter_name.inspect}, " \
                       "but it was not found. Registry contents: #{registry.all.map do |m|
                         [m[:type], m[:name]]
                       end.inspect}"
end

When("I define an event class with a histogram {string} and buckets {int} {int} {int} {int}") do |name, b1, b2, b3, b4|
  E11y::Metrics::Registry.instance.clear!
  histogram_name = name.to_sym
  buckets = [b1, b2, b3, b4]
  @metrics_event_class = Class.new(E11y::Event::Base) do
    schema { required(:amount).filled(:float) }
    metrics do
      histogram histogram_name, value: :amount, buckets: buckets
    end
  end
end

Then("the Metrics Registry should contain a histogram {string} with buckets {int} {int} {int} {int}") do |name, b1, b2, b3, b4|
  expected_buckets = [b1, b2, b3, b4]
  registry = E11y::Metrics::Registry.instance
  entry = registry.all.find { |m| m[:name] == name.to_sym && m[:type] == :histogram }
  expect(entry).not_to be_nil,
                       "Expected Metrics Registry to contain a histogram named #{name.inspect}, " \
                       "but it was not found."
  expect(entry[:buckets]).to eq(expected_buckets),
                             "Expected histogram #{name.inspect} to have buckets #{expected_buckets.inspect}, " \
                             "but found: #{entry[:buckets].inspect}"
end

When("I define two event classes using metric name {string} with different types") do |metric_name|
  E11y::Metrics::Registry.instance.clear!
  @type_conflict_error = nil
  sym = metric_name.to_sym
  begin
    # First: register as a counter
    Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      metrics do
        counter sym, tags: []
      end
    end
    # Second: register same name as a histogram — should raise TypeConflictError
    Class.new(E11y::Event::Base) do
      schema { required(:amount).filled(:float) }
      metrics do
        histogram sym, value: :amount, tags: []
      end
    end
  rescue E11y::Metrics::Registry::TypeConflictError => e
    @type_conflict_error = e
  end
end

Then("a TypeConflictError should have been raised") do
  expect(@type_conflict_error).not_to be_nil,
                                      "Expected E11y::Metrics::Registry::TypeConflictError to be raised " \
                                      "when two event classes define the same metric name with different types, " \
                                      "but no error was raised."
  expect(@type_conflict_error).to be_a(E11y::Metrics::Registry::TypeConflictError)
end

# @wip: BUG 1 — no metrics backend configured
Then("E11y::Metrics should have a configured backend") do
  E11y::Metrics.reset_backend!
  backend = E11y::Metrics.backend
  expect(backend).not_to be_nil,
                         "Expected E11y::Metrics.backend to return a configured adapter, " \
                         "but it returned nil. " \
                         "BUG: No Yabeda adapter is auto-configured in the default E11y setup. " \
                         "All E11y::Metrics.increment/histogram/gauge calls are silently discarded. " \
                         "Users must manually add the Yabeda adapter to the pipeline."
end

# Verify that middleware internal metrics use real E11y::Metrics.increment calls.
# Uses Ruby method wrapping (no RSpec) since Cucumber World doesn't include RSpec.
When("E11y processes an event through the pipeline") do
  @middleware_metric_calls = []
  spy_calls = @middleware_metric_calls

  # Wrap E11y::Metrics.increment to spy on calls (Cucumber has no RSpec allow)
  mod = E11y::Metrics
  mod.singleton_class.class_eval do
    alias_method :__cucumber_original_increment, :increment
    define_method(:increment) do |name, *args, **kwargs|
      spy_calls << name
      __cucumber_original_increment(name, *args, **kwargs)
    end
  end

  begin
    test_class = Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      adapters []
      validation_mode :never
    end
    test_class.track(id: "metrics-spy-test")
  ensure
    mod.singleton_class.class_eval do
      alias_method :increment, :__cucumber_original_increment
      remove_method :__cucumber_original_increment
    end
  end
end

Then("at least 1 internal middleware metric should have been tracked") do
  calls = @middleware_metric_calls || []
  trace_context_metrics = ["e11y.middleware.trace_context.processed", :e11y_middleware_trace_context_processed]
  found = calls.any? { |c| trace_context_metrics.include?(c) }
  expect(found).to be(true),
                   "Expected TraceContext middleware to call E11y::Metrics.increment, " \
                   "but calls were: #{calls.inspect}"

  backend = E11y::Metrics.backend
  expect(backend).not_to be_nil,
                         "Middleware called increment #{calls.size} time(s) with: #{calls.inspect}, " \
                         "but E11y::Metrics.backend is nil."
end
