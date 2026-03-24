# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Middleware::Versioning do
  let(:next_middleware) { ->(event) { event } }
  let(:middleware) { described_class.new(next_middleware) }

  def stub_event_class(name)
    c = Class.new
    c.define_singleton_method(:name) { name }
    c
  end

  def stub_event_class_with_custom_name(class_name, event_name)
    c = stub_event_class(class_name)
    c.define_singleton_method(:event_name) { event_name }
    c
  end

  describe "#call" do
    context "when testing V1 events (no version suffix)" do
      let(:event_class) { stub_event_class("Events::OrderPaid") }
      let(:event_data) { { event_class: event_class, payload: { order_id: "123" } } }

      it "does not add v: field for V1 events" do
        result = middleware.call(event_data)
        expect(result[:v]).to be_nil
      end

      it "normalizes event_name (removes Events:: namespace)" do
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("order.paid")
      end
    end

    context "when testing V2 events (with V2 suffix)" do
      let(:event_class) { stub_event_class("Events::OrderPaidV2") }
      let(:event_data) { { event_class: event_class, payload: { order_id: "123", currency: "USD" } } }

      it "adds v: 2 field" do
        result = middleware.call(event_data)
        expect(result[:v]).to eq(2)
      end

      it "normalizes event_name (removes version suffix)" do
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("order.paid")
      end

      it "preserves original payload" do
        result = middleware.call(event_data)
        expect(result[:payload]).to eq({ order_id: "123", currency: "USD" })
      end
    end

    context "when testing V3+ events (with V3, V4, etc. suffix)" do
      it "extracts V3 correctly" do
        event_data = { event_class: stub_event_class("Events::OrderPaidV3") }
        result = middleware.call(event_data)
        expect(result[:v]).to eq(3)
        expect(result[:event_name]).to eq("order.paid")
      end

      it "extracts V10 correctly (multi-digit version)" do
        event_data = { event_class: stub_event_class("Events::OrderPaidV10") }
        result = middleware.call(event_data)
        expect(result[:v]).to eq(10)
        expect(result[:event_name]).to eq("order.paid")
      end
    end

    context "when testing nested namespace events" do
      it "normalizes nested namespaces" do
        event_data = { event_class: stub_event_class("Events::Payments::OrderPaid") }
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("payments.order.paid")
      end

      it "normalizes nested namespaces with version" do
        event_data = { event_class: stub_event_class("Events::Payments::OrderPaidV2") }
        result = middleware.call(event_data)
        expect(result[:v]).to eq(2)
        expect(result[:event_name]).to eq("payments.order.paid")
      end
    end

    context "when testing edge cases" do
      it "handles event_class without Events:: namespace" do
        event_data = { event_class: stub_event_class("OrderPaid") }
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("order.paid")
      end

      it "handles event_class with V in middle (not version)" do
        event_data = { event_class: stub_event_class("Events::VeryImportantEvent") }
        result = middleware.call(event_data)
        expect(result[:v]).to be_nil
        expect(result[:event_name]).to eq("very.important.event")
      end

      it "uses custom event_name when event_class defines it" do
        event_data = { event_class: stub_event_class_with_custom_name("Events::OrderPaidV2", "custom.order.paid") }
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("custom.order.paid")
      end

      it "falls back to payload event_name when event_class is anonymous (Rails ASN-style)" do
        anon = Class.new
        event_data = {
          event_class: anon,
          payload: { event_name: "sql.active_record" }
        }
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("sql.active_record")
      end

      it "reads payload event_name when the nested key is a string" do
        anon = Class.new
        event_data = {
          event_class: anon,
          payload: { "event_name" => "render.template" }
        }
        result = middleware.call(event_data)
        expect(result[:event_name]).to eq("render.template")
      end
    end
  end

  describe "ADR-012 compliance" do
    describe "§2: Parallel Versions" do
      it "allows V1 and V2 to coexist with same normalized name" do
        v1_event = { event_class: stub_event_class("Events::OrderPaid") }
        v2_event = { event_class: stub_event_class("Events::OrderPaidV2") }

        v1_result = middleware.call(v1_event)
        v2_result = middleware.call(v2_event)

        # Same normalized name for both versions
        expect(v1_result[:event_name]).to eq("order.paid")
        expect(v2_result[:event_name]).to eq("order.paid")

        # But different version field
        expect(v1_result[:v]).to be_nil # V1 implicit
        expect(v2_result[:v]).to eq(2) # V2 explicit
      end
    end

    describe "§3: Naming Convention" do
      it "extracts version from class name suffix" do
        {
          "Events::OrderPaid" => 1,
          "Events::OrderPaidV2" => 2,
          "Events::OrderPaidV3" => 3,
          "Events::OrderPaidV99" => 99
        }.each do |class_name, expected_version|
          event = { event_class: stub_event_class(class_name) }
          result = middleware.call(event)
          actual_version = result[:v] || 1 # V1 is implicit (no field)
          expect(actual_version).to eq(expected_version), "Expected version #{expected_version} for #{class_name}"
        end
      end

      it "normalizes event_name to snake_case" do
        {
          "Events::OrderPaid" => "order.paid",
          "Events::UserSignedUp" => "user.signed.up",
          "Events::PaymentFailed" => "payment.failed",
          "Events::APICallCompleted" => "api.call.completed"
        }.each do |class_name, expected_name|
          event = { event_class: stub_event_class(class_name) }
          result = middleware.call(event)
          expect(result[:event_name]).to eq(expected_name), "Expected #{expected_name} for #{class_name}"
        end
      end
    end

    describe "§4: Version in Payload" do
      it "only adds v: field if version > 1" do
        # V1: No field (implicit)
        v1 = middleware.call({ event_class: stub_event_class("Events::OrderPaid") })
        expect(v1).not_to have_key(:v)

        # V2+: Field present
        v2 = middleware.call({ event_class: stub_event_class("Events::OrderPaidV2") })
        expect(v2).to have_key(:v)
        expect(v2[:v]).to eq(2)
      end

      it "reduces noise for V1 events (90% of events)" do
        # Most events are V1, so avoid adding unnecessary field
        v1_events = [
          "Events::OrderPaid",
          "Events::UserSignedUp",
          "Events::PaymentFailed"
        ]

        v1_events.each do |class_name|
          result = middleware.call({ event_class: stub_event_class(class_name) })
          expect(result[:v]).to be_nil, "Expected no v: field for #{class_name}"
        end
      end
    end
  end

  describe "UC-020 compliance (Event Versioning)" do
    it "supports gradual rollout (V1 and V2 parallel)" do
      # Old code: still tracking V1
      v1_event = { event_class: stub_event_class("Events::OrderPaid"), payload: { order_id: "123", amount: 99.99 } }
      v1_result = middleware.call(v1_event)

      # New code: tracking V2 with new field
      v2_event = { event_class: stub_event_class("Events::OrderPaidV2"), payload: { order_id: "123", amount: 99.99, currency: "USD" } }
      v2_result = middleware.call(v2_event)

      # Both events have same normalized name (consistent queries)
      expect(v1_result[:event_name]).to eq("order.paid")
      expect(v2_result[:event_name]).to eq("order.paid")

      # But different version metadata
      expect(v1_result[:v]).to be_nil
      expect(v2_result[:v]).to eq(2)

      # Query: `WHERE event_name = 'order.paid'` matches BOTH versions
      # Query: `WHERE event_name = 'order.paid' AND v = 2` matches ONLY V2
    end

    it "supports schema evolution without breaking old code" do
      # Scenario: Add required field (currency) → create V2
      # Old code continues to work with V1 (no changes needed)

      v1_event = { event_class: stub_event_class("Events::OrderPaid"), payload: { order_id: "123", amount: 99.99 } }
      v1_result = middleware.call(v1_event)

      # Old code still works (no migration needed)
      expect(v1_result[:event_name]).to eq("order.paid")
      expect(v1_result[:v]).to be_nil
    end
  end

  describe "Real-world scenarios" do
    it "handles typical event evolution: V1 → V2 → V3" do
      # V1: Original event
      v1 = middleware.call({ event_class: stub_event_class("Events::OrderPaid"),
                             payload: { order_id: "123", amount: 99.99 } })
      expect(v1[:event_name]).to eq("order.paid")
      expect(v1[:v]).to be_nil

      # V2: Add currency field
      v2 = middleware.call({
                             event_class: stub_event_class("Events::OrderPaidV2"),
                             payload: { order_id: "123", amount: 99.99, currency: "USD" }
                           })
      expect(v2[:event_name]).to eq("order.paid")
      expect(v2[:v]).to eq(2)

      # V3: Rename amount → amount_cents
      v3 = middleware.call({
                             event_class: stub_event_class("Events::OrderPaidV3"),
                             payload: { order_id: "123", amount_cents: 9999, currency: "USD" }
                           })
      expect(v3[:event_name]).to eq("order.paid")
      expect(v3[:v]).to eq(3)

      # All three versions coexist peacefully
      # Query: WHERE event_name = 'order.paid' matches all
      # Query: WHERE event_name = 'order.paid' AND v = 2 matches only V2
    end

    it "documents that versioning is opt-in (must enable middleware)" do
      # Without enabling versioning middleware, version field won't be added
      # This test documents the opt-in nature of versioning

      # Versioning middleware is ENABLED in this test (via middleware instance)
      result = middleware.call({ event_class: stub_event_class("Events::OrderPaidV2") })
      expect(result[:v]).to eq(2)

      # In production, user must explicitly enable:
      # E11y.configure { |c| c.pipeline.use E11y::Middleware::Versioning }
    end
  end
end
