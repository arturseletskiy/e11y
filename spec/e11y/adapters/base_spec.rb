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

          def write(event_data)
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

          def write(event_data)
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
end
