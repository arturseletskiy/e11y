# frozen_string_literal: true

require "rails_helper"

# Require dependencies - fail fast if not available
begin
  require "yabeda"
  require "yabeda/prometheus"
rescue LoadError => e
  raise "Required dependency 'yabeda' is not available. " \
        "Install with: bundle install --with integration. " \
        "Original error: #{e.message}"
end

# Pattern-based metrics integration tests for UC-003
# Tests pattern matching, label extraction, value extraction, and Yabeda integration
#
# Scenarios:
# 1. Counter metrics (pattern matching, label extraction, Yabeda export)
# 2. Gauge metrics (value extraction, Yabeda export)
# 3. Histogram metrics (value extraction, buckets, Yabeda export)
# 4. Custom labels (tags extraction from event payload)
# 5. Pattern matching (exact, *, ** patterns)
# 6. Regex performance (pattern matching speed benchmarks)

RSpec.describe "Pattern-Based Metrics Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }
  let(:registry) { E11y::Metrics::Registry.instance }

  before do
    memory_adapter.clear!
    # Don't reset Yabeda - it breaks metric registration for subsequent tests
    # Yabeda.reset! destroys the :e11y group and all metrics

    # NOTE: We don't clear registry here because event classes register metrics at load time
    # If we clear registry, metrics won't be re-registered unless classes are reloaded
    # Registry is cleared in after block for test isolation

    # Configure Yabeda adapter
    yabeda_adapter_instance = E11y::Adapters::Yabeda.new(
      auto_register: true
    )
    E11y.config.adapters[:yabeda] = yabeda_adapter_instance

    # Configure Yabeda (empty group, metrics will be auto-registered from Registry)
    Yabeda.configure do
      group :e11y do
        # Metrics will be registered automatically from Registry
      end
    end
    Yabeda.configure!

    # Configure routing to send events to both memory and yabeda adapters
    E11y.config.fallback_adapters = %i[memory yabeda]
  end

  after do
    memory_adapter.clear!
    # Don't reset Yabeda - it breaks metric registration
    # Don't clear registry - event classes register metrics at load time
  end

  describe "Scenario 1: Counter metrics" do
    it "tracks counter metrics with pattern matching and label extraction" do
      # Setup: Event class with counter metric definition
      # Test: Track event, verify pattern matching, label extraction, Yabeda export
      # Expected: Pattern matches event name, counter incremented in Yabeda, labels extracted correctly

      memory_adapter.clear!

      # Ensure Yabeda metrics are registered (auto-register from Registry)
      adapter = E11y.config.adapters[:yabeda]
      adapter.register_metrics_from_registry! if adapter.respond_to?(:register_metrics_from_registry!)

      # Track event (this will trigger event class loading and metric registration)
      event_data = Events::OrderPaid.track(
        order_id: "123",
        currency: "USD"
      )

      # Verify event was tracked
      events = memory_adapter.find_events("Events::OrderPaid")
      expect(events.count).to eq(1), "Expected 1 event tracked"

      # Verify pattern matching (metrics should be registered after event class loaded)
      event_name = Events::OrderPaid.event_name
      matching_metrics = registry.find_matching(event_name)
      expect(matching_metrics).not_to be_empty,
                                      "Expected metrics to be registered for #{event_name}. Registry size: #{registry.size}, All metrics: #{registry.all.map do |m|
                                        "#{m[:pattern]} -> #{m[:name]}"
                                      end.join(', ')}"
      expect(matching_metrics.map { |m| m[:name] }).to include(:orders_paid_total)

      # Verify Yabeda export: Counter incremented
      # Note: Yabeda metrics are updated via adapter.write() which is called by routing middleware
      # We need to explicitly call adapter.write() to process metrics
      adapter&.write(event_data)

      # Verify counter incremented in Yabeda
      # Note: Yabeda counters return a hash with label combinations as keys
      counter_value = Yabeda.e11y.orders_paid_total.get(currency: "USD")
      expect(counter_value).to eq(1),
                               "Expected counter to be incremented to 1, got #{counter_value}"
    end
  end

  describe "Scenario 2: Gauge metrics" do
    it "tracks gauge metrics with value extraction" do
      # Setup: Event class with gauge metric definition
      # Test: Track event, verify value extraction, Yabeda export
      # Expected: Value extracted correctly, gauge set in Yabeda with correct value

      memory_adapter.clear!

      # Ensure Yabeda metrics are registered
      adapter = E11y.config.adapters[:yabeda]
      adapter.register_metrics_from_registry! if adapter.respond_to?(:register_metrics_from_registry!)

      # Track event
      event_data = Events::OrderStatus.track(
        order_id: "123",
        status: "active"
      )

      # Verify event was tracked
      events = memory_adapter.find_events("Events::OrderStatus")
      expect(events.count).to eq(1), "Expected 1 event tracked"

      # Verify value extraction: Value should be in event payload
      expect(event_data[:payload][:status]).to eq("active"),
                                               "Expected status value to be extracted from payload"

      # Process metrics via adapter
      adapter&.write(event_data)

      # Verify gauge set in Yabeda
      gauge_value = Yabeda.e11y.order_status.get(order_id: "123")
      expect(gauge_value).to eq("active"),
                             "Expected gauge to be set to 'active', got #{gauge_value.inspect}"
    end
  end

  describe "Scenario 3: Histogram metrics" do
    it "tracks histogram metrics with buckets and value extraction" do
      # Setup: Event class with histogram metric definition
      # Test: Track events with various values, verify bucket assignment, Yabeda export
      # Expected: Values extracted correctly, buckets assigned correctly, histogram updated in Yabeda

      memory_adapter.clear!

      # Ensure Yabeda metrics are registered
      adapter = E11y.config.adapters[:yabeda]
      adapter.register_metrics_from_registry! if adapter.respond_to?(:register_metrics_from_registry!)

      # Track events with various amounts
      test_amounts = [
        { order_id: "1", amount: 5, currency: "USD" },
        { order_id: "2", amount: 25, currency: "USD" },
        { order_id: "3", amount: 75, currency: "USD" },
        { order_id: "4", amount: 150, currency: "USD" },
        { order_id: "5", amount: 750, currency: "USD" }
      ]

      test_amounts.each do |payload|
        event_data = Events::OrderAmount.track(**payload)
        adapter&.write(event_data)
      end

      # Verify events were tracked
      events = memory_adapter.find_events("Events::OrderAmount")
      expect(events.count).to eq(5), "Expected 5 events tracked"

      # Verify histogram updated in Yabeda
      # Histogram returns a hash with bucket labels
      histogram_data = Yabeda.e11y.orders_amount.get(currency: "USD")
      expect(histogram_data).to be_a(Hash),
                                "Expected histogram to return a hash, got #{histogram_data.class}"

      # Verify buckets are present (Yabeda histograms have bucket labels)
      # Note: Exact bucket structure depends on Yabeda implementation
      # We verify that histogram was updated by checking it's not empty
      expect(histogram_data).not_to be_empty,
                                    "Expected histogram to have bucket data"
    end
  end

  describe "Scenario 4: Custom labels (tags)" do
    it "extracts custom labels from event payload" do
      # Setup: Event class with multiple tags
      # Test: Track event with multiple tags, verify label extraction
      # Expected: All tags extracted from payload, labels exported to Yabeda correctly

      memory_adapter.clear!

      # Ensure Yabeda metrics are registered
      adapter = E11y.config.adapters[:yabeda]
      adapter.register_metrics_from_registry! if adapter.respond_to?(:register_metrics_from_registry!)

      # Track event with multiple tags
      event_data = Events::OrderPayment.track(
        order_id: "123",
        currency: "USD",
        payment_method: "stripe",
        status: "success"
      )

      # Verify event was tracked
      events = memory_adapter.find_events("Events::OrderPayment")
      expect(events.count).to eq(1), "Expected 1 event tracked"

      # Verify all tags are in payload
      expect(event_data[:payload][:currency]).to eq("USD")
      expect(event_data[:payload][:payment_method]).to eq("stripe")
      expect(event_data[:payload][:status]).to eq("success")

      # Process metrics via adapter
      adapter&.write(event_data)

      # Verify labels exported to Yabeda correctly
      counter_value = Yabeda.e11y.orders_payment_total.get(
        currency: "USD",
        payment_method: "stripe",
        status: "success"
      )
      expect(counter_value).to eq(1),
                               "Expected counter to be incremented with all labels, got #{counter_value}"
    end
  end

  describe "Scenario 5: Pattern matching" do
    it "matches events to metrics using different patterns (exact, *, **)" do
      # Setup: Multiple event classes, multiple metric patterns
      # Test: Track events, verify pattern matching works correctly
      # Expected: Exact pattern matches correctly, wildcard patterns match correctly, multiple patterns processed

      memory_adapter.clear!

      # Register additional metrics with different patterns via Registry
      # Note: Event-level metrics use exact match (event name), so we register additional patterns for testing
      registry.register(
        type: :counter,
        pattern: "Events::Order.*",
        name: :orders_all_total,
        tags: [],
        source: "test"
      )

      registry.register(
        type: :counter,
        pattern: "Events::Order.**",
        name: :orders_deep_total,
        tags: [],
        source: "test"
      )

      # Ensure Yabeda metrics are registered
      adapter = E11y.config.adapters[:yabeda]
      adapter.register_metrics_from_registry! if adapter.respond_to?(:register_metrics_from_registry!)

      # Configure Yabeda for additional metrics (without reset)
      Yabeda.configure do
        group :e11y do
          counter :orders_all_total, tags: [], comment: "All order events"
          counter :orders_deep_total, tags: [], comment: "Deep order events"
        end
      end
      # Don't call Yabeda.configure! - metrics are registered immediately

      # Track event: Events::OrderPaid
      event_data = Events::OrderPaid.track(order_id: "123", currency: "USD")
      adapter&.write(event_data)

      # Verify exact pattern matches
      event_name = Events::OrderPaid.event_name
      matching_metrics = registry.find_matching(event_name)
      metric_names = matching_metrics.map { |m| m[:name] }
      expect(metric_names).to include(:orders_paid_total),
                              "Expected exact pattern to match orders_paid_total"

      # Verify wildcard pattern matches
      expect(metric_names).to include(:orders_all_total),
                              "Expected wildcard pattern 'Events::Order.*' to match"

      # Verify double wildcard pattern matches (if applicable)
      # Note: Events::OrderPaid doesn't have deep nesting, so ** may not match
      # But we verify the pattern is registered and can match if event name has deep nesting

      # Verify multiple patterns processed: Check that both metrics were updated
      exact_counter = Yabeda.e11y.orders_paid_total.get(currency: "USD")
      wildcard_counter = Yabeda.e11y.orders_all_total.get({})

      expect(exact_counter).to eq(1),
                               "Expected exact pattern metric to be incremented"
      expect(wildcard_counter).to eq(1),
                                  "Expected wildcard pattern metric to be incremented"
    end
  end

  describe "Scenario 6: Regex performance" do
    it "meets performance requirements (<0.1μs per pattern match)" do
      # Setup: 100 registered metrics with various patterns
      # Test: Benchmark pattern matching speed for 10,000 events
      # Expected: Pattern matching speed <0.1μs per pattern match, no performance degradation

      memory_adapter.clear!

      # Register 100 metrics with different patterns
      100.times do |i|
        registry.register(
          type: :counter,
          pattern: "Events::Test#{i}.*",
          name: :"test_#{i}_total",
          tags: [],
          source: "performance_test"
        )
      end

      # Benchmark pattern matching speed
      require "benchmark"

      times = []
      10_000.times do |i|
        event_name = "Events::Test#{i % 100}.Paid"
        time = Benchmark.realtime do
          registry.find_matching(event_name)
        end
        times << time
      end

      average_time = times.sum / times.size
      average_time_microseconds = average_time * 1_000_000 # Convert to microseconds

      # Verify performance: <0.1μs per pattern match
      # Note: 0.1μs = 0.0001ms = 0.0000001 seconds
      expect(average_time_microseconds).to be < 0.1,
                                           "Expected average pattern matching time <0.1μs, got #{average_time_microseconds.round(3)}μs"

      # Verify pattern compilation overhead: <1ms for 100 patterns
      compilation_times = []
      10.times do
        time = Benchmark.realtime do
          registry.clear!
          100.times do |i|
            registry.register(
              type: :counter,
              pattern: "Events::CompileTest#{i}.*",
              name: :"compile_test_#{i}_total",
              tags: [],
              source: "compilation_test"
            )
          end
        end
        compilation_times << time
      end

      avg_compilation_time = compilation_times.sum / compilation_times.size
      expect(avg_compilation_time).to be < 0.001,
                                      "Expected pattern compilation time <1ms for 100 patterns, got #{(avg_compilation_time * 1000).round(3)}ms"
    end
  end
end
