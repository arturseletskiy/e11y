# frozen_string_literal: true

require "rails_helper"

# Versioning Middleware Integration Tests for UC-020
# Tests version extraction, event name normalization, and version field injection
#
# Scenarios:
# 1. V1 events (no version field)
# 2. V2+ events (version field added)
# 3. Event name normalization (removes version suffix)
# 4. Parallel versions (V1 and V2 coexist)

RSpec.describe "Versioning Middleware Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
    E11y::Current.reset

    # Ensure Versioning middleware is enabled in pipeline
    # Remove existing Versioning middleware first to avoid duplicates
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Versioning }

    # Add Versioning middleware (should be in pre_processing zone, BEFORE Validation)
    trace_context_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::TraceContext }
    insert_index = trace_context_index ? trace_context_index + 1 : 0
    E11y.config.pipeline.middlewares.insert(
      insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Versioning,
        args: [],
        options: {}
      )
    )
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    memory_adapter.clear!
    E11y::Current.reset
    # Reset pipeline to avoid state pollution between test files
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  describe "Scenario 1: V1 events (no version field)" do
    it "does not add version field for V1 events" do
      # Setup: V1 event (no version suffix)
      # Test: Track V1 event
      # Expected: No `v:` field in event_data (V1 is implicit)

      v1_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaid", v1_event_class)

      Events::OrderPaid.track(order_id: 123, amount: 100.0)

      # Check event in memory adapter
      # Note: After Versioning middleware, event_name is normalized to "order.paid"
      all_events = memory_adapter.events
      valid_names = ["order.paid", "Events::OrderPaid"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      event_names_msg = "Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
      msg = format("Event should be stored in memory adapter. %s", event_names_msg)
      expect(events.count).to eq(1), msg

      event = events.first
      expect(event[:v]).to be_nil, "V1 events should not have `v:` field"
      expect(event[:event_name]).to eq("order.paid"), "Event name should be normalized"
    end

    it "normalizes event_name for V1 events" do
      # Setup: V1 event with class name "Events::OrderPaid"
      # Test: Track event
      # Expected: event_name normalized to "order.paid"

      v1_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaid", v1_event_class)

      Events::OrderPaid.track(order_id: 123)

      all_events = memory_adapter.events
      valid_names = ["order.paid", "Events::OrderPaid"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      expect(events.count).to eq(1)
      expect(events.first[:event_name]).to eq("order.paid")
    end
  end

  describe "Scenario 2: V2+ events (version field added)" do
    it "adds version field for V2 events" do
      # Setup: V2 event (class name ends with V2)
      # Test: Track V2 event
      # Expected: `v: 2` field added to event_data

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      Events::OrderPaidV2.track(order_id: 123, amount: 100.0, currency: "USD")

      # NOTE: After Versioning middleware, event_name is normalized to "order.paid"
      all_events = memory_adapter.events
      valid_names = ["order.paid", "Events::OrderPaidV2"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      event_names_msg = "Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
      msg = format("Event should be stored in memory adapter. %s", event_names_msg)
      expect(events.count).to eq(1), msg

      event = events.first
      expect(event[:v]).to eq(2), "V2 events should have `v: 2` field"
      expect(event[:event_name]).to eq("order.paid"), "Event name should be normalized (no version suffix)"
    end

    it "adds version field for V3 events" do
      # Setup: V3 event (class name ends with V3)
      # Test: Track V3 event
      # Expected: `v: 3` field added to event_data

      v3_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV3"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaidV3", v3_event_class)

      Events::OrderPaidV3.track(order_id: 123, amount: 100.0, currency: "USD", tax: 10.0)

      all_events = memory_adapter.events
      valid_names = ["order.paid", "Events::OrderPaidV3"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      expect(events.count).to eq(1)

      event = events.first
      expect(event[:v]).to eq(3), "V3 events should have `v: 3` field"
      expect(event[:event_name]).to eq("order.paid"), "Event name should be normalized"
    end

    it "normalizes event_name for V2 events (removes version suffix)" do
      # Setup: V2 event with class name "Events::OrderPaidV2"
      # Test: Track event
      # Expected: event_name normalized to "order.paid" (no V2 suffix)

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      Events::OrderPaidV2.track(order_id: 123)

      all_events = memory_adapter.events
      valid_names = ["order.paid", "Events::OrderPaidV2"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      expect(events.count).to eq(1)
      event = events.first

      # Event name should be normalized (no version suffix)
      expect(event[:event_name]).to eq("order.paid"), "Event name should be normalized (removes V2 suffix)"
      expect(event[:event_name]).not_to include("V2"), "Event name should not contain version suffix"
    end
  end

  describe "Scenario 3: Event name normalization" do
    it "normalizes nested namespace event names" do
      # Setup: Event with nested namespace
      # Test: Track event
      # Expected: event_name normalized correctly

      nested_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::Payment::OrderPaidV2"
        end

        def self.event_name
          "payment.order.paid"
        end

        adapters :memory
      end
      stub_const("Events::Payment::OrderPaidV2", nested_event_class)

      Events::Payment::OrderPaidV2.track(order_id: 123)

      all_events = memory_adapter.events
      events = all_events.select { |e| e[:event_name] == "payment.order.paid" || e[:event_name]&.include?("Payment::OrderPaidV2") }
      expect(events.count).to eq(1)
      event = events.first

      # Should normalize nested namespaces
      expect(event[:event_name]).to eq("payment.order.paid"), "Nested namespace should be normalized"
      expect(event[:v]).to eq(2), "Version should be extracted"
    end

    it "handles CamelCase event names correctly" do
      # Setup: Event with CamelCase name
      # Test: Track event
      # Expected: event_name converted to snake_case with dots

      camel_case_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::UserSignupV2"
        end

        def self.event_name
          "user.signup"
        end

        adapters :memory
      end
      stub_const("Events::UserSignupV2", camel_case_event_class)

      Events::UserSignupV2.track(user_id: 123)

      all_events = memory_adapter.events
      valid_names = ["user.signup", "Events::UserSignupV2"]
      events = all_events.select { |e| valid_names.include?(e[:event_name]) }
      expect(events.count).to eq(1)
      event = events.first

      expect(event[:event_name]).to eq("user.signup"), "CamelCase should be normalized to snake_case"
      expect(event[:v]).to eq(2), "Version should be extracted"
    end
  end

  describe "Scenario 4: Parallel versions" do
    it "allows V1 and V2 events to coexist" do
      # Setup: Both V1 and V2 event classes exist
      # Test: Track both V1 and V2 events
      # Expected: Both events tracked correctly with appropriate version fields

      v1_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaid", v1_event_class)

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      # Track V1 event
      Events::OrderPaid.track(order_id: 1, amount: 100.0)

      # Track V2 event
      Events::OrderPaidV2.track(order_id: 2, amount: 200.0, currency: "USD")

      # Both events should be tracked (both have normalized event_name "order.paid")
      all_events = memory_adapter.events
      events_with_order_paid = all_events.select { |e| e[:event_name] == "order.paid" }
      expect(events_with_order_paid.count).to eq(2), "Both V1 and V2 events should be tracked"

      # Find V1 event (no v: field)
      v1_event = events_with_order_paid.find { |e| e[:v].nil? }
      expect(v1_event).not_to be_nil, "V1 event should be tracked"
      expect(v1_event[:v]).to be_nil, "V1 event should not have `v:` field"
      expect(v1_event[:event_name]).to eq("order.paid")

      # Find V2 event (has v: 2)
      v2_event = events_with_order_paid.find { |e| e[:v] == 2 }
      expect(v2_event).not_to be_nil, "V2 event should be tracked"
      expect(v2_event[:v]).to eq(2), "V2 event should have `v: 2` field"
      expect(v2_event[:event_name]).to eq("order.paid")
    end

    it "normalizes event_name consistently across versions" do
      # Setup: V1 and V2 events with same base name
      # Test: Track both events
      # Expected: Both have same normalized event_name (enables version-agnostic queries)

      v1_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaid", v1_event_class)

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        def self.event_name
          "order.paid"
        end

        adapters :memory
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      Events::OrderPaid.track(order_id: 1)
      Events::OrderPaidV2.track(order_id: 2)

      all_events = memory_adapter.events
      events_with_order_paid = all_events.select { |e| e[:event_name] == "order.paid" }
      expect(events_with_order_paid.count).to eq(2), "Both V1 and V2 events should be tracked"

      v1_event = events_with_order_paid.find { |e| e[:v].nil? }
      v2_event = events_with_order_paid.find { |e| e[:v] == 2 }

      # Both should have same normalized event_name (enables version-agnostic queries)
      expect(v1_event[:event_name]).to eq("order.paid")
      expect(v2_event[:event_name]).to eq("order.paid")
      msg = "V1 and V2 events should have same normalized event_name for version-agnostic queries"
      expect(v1_event[:event_name]).to eq(v2_event[:event_name]), msg
    end
  end
end
