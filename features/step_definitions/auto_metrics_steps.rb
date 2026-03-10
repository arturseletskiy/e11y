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

# @wip: BUG 2 — increment_metric in middleware is an empty stub
When("E11y processes an event through the pipeline") do
  @middleware_metric_calls = []

  # Temporarily instrument increment_metric in TraceContext to detect calls
  # (the actual stub returns nil and does nothing)
  spy_calls = @middleware_metric_calls
  E11y::Middleware::TraceContext.class_eval do
    alias_method :__original_increment_metric, :increment_metric

    define_method(:increment_metric) do |metric_name, **tags|
      spy_calls << metric_name
      __original_increment_metric(metric_name, **tags)
    end
  end

  begin
    # Track a simple event through the pipeline
    test_class = Class.new(E11y::Event::Base) do
      schema { required(:id).filled(:string) }
      adapters []
      validation_mode :never
    end
    test_class.track(id: "metrics-spy-test")
  ensure
    # Restore original method
    E11y::Middleware::TraceContext.class_eval do
      alias_method :increment_metric, :__original_increment_metric
      remove_method :__original_increment_metric
    end
  end
end

Then("at least 1 internal middleware metric should have been tracked") do
  calls = @middleware_metric_calls || []
  # increment_metric is called but is a stub — it never reaches a real metrics backend.
  # We first verify the stub IS called, then check the stub doesn't produce actual tracking.
  expect(calls.size).to be >= 1,
                        "Expected at least 1 call to increment_metric in TraceContext middleware, " \
                        "but 0 calls were detected. Check that the spy is wired correctly."

  # Now verify the stub's no-op nature: E11y::Metrics.increment was NOT called.
  E11y::Metrics.reset_backend!
  backend = E11y::Metrics.backend
  expect(backend).not_to be_nil,
                         "increment_metric was called #{calls.size} time(s) with: #{calls.inspect}, " \
                         "but E11y::Metrics.backend is nil — metric calls go nowhere. " \
                         "BUG: increment_metric in middleware is an empty stub " \
                         "(body contains only a TODO comment, no real metric recording)."
end
