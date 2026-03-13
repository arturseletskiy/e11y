# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/trace_context"

RSpec.describe E11y::Middleware::TraceContext do
  let(:final_app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(final_app) }
  let(:event_data) { { event_name: "Events::Test", payload: { foo: "bar" } } }

  describe ".middleware_zone" do
    it "declares pre_processing zone" do
      expect(described_class.middleware_zone).to eq(:pre_processing)
    end
  end

  describe "#call" do
    it "adds trace_id to event data" do
      result = middleware.call(event_data)

      expect(result[:trace_id]).to be_a(String)
      expect(result[:trace_id].length).to eq(32) # 16 bytes = 32 hex chars
      expect(result[:trace_id]).to match(/\A[0-9a-f]{32}\z/) # Hex format
    end

    it "adds span_id to event data" do
      result = middleware.call(event_data)

      expect(result[:span_id]).to be_a(String)
      expect(result[:span_id].length).to eq(16) # 8 bytes = 16 hex chars
      expect(result[:span_id]).to match(/\A[0-9a-f]{16}\z/) # Hex format
    end

    it "adds timestamp to event data" do
      result = middleware.call(event_data)

      expect(result[:timestamp]).to be_a(String)
      expect(result[:timestamp]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/) # ISO8601
    end

    it "calls the next middleware in the chain" do
      allow(final_app).to receive(:call).and_call_original

      middleware.call(event_data)

      expect(final_app).to have_received(:call).with(event_data)
    end

    it "preserves original event data fields" do
      result = middleware.call(event_data)

      expect(result[:event_name]).to eq("Events::Test")
      expect(result[:payload]).to eq({ foo: "bar" })
    end

    describe "trace_id propagation" do
      it "uses trace_id from E11y::Current if present (priority)" do
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = "thread-trace-id"
        E11y::Current.trace_id = "current-trace-id"

        result = middleware.call(event_data)

        expect(result[:trace_id]).to eq("current-trace-id")
      ensure
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = nil
      end

      it "uses trace_id from Thread.current if E11y::Current is not set" do
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = "custom-trace-id-from-request"

        result = middleware.call(event_data)

        expect(result[:trace_id]).to eq("custom-trace-id-from-request")
      ensure
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = nil
      end

      it "generates new trace_id if Thread.current[:e11y_trace_id] is nil" do
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = nil

        result = middleware.call(event_data)

        expect(result[:trace_id]).to be_a(String)
        expect(result[:trace_id].length).to eq(32)
      ensure
        E11y::Current.reset
      end

      it "does not override existing trace_id in event_data" do
        event_data[:trace_id] = "existing-trace-id"

        result = middleware.call(event_data)

        expect(result[:trace_id]).to eq("existing-trace-id")
      end
    end

    describe "span_id generation" do
      it "generates unique span_id for each event" do
        result1 = middleware.call(event_data.dup)
        result2 = middleware.call(event_data.dup)

        expect(result1[:span_id]).not_to eq(result2[:span_id])
      end

      it "does not override existing span_id in event_data" do
        event_data[:span_id] = "existing-span-id"

        result = middleware.call(event_data)

        expect(result[:span_id]).to eq("existing-span-id")
      end
    end

    describe "parent_trace_id propagation (C17 Resolution)" do
      it "does not add parent_trace_id if not present in E11y::Current" do
        E11y::Current.reset
        E11y::Current.trace_id = "current-trace"

        result = middleware.call(event_data)

        expect(result[:parent_trace_id]).to be_nil
      end

      it "adds parent_trace_id from E11y::Current if present" do
        E11y::Current.reset
        E11y::Current.trace_id = "child-trace"
        E11y::Current.parent_trace_id = "parent-trace-123"

        result = middleware.call(event_data)

        expect(result[:parent_trace_id]).to eq("parent-trace-123")
      end

      it "does not override existing parent_trace_id in event_data" do
        E11y::Current.reset
        E11y::Current.parent_trace_id = "context-parent"
        event_data[:parent_trace_id] = "existing-parent"

        result = middleware.call(event_data)

        expect(result[:parent_trace_id]).to eq("existing-parent")
      end

      it "supports hybrid job tracing (new trace + parent link)" do
        # Simulate HTTP request trace
        E11y::Current.reset
        E11y::Current.trace_id = "http-request-trace"

        # Simulate background job trace (new trace, parent link)
        E11y::Current.trace_id = "job-trace-xyz"
        E11y::Current.parent_trace_id = "http-request-trace"

        result = middleware.call(event_data)

        expect(result[:trace_id]).to eq("job-trace-xyz")
        expect(result[:parent_trace_id]).to eq("http-request-trace")
      end
    end

    describe "timestamp handling" do
      it "uses existing timestamp if present" do
        existing_timestamp = "2025-01-01T00:00:00.000Z"
        event_data[:timestamp] = existing_timestamp

        result = middleware.call(event_data)

        expect(result[:timestamp]).to eq(existing_timestamp)
      end

      it "generates timestamp with millisecond precision" do
        result = middleware.call(event_data)
        parsed_time = Time.iso8601(result[:timestamp])

        expect(parsed_time).to be_within(1).of(Time.now.utc)
        expect(result[:timestamp]).to match(/\.\d{3}Z\z/) # Milliseconds present
      end
    end

    describe "OpenTelemetry compatibility" do
      it "generates trace_id compatible with OTel format (16 bytes)" do
        E11y::Current.reset
        Thread.current[:e11y_trace_id] = nil

        result = middleware.call(event_data)
        trace_id_bytes = [result[:trace_id]].pack("H*")

        expect(trace_id_bytes.bytesize).to eq(16)
      ensure
        E11y::Current.reset
      end

      it "generates span_id compatible with OTel format (8 bytes)" do
        result = middleware.call(event_data)
        span_id_bytes = [result[:span_id]].pack("H*")

        expect(span_id_bytes.bytesize).to eq(8)
      end
    end

    describe "metrics" do
      it "increments processed counter" do
        allow(E11y::Metrics).to receive(:increment)

        middleware.call(event_data)

        expect(E11y::Metrics).to have_received(:increment)
          .with("e11y.middleware.trace_context.processed")
      end
    end
  end

  describe "ADR-015 compliance" do
    it "runs in pre_processing zone (first in pipeline)" do
      expect(described_class.middleware_zone).to eq(:pre_processing)
    end

    it "does not care about event class name (ADR-015 §3.2)" do
      event_data1 = { event_name: "Events::OrderPaidV1", payload: {} }
      event_data2 = { event_name: "Events::OrderPaidV2", payload: {} }

      result1 = middleware.call(event_data1)
      result2 = middleware.call(event_data2)

      # Both get trace context regardless of event_name
      expect(result1[:trace_id]).to be_a(String)
      expect(result1[:trace_id]).not_to be_empty
      expect(result2[:trace_id]).to be_a(String)
      expect(result2[:trace_id]).not_to be_empty
    end
  end

  describe "integration" do
    it "works with full pipeline execution" do
      # Simulate multi-middleware pipeline
      middleware2 = Class.new(E11y::Middleware::Base) do
        def call(event_data)
          event_data[:middleware2] = true
          @app.call(event_data)
        end
      end

      pipeline = middleware2.new(middleware)
      result = pipeline.call(event_data)

      expect(result[:trace_id]).to be_a(String)
      expect(result[:trace_id]).not_to be_empty
      expect(result[:span_id]).to be_a(String)
      expect(result[:span_id]).not_to be_empty
      expect(result[:timestamp]).to be_a(String)
      expect(result[:timestamp]).not_to be_empty
      expect(result[:middleware2]).to be true
    end
  end
end
