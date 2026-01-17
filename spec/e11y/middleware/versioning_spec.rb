# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/versioning"

RSpec.describe E11y::Middleware::Versioning do
  let(:final_app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(final_app) }

  describe ".middleware_zone" do
    it "declares post_processing zone (LAST before routing!)" do
      expect(described_class.middleware_zone).to eq(:post_processing)
    end
  end

  describe "#call" do
    context "with V2 event" do
      it "normalizes event name by removing version suffix" do
        event_data = {
          event_name: "Events::OrderPaidV2",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:event_name]).to eq("Events::OrderPaid")
      end

      it "adds version to payload" do
        event_data = {
          event_name: "Events::OrderPaidV2",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:v]).to eq(2)
      end

      it "preserves original payload fields" do
        event_data = {
          event_name: "Events::OrderPaidV2",
          payload: { order_id: 123, amount: 99.99 }
        }

        result = middleware.call(event_data)

        expect(result[:payload][:order_id]).to eq(123)
        expect(result[:payload][:amount]).to eq(99.99)
      end

      it "does not override existing version in payload" do
        event_data = {
          event_name: "Events::OrderPaidV2",
          payload: { order_id: 123, v: 1 } # Already has version
        }

        result = middleware.call(event_data)

        expect(result[:payload][:v]).to eq(1) # Not overridden
      end
    end

    context "with V1 event (no version suffix)" do
      it "keeps event name unchanged" do
        event_data = {
          event_name: "Events::OrderPaid",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:event_name]).to eq("Events::OrderPaid")
      end

      it "does not add version to payload (ADR-015 line 243)" do
        event_data = {
          event_name: "Events::OrderPaid",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:payload]).not_to have_key(:v)
      end
    end

    context "with higher versions" do
      it "handles V3 events" do
        event_data = {
          event_name: "Events::OrderPaidV3",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:event_name]).to eq("Events::OrderPaid")
        expect(result[:payload][:v]).to eq(3)
      end

      it "handles V10 events (multi-digit versions)" do
        event_data = {
          event_name: "Events::OrderPaidV10",
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:event_name]).to eq("Events::OrderPaid")
        expect(result[:payload][:v]).to eq(10)
      end
    end

    context "with missing event_name or payload" do
      it "skips normalization if event_name is missing" do
        event_data = { payload: { order_id: 123 } }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end

      it "skips normalization if payload is missing" do
        event_data = { event_name: "Events::OrderPaidV2" }

        result = middleware.call(event_data)

        expect(result).to eq(event_data)
      end
    end

    context "with metrics" do
      it "increments normalized metric with version tag" do
        event_data = {
          event_name: "Events::OrderPaidV2",
          payload: { order_id: 123 }
        }

        allow(middleware).to receive(:increment_metric)

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.versioning.normalized", version: 2)
      end
    end
  end

  describe "ADR-015 compliance" do
    it "runs in post_processing zone (LAST before routing)" do
      expect(described_class.middleware_zone).to eq(:post_processing)
    end

    it "normalizes event name for adapters (ADR-015 §3.1 line 110)" do
      event_data = {
        event_name: "Events::OrderPaidV2",
        payload: { order_id: 123, amount: 99.99, currency: "USD" }
      }

      result = middleware.call(event_data)

      # Adapters receive normalized name
      expect(result[:event_name]).to eq("Events::OrderPaid")
      expect(result[:payload][:v]).to eq(2)
    end

    it "only adds version field if version > 1 (ADR-015 §6 line 243)" do
      v1_event = {
        event_name: "Events::OrderPaid",
        payload: { order_id: 123 }
      }

      v2_event = {
        event_name: "Events::OrderPaidV2",
        payload: { order_id: 456 }
      }

      v1_result = middleware.call(v1_event)
      v2_result = middleware.call(v2_event)

      # V1: no version field
      expect(v1_result[:payload]).not_to have_key(:v)

      # V2: version field present
      expect(v2_result[:payload][:v]).to eq(2)
    end

    it "enables easy querying in Loki (ADR-015 §5 line 229-232)" do
      # All versions query: {event_name="Events::OrderPaid"}
      v1_event = { event_name: "Events::OrderPaid", payload: {} }
      v2_event = { event_name: "Events::OrderPaidV2", payload: {} }

      v1_result = middleware.call(v1_event)
      v2_result = middleware.call(v2_event)

      # Both have same normalized name (easy to query all versions)
      expect(v1_result[:event_name]).to eq("Events::OrderPaid")
      expect(v2_result[:event_name]).to eq("Events::OrderPaid")

      # V2 has explicit version (easy to filter)
      expect(v2_result[:payload][:v]).to eq(2)
    end
  end

  describe "ADR-015 §4 Wrong Order Prevention" do
    it "MUST run in post_processing zone (AFTER Validation and PII Filtering)" do
      # CRITICAL: Versioning must be LAST before routing!
      #
      # If Versioning runs TOO EARLY (before Validation):
      # 1. Versioning normalizes "Events::OrderPaidV2" → "Events::OrderPaid"
      # 2. Validation tries to find schema for "Events::OrderPaid"
      # 3. ERROR: Can't find V2 schema! (it's attached to V2 class)
      #
      # If Versioning runs TOO EARLY (before PII Filtering):
      # 1. Versioning normalizes "Events::OrderPaidV2" → "Events::OrderPaid"
      # 2. PII Filtering uses V1 rules instead of V2 rules!
      # 3. ERROR: Wrong PII handling!
      #
      # Correct order (enforced by zone system):
      # 1. :pre_processing zone → Validation uses "Events::OrderPaidV2" schema ✅
      # 2. :security zone → PII Filtering uses "Events::OrderPaidV2" rules ✅
      # 3. :post_processing zone → Versioning normalizes to "Events::OrderPaid" ✅
      # 4. :adapters zone → Routing to buffers

      expect(described_class.middleware_zone).to eq(:post_processing)
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
      event_data = {
        event_name: "Events::OrderPaidV2",
        payload: { order_id: 123 }
      }

      result = pipeline.call(event_data)

      expect(result[:event_name]).to eq("Events::OrderPaid")
      expect(result[:payload][:v]).to eq(2)
      expect(result[:middleware2]).to be true
    end

    it "adapters receive normalized event name" do
      # Simulate adapter (final app)
      adapter_received = nil
      adapter = lambda do |event_data|
        adapter_received = event_data
        nil
      end

      versioning_middleware = described_class.new(adapter)
      event_data = {
        event_name: "Events::OrderPaidV2",
        payload: { order_id: 123, amount: 99.99 }
      }

      versioning_middleware.call(event_data)

      # Adapter sees normalized name and explicit version
      expect(adapter_received[:event_name]).to eq("Events::OrderPaid")
      expect(adapter_received[:payload][:v]).to eq(2)
    end
  end
end
