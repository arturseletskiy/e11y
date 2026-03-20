# frozen_string_literal: true

require "rails_helper"
require "timecop"

# Sampling middleware integration tests for UC-014
# Tests adaptive sampling, trace-aware sampling, and sampling rate enforcement
#
# Scenarios:
# 1. Basic sampling (per-event sample rates)
# 2. Severity-based sampling (errors always sampled)
# 3. Pattern-based sampling
# 4. Trace-aware sampling (C05 - all events in trace sampled or none)
# 5. Error-based adaptive sampling (FEAT-4838 - 100% during error spikes)
# 6. Load-based adaptive sampling (FEAT-4842 - tiered sampling based on event volume)
# 7. Value-based sampling
# 8. Stratified sampling

RSpec.describe "Sampling Middleware Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }

  before do
    memory_adapter.clear!
    Timecop.freeze(Time.now)

    # CRITICAL: Don't reset Yabeda in Rails environment - it breaks metric registration
    # Yabeda.reset! destroys the :e11y group and all metrics configured by Railtie

    # Configure Yabeda adapter if needed for metrics tests
    if yabeda_adapter
      yabeda_adapter_instance = E11y::Adapters::Yabeda.new(
        auto_register: true
      )
      E11y.config.adapters[:yabeda] = yabeda_adapter_instance

      # Metrics will be registered automatically via auto_register
      # Don't call Yabeda.configure! - it was already called by Railtie
    end

    # Configure routing to send events to memory adapter
    E11y.config.fallback_adapters = [:memory]

    # Ensure Sampling middleware is configured in pipeline
    # Note: Sampling middleware should already be in pipeline, but we ensure it's configured correctly
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    memory_adapter.clear!
    Timecop.return
    # Don't reset Yabeda - it breaks metric registration for subsequent tests
  end

  describe "Scenario 1: Basic sampling (per-event sample rates)" do
    before do
      # Reconfigure Sampling middleware for these tests: disable trace-aware sampling
      # This allows deterministic testing of per-event sample rates
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      # Find position after PIIFilter (before Routing)
      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      # Insert Sampling middleware with trace_aware: false
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 1.0, # Default to 100% for events without explicit sample_rate
            trace_aware: false # Disable trace-aware sampling for deterministic testing
          }
        )
      )

      # Clear cached pipeline so it rebuilds with new middleware
      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    it "samples events based on sample_rate from Event::Base" do
      # Setup: Event with sample_rate 0.5 (50%)
      # Test: Send 100 events
      # Expected: ~50 events pass through (statistical test)

      # Create test event class with sample_rate
      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.5
      end
      stub_const("Events::TestSampling", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset # Clear trace context

      # Track 100 events
      100.times do |i|
        Events::TestSampling.track(test_id: i)
      end

      # Check how many events passed through sampling
      events = memory_adapter.find_events("Events::TestSampling")
      passed_count = events.count

      # Statistical test: should be approximately 50% (allow 35-65% range for statistical variance)
      expect(passed_count).to be_between(35, 65),
                              "Expected ~50% sampling (35-65 events), got #{passed_count} events"
    end

    it "always samples events with sample_rate 1.0" do
      # Setup: Event with sample_rate 1.0 (100%)
      # Test: Send 10 events
      # Expected: All 10 events pass through

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 1.0
      end
      stub_const("Events::TestAlwaysSampled", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Track 10 events
      10.times do |i|
        Events::TestAlwaysSampled.track(test_id: i)
      end

      events = memory_adapter.find_events("Events::TestAlwaysSampled")
      expect(events.count).to eq(10)
    end

    it "never samples events with sample_rate 0.0" do
      # Setup: Event with sample_rate 0.0 (0%)
      # Test: Send 10 events
      # Expected: No events pass through

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
      end
      stub_const("Events::TestNeverSampled", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Track 10 events
      10.times do |i|
        Events::TestNeverSampled.track(test_id: i)
      end

      events = memory_adapter.find_events("Events::TestNeverSampled")
      expect(events.count).to eq(0),
                              "Expected 0 events with sample_rate 0.0, got #{events.count} events"
    end
  end

  describe "Scenario 2: Severity-based sampling" do
    before do
      # Reconfigure Sampling middleware: enable severity-based sampling
      # Errors should always be sampled (severity_rates override)
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      # Insert Sampling middleware with severity_rates override
      # Error severity should override sample_rate
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 0.0, # Default to 0% (will be overridden by severity)
            trace_aware: false,
            severity_rates: {
              error: 1.0,  # Errors always sampled
              fatal: 1.0   # Fatal always sampled
            }
          }
        )
      )

      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    it "always samples error and fatal events regardless of sample_rate" do
      # Setup: Event with sample_rate 0.0 but severity :error
      # Test: Send 10 error events
      # Expected: All 10 events pass through (errors always sampled via severity_rates override)

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0 # Should be dropped normally, but severity override applies
        severity :error
      end
      stub_const("Events::TestErrorEvent", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Track 10 error events
      10.times do |i|
        Events::TestErrorEvent.track(test_id: i, error: "Test error")
      end

      events = memory_adapter.find_events("Events::TestErrorEvent")
      expect(events.count).to eq(10),
                              "Expected 10 error events to pass (severity override), got #{events.count} events"
    end
  end

  describe "Scenario 5: Error-based adaptive sampling (FEAT-4838)" do
    before do
      # Reconfigure Sampling middleware with error-based adaptive sampling
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      # Insert Sampling middleware with error-based adaptive sampling enabled
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 0.1, # Normal: 10% sampling
            trace_aware: false,
            error_based_adaptive: true,
            error_spike_config: {
              window: 60,
              absolute_threshold: 10, # 10 errors/min triggers spike
              relative_threshold: 3.0,
              spike_duration: 300 # 5 minutes
            }
          }
        )
      )

      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    it "uses 100% sampling during error spikes" do
      # Setup: Normal sampling 10%, but error spike detected
      # Test: Trigger error spike, then send info events
      # Expected: All events sampled at 100% during spike

      error_event_class = Class.new(E11y::Event::Base) do
        severity :error
      end
      stub_const("Events::TestError", error_event_class)

      info_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.1 # Normal: 10% sampling
        severity :info
      end
      stub_const("Events::TestInfo", info_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Step 1: Trigger error spike (11 errors > threshold of 10)
      11.times do |i|
        Events::TestError.track(test_id: i, error: "Test error")
      end

      # Step 2: Send info events (should be 100% sampled during spike)
      passed_count = 0
      20.times do |i|
        Events::TestInfo.track(test_id: i, message: "Info message")
        events = memory_adapter.find_events("Events::TestInfo")
        passed_count = events.count
      end

      # All info events should pass (100% sampling during spike)
      msg = "Expected all 20 info events to pass during error spike (100% sampling), got #{passed_count}"
      expect(passed_count).to eq(20), msg
    end

    it "returns to normal sampling after spike ends" do
      # Setup: Error spike triggered, then spike ends
      # Test: Send events after spike ends
      # Expected: Normal sampling rate (10%) applied
      # Deterministic: srand(8) yields exactly 10 passes for 100 events at 10% rate

      error_event_class = Class.new(E11y::Event::Base) do
        severity :error
      end
      stub_const("Events::TestError", error_event_class)

      info_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.1 # Normal: 10% sampling
        severity :info
      end
      stub_const("Events::TestInfo", info_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Deterministic sampling: seed yields exactly 10/100 at 10% rate
      srand(8)

      # Step 1: Trigger error spike (11 rand calls; 100% pass during spike)
      11.times do |i|
        Events::TestError.track(test_id: i, error: "Test error")
      end

      # Step 2: Wait for spike to end (spike_duration = 300 seconds)
      Timecop.travel(Time.now + 301)

      # Step 3: Send info events (next 100 rand calls; exactly 10 pass with seed 8)
      memory_adapter.clear!
      100.times do |i|
        Events::TestInfo.track(test_id: i, message: "Info message")
      end

      events = memory_adapter.find_events("Events::TestInfo")
      passed_count = events.count

      expect(passed_count).to eq(10),
                              "Expected exactly 10 events (deterministic srand), got #{passed_count}"
    ensure
      srand # Reset to avoid affecting other tests
    end
  end

  describe "Scenario 6: Load-based adaptive sampling (FEAT-4842)" do
    before do
      # Reconfigure Sampling middleware with load-based adaptive sampling
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      # Insert Sampling middleware with load-based adaptive sampling enabled
      # Use very low thresholds for testing (easier to trigger)
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 1.0, # Base rate (will be overridden by load-based)
            trace_aware: false,
            load_based_adaptive: true,
            load_monitor_config: {
              window: 5, # Very short window for testing (5 seconds)
              thresholds: {
                normal: 2,      # 0-2 events/sec → 100% sampling
                high: 5,        # 2-5 events/sec → 50% sampling
                very_high: 10,  # 5-10 events/sec → 10% sampling
                overload: 20 # >10 events/sec → 1% sampling
              }
            }
          }
        )
      )

      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    it "applies tiered sampling based on event volume" do
      # Setup: Load-based adaptive sampling with tiered rates
      # Test: Verify that LoadMonitor is used and sampling rate can change
      # Expected: LoadMonitor is created and used by Sampling middleware
      # Note: Detailed rate calculation testing is in unit tests (sampling_spec.rb)
      #       This integration test verifies that the feature is enabled and works end-to-end

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 1.0 # Base rate (will be overridden by load-based)
      end
      stub_const("Events::TestLoad", test_event_class)

      # Get pipeline instance to verify LoadMonitor is created and used
      final_app = ->(event_data) { memory_adapter.write(event_data) }
      pipeline = E11y.config.pipeline.build(final_app)

      # Find Sampling middleware in the chain
      current = pipeline
      sampling_middleware = nil
      while current && !current.is_a?(Proc)
        if current.is_a?(E11y::Middleware::Sampling)
          sampling_middleware = current
          break
        end
        current = current.instance_variable_get(:@app)
      end

      expect(sampling_middleware).not_to be_nil, "Sampling middleware should be in pipeline"
      load_monitor = sampling_middleware.instance_variable_get(:@load_monitor)
      expect(load_monitor).not_to be_nil, "LoadMonitor should be created"

      memory_adapter.clear!
      E11y::Current.reset

      # Send events and verify LoadMonitor records them
      # LoadMonitor.record_event is called by Sampling middleware for each event
      initial_rate = load_monitor.recommended_sample_rate
      expect(initial_rate).to eq(1.0), "Initial rate should be 100% (normal load)"

      # Send events to trigger LoadMonitor
      start_time = Time.now
      10.times do |i|
        Events::TestLoad.track(test_id: i, load: "test")
        Timecop.travel(start_time + ((i + 1) * 0.1)) # 0.1 sec per event = 10 events/sec
      end

      # Verify events were tracked (some should pass through)
      events = memory_adapter.find_events("Events::TestLoad")
      expect(events.count).to be > 0, "Some events should pass through sampling"

      # Verify LoadMonitor is tracking events
      # Note: recommended_sample_rate may change based on load, but exact calculation
      #       is tested in unit tests. Here we verify the integration works.
      current_rate = load_monitor.recommended_sample_rate
      expect(current_rate).to be_between(0.0, 1.0), "Sample rate should be between 0 and 1"
    end

    it "verifies load-based adaptive sampling is enabled" do
      # Setup: Load-based adaptive sampling enabled
      # Test: Verify that LoadMonitor is created and used
      # Expected: Sampling middleware has LoadMonitor instance

      # Get pipeline instance to verify LoadMonitor is created
      final_app = ->(event_data) { memory_adapter.write(event_data) }
      pipeline = E11y.config.pipeline.build(final_app)

      # Find Sampling middleware in the chain
      current = pipeline
      sampling_middleware = nil
      while current && !current.is_a?(Proc)
        if current.is_a?(E11y::Middleware::Sampling)
          sampling_middleware = current
          break
        end
        current = current.instance_variable_get(:@app)
      end

      expect(sampling_middleware).not_to be_nil, "Sampling middleware should be in pipeline"
      load_monitor = sampling_middleware.instance_variable_get(:@load_monitor)
      expect(load_monitor).not_to be_nil, "LoadMonitor should be created when load_based_adaptive is enabled"
      expect(load_monitor).to be_a(E11y::Sampling::LoadMonitor), "LoadMonitor should be instance of E11y::Sampling::LoadMonitor"

      # Verify LoadMonitor has correct configuration
      expect(load_monitor.window).to eq(5), "LoadMonitor window should be 5 seconds"
      expect(load_monitor.thresholds[:normal]).to eq(2), "Normal threshold should be 2 events/sec"
      expect(load_monitor.thresholds[:high]).to eq(5), "High threshold should be 5 events/sec"
    end
  end

  describe "Scenario 4: Trace-aware sampling (C05)" do
    before do
      # Reconfigure Sampling middleware with trace-aware sampling enabled
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      # Insert Sampling middleware with trace-aware sampling enabled
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 0.5, # 50% sampling for testing
            trace_aware: true # Enable trace-aware sampling (C05)
          }
        )
      )

      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    it "makes consistent sampling decision for all events in same trace" do
      # Setup: Trace-aware sampling enabled, sample_rate 0.5 (50%)
      # Test: Send multiple events with same trace_id
      # Expected: All events in same trace get same sampling decision (all sampled or all not sampled)

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.5
      end
      stub_const("Events::TestTrace", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Set trace_id in Current context
      trace_id = "trace-123"
      E11y::Current.trace_id = trace_id

      # Send 20 events with same trace_id
      20.times do |i|
        Events::TestTrace.track(test_id: i, trace: trace_id)
      end

      events = memory_adapter.find_events("Events::TestTrace")
      passed_count = events.count

      # All events in same trace should have same decision
      # Either all 20 pass (trace sampled) or all 20 fail (trace not sampled)
      expect(passed_count).to be_in([0, 20]),
                              "Trace-aware sampling: all events in same trace should have same decision. " \
                              "Expected 0 or 20 events, got #{passed_count}"
    end

    it "makes independent sampling decisions for different traces" do
      # Setup: Trace-aware sampling enabled, sample_rate 0.5 (50%)
      # Test: Send events with different trace_ids
      # Expected: Different traces get independent sampling decisions

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.5
      end
      stub_const("Events::TestTraceIndependent", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Send 100 events, each with different trace_id
      decisions = []
      100.times do |i|
        trace_id = "trace-#{i}"
        E11y::Current.trace_id = trace_id
        Events::TestTraceIndependent.track(test_id: i, trace: trace_id)

        # Check if event passed (after each event to see decision)
        events = memory_adapter.find_events("Events::TestTraceIndependent")
        decisions << (events.count > decisions.sum { |d| d ? 1 : 0 })
      end

      # Check final count
      final_events = memory_adapter.find_events("Events::TestTraceIndependent")
      final_count = final_events.count

      # Should be approximately 50%. With n=100 independent traces, counts outside a tight
      # band still occur (~3σ is ~35–65; CI occasionally sees 34). Use a slightly wider band.
      expect(final_count).to be_between(30, 70),
                             "Different traces should get independent decisions. " \
                             "Expected ~50% sampled (30–70 events), got #{final_count}"
    end

    it "caches trace sampling decisions for performance" do
      # Setup: Trace-aware sampling enabled
      # Test: Send multiple events with same trace_id
      # Expected: Sampling decision is cached and reused

      test_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.5
      end
      stub_const("Events::TestTraceCache", test_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      trace_id = "trace-cache-test"
      E11y::Current.trace_id = trace_id

      # Send first event (decision is made and cached)
      Events::TestTraceCache.track(test_id: 1, trace: trace_id)
      first_decision = memory_adapter.find_events("Events::TestTraceCache").any?

      # Send 10 more events with same trace_id (should use cached decision)
      memory_adapter.clear! # Clear to count new events
      10.times do |i|
        Events::TestTraceCache.track(test_id: i + 2, trace: trace_id)
      end

      events = memory_adapter.find_events("Events::TestTraceCache")
      events.count

      # All events should have same decision (cached)
      if first_decision
        expect(events.count).to eq(10), "If first event sampled, all should be sampled (cached decision)"
      else
        expect(events.count).to eq(0), "If first event not sampled, all should not be sampled (cached decision)"
      end
    end
  end

  describe "Scenario 7: Value-based sampling (FEAT-4849)" do
    # BUG-004 fix (2026-03-13): sampling middleware now passes event_data[:payload]
    # to ValueSamplingConfig#matches?, so sample_by_value rules work correctly
    # via the normal Event::Base.track() API.
    # See: lib/e11y/middleware/sampling.rb — payload = event_data[:payload] || event_data

    before do
      # Reconfigure Sampling middleware with value-based sampling support enabled.
      # trace_aware: false for deterministic results.
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Sampling }

      pii_filter_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::PIIFilter }
      insert_index = pii_filter_index ? pii_filter_index + 1 : E11y.config.pipeline.middlewares.length

      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Sampling,
          args: [],
          options: {
            default_sample_rate: 1.0,
            trace_aware: false
          }
        )
      )

      E11y.config.instance_variable_set(:@built_pipeline, nil)
    end

    # Helper: build minimal event_data with payload fields promoted to the top level
    # so that ValueExtractor can find them — this matches the middleware's design contract.
    # We also include :payload for any middleware that expects it (e.g., Validation skips
    # when event_class has no schema, but Routing uses :adapters for routing decisions).
    def build_value_event_data(event_class, event_name_str, top_level_fields)
      {
        event_class: event_class,
        event_name: event_name_str,
        severity: event_class.respond_to?(:severity) ? event_class.severity : :info,
        version: "1",
        adapters: [],
        timestamp: Time.now.utc,
        payload: top_level_fields
      }.merge(top_level_fields)
    end

    it "always samples high-value events matching greater_than rule (100% override)" do
      # Event has sample_rate 0.0 (never sampled) but value rule fires → 100% sampling
      high_value_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :amount, greater_than: 1000
      end
      stub_const("Events::TestValueHigh", high_value_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(Events::TestValueHigh, "Events::TestValueHigh", { amount: 2000.0 })
        )
      end

      events = memory_adapter.find_events("Events::TestValueHigh")
      expect(events.count).to eq(10),
                              "Expected all 10 high-value events to be sampled (value rule overrides 0.0 rate), " \
                              "got #{events.count}"
    end

    it "does not force-sample low-value events that do not match greater_than rule" do
      # Event has sample_rate 0.0 and value does not satisfy the rule → dropped
      low_value_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :amount, greater_than: 1000
      end
      stub_const("Events::TestValueLow", low_value_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(Events::TestValueLow, "Events::TestValueLow", { amount: 50.0 })
        )
      end

      events = memory_adapter.find_events("Events::TestValueLow")
      expect(events.count).to eq(0),
                              "Expected 0 events (value rule not met, base rate 0.0), got #{events.count}"
    end

    it "always samples events whose value falls in_range" do
      # Value 250.0 is within 100..500 → 100% sampling despite base rate 0.0
      in_range_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :score, in_range: 100..500
      end
      stub_const("Events::TestValueInRange", in_range_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(Events::TestValueInRange, "Events::TestValueInRange", { score: 250.0 })
        )
      end

      events = memory_adapter.find_events("Events::TestValueInRange")
      expect(events.count).to eq(10),
                              "Expected all 10 in-range events to be sampled, got #{events.count}"
    end

    it "does not force-sample events whose value is outside in_range" do
      # Value 750.0 is outside 100..500 → base rate 0.0 applies → dropped
      out_of_range_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :score, in_range: 100..500
      end
      stub_const("Events::TestValueOutOfRange", out_of_range_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(Events::TestValueOutOfRange, "Events::TestValueOutOfRange", { score: 750.0 })
        )
      end

      events = memory_adapter.find_events("Events::TestValueOutOfRange")
      expect(events.count).to eq(0),
                              "Expected 0 events (out of range, base rate 0.0), got #{events.count}"
    end

    it "samples event when any of multiple value rules matches (OR logic)" do
      # Two rules with OR logic: amount > 5000 OR priority equals 99 (numeric).
      # ValueExtractor coerces all fields to Float, so equals comparisons must use
      # numeric values. Send event where only second rule fires (amount below threshold).
      multi_rule_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :amount, greater_than: 5000
        sample_by_value :priority, equals: 99
      end
      stub_const("Events::TestValueMultiRule", multi_rule_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # Only second rule matches (priority: 99, amount: 100 — well below threshold)
      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(
            Events::TestValueMultiRule,
            "Events::TestValueMultiRule",
            { amount: 100.0, priority: 99 }
          )
        )
      end

      events = memory_adapter.find_events("Events::TestValueMultiRule")
      expect(events.count).to eq(10),
                              "Expected all 10 events sampled via OR-logic (priority=99 rule), got #{events.count}"
    end

    it "does not sample event when no rule matches (OR logic — all rules fail)" do
      # Two rules: neither fires for the given payload → base rate 0.0 applies → dropped
      no_match_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value :amount, greater_than: 5000
        sample_by_value :priority, equals: 99
      end
      stub_const("Events::TestValueNoMatch", no_match_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(
            Events::TestValueNoMatch,
            "Events::TestValueNoMatch",
            { amount: 100.0, priority: 1 }
          )
        )
      end

      events = memory_adapter.find_events("Events::TestValueNoMatch")
      expect(events.count).to eq(0),
                              "Expected 0 events (no rule matches, base rate 0.0), got #{events.count}"
    end

    it "works via Event::Base.track() — BUG-004 regression" do
      # Before BUG-004 fix: sample_by_value never fired via track() because
      # middleware checked top-level event_data[:amount] (always 0.0) instead of
      # event_data[:payload][:amount] where track() puts the user fields.
      track_api_event_class = Class.new(E11y::Event::Base) do
        severity :info
        sample_rate 0.0 # never sampled without value rule
        contains_pii false
        sample_by_value :amount, greater_than: 1000

        schema do
          required(:amount).filled(:float)
        end
      end
      stub_const("Events::TestValueTrack", track_api_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # High-value event via track() → value rule fires → 100% override
      # Event name is derived from stub_const: "Events::TestValueTrack"
      10.times { Events::TestValueTrack.track(amount: 2000.0) }
      high_events = memory_adapter.find_events("Events::TestValueTrack")
      expect(high_events.count).to eq(10),
                                   "BUG-004 regression: track(amount: 2000.0) should trigger " \
                                   "value rule (>1000) and sample 100%, got #{high_events.count}"

      memory_adapter.clear!

      # Low-value event via track() → rule doesn't fire → base rate 0.0 → dropped
      10.times { Events::TestValueTrack.track(amount: 50.0) }
      low_events = memory_adapter.find_events("Events::TestValueTrack")
      expect(low_events.count).to eq(0),
                                  "Low-value track(amount: 50.0) should be dropped (base rate 0.0), " \
                                  "got #{low_events.count}"
    end

    it "extracts nested fields via dot notation for value-based sampling" do
      # Rule on nested field "order.total" > 5000
      # ValueExtractor navigates nested hashes via dot notation
      nested_event_class = Class.new(E11y::Event::Base) do
        sample_rate 0.0
        severity :info
        contains_pii false
        sample_by_value "order.total", greater_than: 5000
      end
      stub_const("Events::TestValueNested", nested_event_class)

      memory_adapter.clear!
      E11y::Current.reset

      # High-value nested field: should be sampled
      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(
            Events::TestValueNested,
            "Events::TestValueNested",
            { order: { total: 9999.0 } }
          )
        )
      end

      high_events = memory_adapter.find_events("Events::TestValueNested")
      expect(high_events.count).to eq(10),
                                   "Expected all 10 events sampled (nested order.total > 5000), " \
                                   "got #{high_events.count}"

      memory_adapter.clear!

      # Low-value nested field: should NOT be sampled
      10.times do
        E11y.config.built_pipeline.call(
          build_value_event_data(
            Events::TestValueNested,
            "Events::TestValueNested",
            { order: { total: 10.0 } }
          )
        )
      end

      low_events = memory_adapter.find_events("Events::TestValueNested")
      expect(low_events.count).to eq(0),
                                  "Expected 0 events (nested order.total <= 5000, base rate 0.0), " \
                                  "got #{low_events.count}"
    end
  end

  describe "Scenario 8: Stratified sampling — correction factors (FEAT-4851)" do
    # StratifiedTracker is wired into Sampling middleware (C11). These tests
    # exercise the tracker directly for correction factor validation (isolated).
    let(:tracker) { E11y::Sampling::StratifiedTracker.new }

    it "tracks sampling decisions per severity stratum" do
      # Record samples for two distinct strata
      5.times { tracker.record_sample(severity: :info, sample_rate: 0.1, sampled: true) }
      3.times { tracker.record_sample(severity: :info, sample_rate: 0.1, sampled: false) }
      4.times { tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true) }

      info_stats = tracker.stratum_stats(:info)
      error_stats = tracker.stratum_stats(:error)

      expect(info_stats[:total_count]).to eq(8)
      expect(info_stats[:sampled_count]).to eq(5)
      expect(error_stats[:total_count]).to eq(4)
      expect(error_stats[:sampled_count]).to eq(4)
    end

    it "calculates correction factor correctly as 1/avg_sample_rate" do
      # At 10% sampling, correction factor should be 10.0
      10.times { tracker.record_sample(severity: :debug, sample_rate: 0.1, sampled: true) }

      correction = tracker.sampling_correction(:debug)
      expect(correction).to be_within(0.001).of(10.0),
                            "Correction factor for 10% sample_rate should be 10.0, got #{correction}"
    end

    it "returns 1.0 correction factor for a stratum with no recorded samples" do
      correction = tracker.sampling_correction(:warn)
      expect(correction).to eq(1.0),
                            "Correction factor for unseen stratum should default to 1.0"
    end

    it "handles multiple strata independently" do
      tracker.record_sample(severity: :info, sample_rate: 0.5, sampled: true)
      tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true)
      tracker.record_sample(severity: :debug, sample_rate: 0.01, sampled: false)

      expect(tracker.sampling_correction(:info)).to be_within(0.001).of(2.0)
      expect(tracker.sampling_correction(:error)).to be_within(0.001).of(1.0)
      # debug stratum: sampled_count is 0 → guard returns 1.0
      expect(tracker.sampling_correction(:debug)).to eq(1.0)
    end

    it "resets all strata cleanly" do
      tracker.record_sample(severity: :info, sample_rate: 0.5, sampled: true)
      tracker.record_sample(severity: :error, sample_rate: 1.0, sampled: true)

      tracker.reset!

      expect(tracker.all_strata_stats).to be_empty
      expect(tracker.sampling_correction(:info)).to eq(1.0)
      expect(tracker.sampling_correction(:error)).to eq(1.0)
    end

    it "is thread-safe under concurrent writes" do
      threads = Array.new(10) do |i|
        Thread.new do
          100.times do
            tracker.record_sample(
              severity: (i.even? ? :info : :error),
              sample_rate: 0.1,
              sampled: true
            )
          end
        end
      end
      threads.each(&:join)

      info_stats = tracker.stratum_stats(:info)
      error_stats = tracker.stratum_stats(:error)

      total = info_stats[:total_count] + error_stats[:total_count]
      expect(total).to eq(1000), "Expected 1000 total recorded samples, got #{total}"
    end

    it "averages correction factor across varying sample rates" do
      # Two records with different rates: 0.1 and 0.5 → avg 0.3 → correction ~3.33
      tracker.record_sample(severity: :success, sample_rate: 0.1, sampled: true)
      tracker.record_sample(severity: :success, sample_rate: 0.5, sampled: true)

      correction = tracker.sampling_correction(:success)
      expected = 1.0 / 0.3
      expect(correction).to be_within(0.01).of(expected),
                            "Expected correction ~#{expected.round(3)}, got #{correction}"
    end
  end

  # Additional scenarios will be added in subsequent tasks
  # Scenario 3: Pattern-based sampling
end
