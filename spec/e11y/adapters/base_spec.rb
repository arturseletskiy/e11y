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
  end
end
