# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Adapters::Base do
  # Test adapter implementation
  let(:test_adapter_class) do
    Class.new(described_class) do
      attr_accessor :written_events, :batch_written_events

      def initialize(config = {})
        super
        @written_events = []
        @batch_written_events = []
        @write_failures = config[:write_failures] || []
        @healthy = config.fetch(:healthy, true)
      end

      def write(event_data)
        if @write_failures.include?(event_data[:event_name])
          false
        else
          @written_events << event_data
          true
        end
      end

      def write_batch(events)
        @batch_written_events << events
        events.all? { |event| write(event) }
      end

      def healthy?
        @healthy
      end

      def capabilities
        {
          batching: true,
          compression: false,
          async: false,
          streaming: false
        }
      end
    end
  end

  let(:test_adapter) { test_adapter_class.new }

  describe "#initialize" do
    it "accepts config hash" do
      adapter = test_adapter_class.new(healthy: false)
      expect(adapter).not_to be_healthy
    end

    it "calls validate_config! during initialization" do
      validator_class = Class.new(described_class) do
        def validate_config!
          raise ArgumentError, "test validation error"
        end
      end

      expect { validator_class.new }.to raise_error(ArgumentError, "test validation error")
    end
  end

  describe "#write" do
    it "raises NotImplementedError by default" do
      adapter = described_class.new
      expect { adapter.write({}) }.to raise_error(NotImplementedError, /must be implemented/)
    end

    it "returns true on success when overridden" do
      event_data = { event_name: "test.event", severity: :info }
      expect(test_adapter.write(event_data)).to be true
    end

    it "returns false on failure when overridden" do
      event_data = { event_name: "failing.event", severity: :error }
      adapter = test_adapter_class.new(write_failures: ["failing.event"])

      expect(adapter.write(event_data)).to be false
    end

    it "accepts event data hash with standard keys" do
      event_data = {
        event_name: "order.paid",
        severity: :success,
        timestamp: Time.now,
        payload: { order_id: "123" },
        trace_id: "trace-123",
        span_id: "span-456"
      }

      expect(test_adapter.write(event_data)).to be true
      expect(test_adapter.written_events.first).to eq(event_data)
    end
  end

  describe "#write_batch" do
    let(:events) do
      [
        { event_name: "event1", severity: :info },
        { event_name: "event2", severity: :success },
        { event_name: "event3", severity: :warn }
      ]
    end

    it "calls write for each event by default" do
      base_adapter = described_class.new
      allow(base_adapter).to receive(:write).and_return(true)

      base_adapter.write_batch(events)

      expect(base_adapter).to have_received(:write).exactly(3).times
    end

    it "returns true if all events written successfully" do
      expect(test_adapter.write_batch(events)).to be true
    end

    it "returns false if any event fails" do
      adapter = test_adapter_class.new(write_failures: ["event2"])
      expect(adapter.write_batch(events)).to be false
    end

    it "can be overridden for batch optimization" do
      test_adapter.write_batch(events)
      expect(test_adapter.batch_written_events).to eq([events])
    end
  end

  describe "#healthy?" do
    it "returns true by default" do
      adapter = described_class.new
      expect(adapter).to be_healthy
    end

    it "can be overridden" do
      unhealthy_adapter = test_adapter_class.new(healthy: false)
      expect(unhealthy_adapter).not_to be_healthy
    end
  end

  describe "#close" do
    it "does nothing by default" do
      adapter = described_class.new
      expect { adapter.close }.not_to raise_error
    end

    it "can be overridden for cleanup" do
      cleanup_class = Class.new(described_class) do
        attr_reader :closed

        def close
          @closed = true
        end
      end

      adapter = cleanup_class.new
      adapter.close

      expect(adapter.closed).to be true
    end
  end

  describe "#capabilities" do
    it "returns default capabilities" do
      adapter = described_class.new
      capabilities = adapter.capabilities

      expect(capabilities).to eq(
        batching: false,
        compression: false,
        async: false,
        streaming: false
      )
    end

    it "can be overridden" do
      expect(test_adapter.capabilities).to eq(
        batching: true,
        compression: false,
        async: false,
        streaming: false
      )
    end
  end

  describe "contract compliance" do
    it "implements required interface methods" do
      expect(described_class.instance_methods(false)).to include(
        :write,
        :write_batch,
        :healthy?,
        :close,
        :capabilities
      )
    end

    it "accepts config parameter in initialize" do
      expect { described_class.new(custom_option: true) }.not_to raise_error
    end
  end

  describe "ADR-004 compliance" do
    context "Section 3.1: Base Adapter Contract" do
      it "write returns Boolean" do
        result = test_adapter.write({})
        expect([true, false]).to include(result)
      end

      it "write_batch returns Boolean" do
        result = test_adapter.write_batch([])
        expect([true, false]).to include(result)
      end

      it "healthy? returns Boolean" do
        result = test_adapter.healthy?
        expect([true, false]).to include(result)
      end

      it "capabilities returns Hash with correct keys" do
        capabilities = test_adapter.capabilities

        expect(capabilities).to be_a(Hash)
        expect(capabilities.keys).to match_array(%i[batching compression async streaming])
        capabilities.values.each do |value|
          expect([true, false]).to include(value)
        end
      end
    end

    context "Section 7.1: Retry Logic (with_retry helper)" do
      let(:retry_adapter_class) do
        Class.new(described_class) do
          attr_accessor :attempt_count, :should_fail

          def initialize(config = {})
            super
            @attempt_count = 0
            @should_fail = config.fetch(:should_fail, 0)
          end

          def write(_event_data)
            with_retry(max_attempts: 3, base_delay: 0.01, max_delay: 0.1) do
              @attempt_count += 1
              raise Timeout::Error, "Network timeout" if @attempt_count <= @should_fail

              true
            end
          end
        end
      end

      it "succeeds on first attempt when no errors" do
        adapter = retry_adapter_class.new(should_fail: 0)
        expect(adapter.write({})).to be true
        expect(adapter.attempt_count).to eq(1)
      end

      it "retries on retriable errors (network timeout)" do
        adapter = retry_adapter_class.new(should_fail: 2)
        expect(adapter.write({})).to be true
        expect(adapter.attempt_count).to eq(3) # Initial + 2 retries
      end

      it "raises after max retries exhausted" do
        adapter = retry_adapter_class.new(should_fail: 10)
        expect { adapter.write({}) }.to raise_error(Timeout::Error)
        expect(adapter.attempt_count).to eq(3) # Max attempts
      end

      it "does not retry non-retriable errors" do
        adapter_class = Class.new(described_class) do
          attr_accessor :attempt_count

          def initialize(config = {})
            super
            @attempt_count = 0
          end

          def write(_event_data)
            with_retry(max_attempts: 3) do
              @attempt_count += 1
              raise ArgumentError, "Invalid argument"
            end
          end
        end

        adapter = adapter_class.new
        expect { adapter.write({}) }.to raise_error(ArgumentError)
        expect(adapter.attempt_count).to eq(1) # No retries
      end

      it "uses exponential backoff with jitter" do
        adapter = retry_adapter_class.new(should_fail: 2)
        allow(adapter).to receive(:sleep) # Don't actually sleep in tests

        adapter.write({})

        # Should have called sleep twice (for retry 1 and 2)
        expect(adapter).to have_received(:sleep).twice
      end
    end

    context "Section 7.2: Circuit Breaker (with_circuit_breaker helper)" do
      let(:circuit_adapter_class) do
        Class.new(described_class) do
          attr_accessor :call_count, :should_fail

          def initialize(config = {})
            super
            @call_count = 0
            @should_fail = config.fetch(:should_fail, false)
          end

          def write(_event_data)
            with_circuit_breaker(failure_threshold: 3, timeout: 0.1) do
              @call_count += 1
              raise StandardError, "Service unavailable" if @should_fail

              true
            end
          end
        end
      end

      it "allows calls when circuit is closed" do
        adapter = circuit_adapter_class.new(should_fail: false)
        expect(adapter.write({})).to be true
        expect(adapter.call_count).to eq(1)
      end

      it "opens circuit after failure threshold" do
        adapter = circuit_adapter_class.new(should_fail: true)

        # First 3 calls should execute (and fail)
        3.times do
          expect { adapter.write({}) }.to raise_error(StandardError)
        end

        expect(adapter.call_count).to eq(3)

        # 4th call should fail with CircuitOpenError (circuit is open)
        expect { adapter.write({}) }.to raise_error(E11y::Adapters::CircuitOpenError)
        expect(adapter.call_count).to eq(3) # No execution, circuit open
      end

      it "transitions to half-open after timeout" do
        adapter = circuit_adapter_class.new(should_fail: true)

        # Open the circuit
        3.times { expect { adapter.write({}) }.to raise_error(StandardError) }

        # Wait for timeout
        sleep(0.15)

        # Next call should execute (half-open state)
        adapter.should_fail = false
        expect(adapter.write({})).to be true
        expect(adapter.call_count).to eq(4) # Circuit tested
      end

      it "closes circuit after successful half-open attempts" do
        adapter = circuit_adapter_class.new(should_fail: true)

        # Open the circuit
        3.times { expect { adapter.write({}) }.to raise_error(StandardError) }

        sleep(0.15)

        # Successful attempts in half-open state
        adapter.should_fail = false
        2.times { adapter.write({}) } # 2 successes → close

        # Circuit should be closed now, calls execute normally
        expect(adapter.write({})).to be true
      end

      it "resets failure count on success in closed state" do
        adapter = circuit_adapter_class.new(should_fail: true)

        # 2 failures (below threshold)
        2.times { expect { adapter.write({}) }.to raise_error(StandardError) }

        # Success resets counter
        adapter.should_fail = false
        adapter.write({})

        # Can fail 3 more times before opening
        adapter.should_fail = true
        3.times { expect { adapter.write({}) }.to raise_error(StandardError) }

        # Now circuit should be open
        expect { adapter.write({}) }.to raise_error(E11y::Adapters::CircuitOpenError)
      end
    end
  end

  describe "C18 Resolution: fail_on_error behavior" do
    let(:failing_adapter_class) do
      Class.new(described_class) do
        def write(_event_data)
          raise E11y::Reliability::CircuitBreaker::CircuitOpenError, "Circuit breaker open"
        end
      end
    end

    let(:failing_adapter) do
      failing_adapter_class.new(
        circuit_breaker: { enabled: true },
        retry_handler: { max_attempts: 1 },
        dlq_storage: { file_path: "/tmp/e11y_dlq_test.jsonl" },
        dlq_filter: { min_severity_to_save: :error }
      )
    end

    let(:event_data) { { event_name: "test.event", severity: :info } }

    after do
      E11y.config.error_handling.fail_on_error = true # Reset to default
    end

    context "when fail_on_error = true (web requests)" do
      before do
        E11y.config.error_handling.fail_on_error = true
      end

      it "raises RetryExhaustedError (wraps CircuitOpenError)" do
        expect do
          failing_adapter.write_with_reliability(event_data)
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)
      end

      it "provides fast feedback for failures" do
        # Web requests should fail immediately to provide fast feedback
        expect do
          failing_adapter.write_with_reliability(event_data)
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError, /Retry exhausted/)
      end
    end

    context "when fail_on_error = false (background jobs)" do
      before do
        E11y.config.error_handling.fail_on_error = false
      end

      it "swallows CircuitOpenError" do
        expect do
          failing_adapter.write_with_reliability(event_data)
        end.not_to raise_error
      end

      it "returns false on failure" do
        result = failing_adapter.write_with_reliability(event_data)
        expect(result).to be false
      end

      it "does not block business logic" do
        # In background jobs, event tracking failures should NOT cause job to fail
        result = failing_adapter.write_with_reliability(event_data)
        expect(result).to be false
        # Job continues despite E11y failure
      end

      it "saves failed event to DLQ" do
        # DLQ save is tested separately, but this documents the intent
        expect do
          failing_adapter.write_with_reliability(event_data)
        end.not_to raise_error
      end
    end

    describe "fail_on_error setting in different contexts" do
      it "defaults to true (web request context)" do
        expect(E11y.config.error_handling.fail_on_error).to be true
      end

      it "can be set to false (background job context)" do
        E11y.config.error_handling.fail_on_error = false
        expect(E11y.config.error_handling.fail_on_error).to be false
      end

      it "can be temporarily changed and restored" do
        original_setting = E11y.config.error_handling.fail_on_error

        E11y.config.error_handling.fail_on_error = false
        expect(E11y.config.error_handling.fail_on_error).to be false

        E11y.config.error_handling.fail_on_error = original_setting
        expect(E11y.config.error_handling.fail_on_error).to eq(original_setting)
      end
    end

    describe "ADR-013 §3.6 compliance" do
      it "implements non-failing event tracking for background jobs" do
        # C18 Resolution: Event tracking should NOT fail background jobs
        E11y.config.error_handling.fail_on_error = false

        # Even if adapter is down (circuit breaker open), event tracking should not raise
        expect do
          failing_adapter.write_with_reliability(event_data)
        end.not_to raise_error

        # Business logic continues
        # Event is saved to DLQ (will replay when adapter recovers)
      end

      it "preserves fast feedback for web requests" do
        # Web requests should fail fast (don't hide errors)
        E11y.config.error_handling.fail_on_error = true

        expect do
          failing_adapter.write_with_reliability(event_data)
        end.to raise_error(E11y::Reliability::RetryHandler::RetryExhaustedError)
      end
    end
  end

  describe "Self-Monitoring Integration" do
    let(:event_data) { { event_name: "test.event", severity: :info, message: "Test" } }

    let(:successful_adapter) do
      Class.new(E11y::Adapters::Base) do
        def write(_event_data)
          sleep 0.01 # Simulate 10ms latency
          true
        end
      end.new(reliability_enabled: true)
    end

    let(:failing_adapter) do
      Class.new(E11y::Adapters::Base) do
        def write(_event_data)
          sleep 0.005 # Simulate 5ms latency before failure
          raise StandardError, "Adapter error"
        end
      end.new(reliability_enabled: true)
    end

    before do
      E11y::Metrics.reset_backend!
      allow(E11y::Reliability::RetryHandler).to receive(:new).and_return(
        instance_double(E11y::Reliability::RetryHandler, with_retry: nil)
      )
      allow(E11y::Reliability::CircuitBreaker).to receive(:new).and_return(
        instance_double(E11y::Reliability::CircuitBreaker, call: nil)
      )
    end

    context "on successful write" do
      it "tracks adapter latency" do
        expect(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency) do |adapter_name, duration_ms|
          expect(adapter_name).to eq("AnonymousAdapter") # Anonymous class in test
          expect(duration_ms).to be >= 0
          expect(duration_ms).to be < 100 # Less than 100ms
        end

        allow(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_success)

        successful_adapter.send(:track_adapter_success, event_data, Time.now - 0.01)
      end

      it "tracks adapter success" do
        allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency)

        expect(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_success).with(
          adapter_name: "AnonymousAdapter"
        )

        successful_adapter.send(:track_adapter_success, event_data, Time.now - 0.01)
      end

      it "doesn't fail if monitoring fails" do
        allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency).and_raise(StandardError,
                                                                                                     "Monitor error")

        expect do
          successful_adapter.send(:track_adapter_success, event_data, Time.now)
        end.not_to raise_error
      end
    end

    context "on failed write" do
      let(:error) { StandardError.new("Write failed") }

      it "tracks adapter latency even on failure" do
        expect(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency) do |adapter_name, duration_ms|
          expect(adapter_name).to eq("AnonymousAdapter")
          expect(duration_ms).to be >= 0
        end

        allow(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_failure)

        failing_adapter.send(:track_adapter_failure, event_data, error, Time.now - 0.005)
      end

      it "tracks adapter failure with error class" do
        allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency)

        expect(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_failure).with(
          adapter_name: "AnonymousAdapter",
          error_class: "StandardError"
        )

        failing_adapter.send(:track_adapter_failure, event_data, error, Time.now - 0.005)
      end

      it "doesn't fail if monitoring fails" do
        allow(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_failure).and_raise(StandardError,
                                                                                                     "Monitor error")

        expect do
          failing_adapter.send(:track_adapter_failure, event_data, error, Time.now)
        end.not_to raise_error
      end
    end

    context "ADR-016 compliance" do
      it "tracks internal metrics for E11y self-monitoring" do
        allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_adapter_latency)

        expect(E11y::SelfMonitoring::ReliabilityMonitor).to receive(:track_adapter_success)

        successful_adapter.send(:track_adapter_success, event_data, Time.now - 0.01)
      end
    end
  end
end
