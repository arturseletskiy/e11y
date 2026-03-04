# frozen_string_literal: true

require "rails_helper"

# Validation Middleware Integration Tests
# Tests schema validation, validation errors, and schema-less event handling
#
# Scenarios:
# 1. Valid events pass through
# 2. Invalid events raise ValidationError
# 3. Schema-less events pass through
# 4. Versioned events use original class name for validation

RSpec.describe "Validation Middleware Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
    E11y::Current.reset

    # Ensure memory adapter is registered (it should be from application.rb, but ensure it's there)
    E11y.config.adapters[:memory] ||= memory_adapter

    # Configure routing to send events to memory adapter
    E11y.config.fallback_adapters = [:memory]
    E11y.config.routing_rules = [] # Clear any existing routing rules

    # Ensure Versioning middleware is enabled (needed for versioned event tests)
    # Remove existing Versioning middleware first to avoid duplicates
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Versioning }
    trace_context_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::TraceContext }
    versioning_insert_index = trace_context_index ? trace_context_index + 1 : 0
    E11y.config.pipeline.middlewares.insert(
      versioning_insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Versioning,
        args: [],
        options: {}
      )
    )

    # Ensure Validation middleware is enabled in pipeline
    # Remove existing Validation middleware first to avoid duplicates
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::Validation }

    # Add Validation middleware AFTER Versioning (should be in pre_processing zone)
    versioning_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Versioning }
    insert_index = if versioning_index
                     versioning_index + 1
                   else
                     (trace_context_index ? trace_context_index + 1 : 0)
                   end
    E11y.config.pipeline.middlewares.insert(
      insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::Validation,
        args: [],
        options: {}
      )
    )

    # Ensure Routing middleware is present (it should be from application.rb, but ensure it's there)
    unless E11y.config.pipeline.middlewares.any? { |m| m.middleware_class == E11y::Middleware::Routing }
      E11y.config.pipeline.use E11y::Middleware::Routing
    end

    # Force pipeline rebuild after middleware changes
    E11y.config.instance_variable_set(:@built_pipeline, nil)
    # Ensure pipeline is rebuilt by calling built_pipeline (lazy rebuild)
    E11y.config.built_pipeline
  end

  after do
    memory_adapter.clear!
    E11y::Current.reset
    # Reset pipeline to avoid state pollution between test files
    E11y.config.instance_variable_set(:@built_pipeline, nil)
    # Ensure Routing middleware is still present (it should be from application.rb)
    unless E11y.config.pipeline.middlewares.any? { |m| m.middleware_class == E11y::Middleware::Routing }
      E11y.config.pipeline.use E11y::Middleware::Routing
    end
    # Ensure Versioning and Validation middleware are still present (they should be from before block)
    unless E11y.config.pipeline.middlewares.any? { |m| m.middleware_class == E11y::Middleware::Versioning }
      trace_context_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::TraceContext }
      versioning_insert_index = trace_context_index ? trace_context_index + 1 : 0
      E11y.config.pipeline.middlewares.insert(
        versioning_insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Versioning,
          args: [],
          options: {}
        )
      )
    end
    unless E11y.config.pipeline.middlewares.any? { |m| m.middleware_class == E11y::Middleware::Validation }
      versioning_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Versioning }
      trace_context_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::TraceContext }
      insert_index = if versioning_index
                       versioning_index + 1
                     else
                       (trace_context_index ? trace_context_index + 1 : 0)
                     end
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::Validation,
          args: [],
          options: {}
        )
      )
    end
  end

  describe "Scenario 1: Valid events pass through" do
    it "allows valid events to pass through validation" do
      # Setup: Event with valid payload matching schema
      # Test: Track event
      # Expected: Event passes through, stored in adapter

      valid_event_class = Class.new(E11y::Event::Base) do
        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
        end
      end
      stub_const("Events::ValidOrder", valid_event_class)

      # Should not raise error
      expect do
        Events::ValidOrder.track(order_id: 123, amount: 100.50)
      end.not_to raise_error

      # Event should be stored (after Versioning middleware, event_name may be normalized)
      all_events = memory_adapter.events
      events = all_events.select do |e|
        e[:event_name]&.include?("ValidOrder") || e[:event_name]&.include?("valid.order") || e[:event_class] == valid_event_class
      end
      expect(events.count).to eq(1), "Event should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
      expect(events.first[:payload][:order_id]).to eq(123)
      expect(events.first[:payload][:amount]).to eq(100.50)
    end

    it "validates required fields" do
      # Setup: Event with schema requiring specific fields
      # Test: Track event with all required fields
      # Expected: Validation passes

      event_class = Class.new(E11y::Event::Base) do
        adapters :memory

        schema do
          required(:user_id).filled(:integer)
          required(:email).filled(:string)
        end
      end
      stub_const("Events::UserSignup", event_class)

      expect do
        Events::UserSignup.track(user_id: 456, email: "user@example.com")
      end.not_to raise_error

      # After Versioning middleware, event_name may be normalized
      all_events = memory_adapter.events
      events = all_events.select do |e|
        e[:event_name]&.include?("UserSignup") || e[:event_name]&.include?("user.signup") || e[:event_class] == event_class
      end
      expect(events.count).to eq(1), "Event should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end

    it "validates optional fields" do
      # Setup: Event with optional fields in schema
      # Test: Track event with optional fields
      # Expected: Validation passes

      event_class = Class.new(E11y::Event::Base) do
        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          optional(:discount).filled(:decimal)
        end
      end
      stub_const("Events::OrderWithDiscount", event_class)

      # With optional field
      expect do
        Events::OrderWithDiscount.track(order_id: 123, discount: 10.0)
      end.not_to raise_error

      # Without optional field
      expect do
        Events::OrderWithDiscount.track(order_id: 123)
      end.not_to raise_error

      # After Versioning middleware, event_name may be normalized
      all_events = memory_adapter.events
      events = all_events.select do |e|
        e[:event_name]&.include?("OrderWithDiscount") || e[:event_name]&.include?("order.with.discount") || e[:event_class] == event_class
      end
      expect(events.count).to eq(2), "Both events should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end
  end

  describe "Scenario 2: Invalid events raise ValidationError" do
    it "raises ValidationError for missing required fields" do
      # Setup: Event with required fields in schema
      # Test: Track event without required fields
      # Expected: Raises E11y::ValidationError

      event_class = Class.new(E11y::Event::Base) do
        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
        end
      end
      stub_const("Events::InvalidOrder", event_class)

      # Missing required field
      expect do
        Events::InvalidOrder.track(order_id: 123) # Missing :amount
      end.to raise_error(E11y::ValidationError)

      # Event should not be stored
      events = memory_adapter.find_events("Events::InvalidOrder")
      expect(events.count).to eq(0)
    end

    it "raises ValidationError for wrong field types" do
      # Setup: Event with type constraints in schema
      # Test: Track event with wrong types
      # Expected: Raises E11y::ValidationError

      event_class = Class.new(E11y::Event::Base) do
        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
        end
      end
      stub_const("Events::TypeMismatchOrder", event_class)

      # Wrong type for order_id
      expect do
        Events::TypeMismatchOrder.track(order_id: "not_a_number", amount: 100.0)
      end.to raise_error(E11y::ValidationError)

      # Wrong type for amount
      expect do
        Events::TypeMismatchOrder.track(order_id: 123, amount: "not_a_decimal")
      end.to raise_error(E11y::ValidationError)
    end

    it "raises ValidationError for empty required fields" do
      # Setup: Event with required fields that must be filled
      # Test: Track event with empty values
      # Expected: Raises E11y::ValidationError

      event_class = Class.new(E11y::Event::Base) do
        schema do
          required(:user_id).filled(:integer)
          required(:email).filled(:string)
        end
      end
      stub_const("Events::EmptyFieldsOrder", event_class)

      # Empty string
      expect do
        Events::EmptyFieldsOrder.track(user_id: 123, email: "")
      end.to raise_error(E11y::ValidationError)

      # Nil value
      expect do
        Events::EmptyFieldsOrder.track(user_id: 123, email: nil)
      end.to raise_error(E11y::ValidationError)
    end
  end

  describe "Scenario 3: Schema-less events pass through" do
    it "allows events without schema to pass through" do
      # Setup: Event without schema definition
      # Test: Track event
      # Expected: Event passes through (validation skipped)

      schema_less_event_class = Class.new(E11y::Event::Base) do
        adapters :memory
        # No schema defined
      end
      stub_const("Events::SchemaLessEvent", schema_less_event_class)

      # Should not raise error (validation skipped)
      expect do
        Events::SchemaLessEvent.track(any_field: "any_value", another_field: 123)
      end.not_to raise_error

      # Event should be stored (after Versioning middleware, event_name may be normalized)
      all_events = memory_adapter.events
      # Try to find by class name or normalized event_name
      events = all_events.select do |e|
        e[:event_name]&.include?("SchemaLessEvent") || e[:event_name]&.include?("schema.less.event") || e[:event_class] == schema_less_event_class
      end
      expect(events.count).to eq(1), "Event should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end

    it "allows any payload structure for schema-less events" do
      # Setup: Event without schema
      # Test: Track event with various payload structures
      # Expected: All pass through

      schema_less_event_class = Class.new(E11y::Event::Base) do
        adapters :memory
        # No schema
      end
      stub_const("Events::FlexibleEvent", schema_less_event_class)

      # Various payload structures should all pass
      expect do
        Events::FlexibleEvent.track(field1: "value1")
      end.not_to raise_error

      expect do
        Events::FlexibleEvent.track(nested: { data: "value" })
      end.not_to raise_error

      expect do
        Events::FlexibleEvent.track(array: [1, 2, 3])
      end.not_to raise_error

      # After Versioning middleware, event_name may be normalized
      all_events = memory_adapter.events
      events = all_events.select do |e|
        e[:event_name]&.include?("FlexibleEvent") || e[:event_name]&.include?("flexible.event") || e[:event_class] == schema_less_event_class
      end
      expect(events.count).to eq(3), "All 3 events should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end
  end

  describe "Scenario 4: Versioned events use original class name" do
    it "validates V2 events using V2 schema" do
      # Setup: V2 event with V2-specific schema
      # Test: Track V2 event
      # Expected: Validation uses V2 schema (original class name)

      # Clear adapter before test to ensure clean state
      memory_adapter.clear!

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
          required(:currency).filled(:string) # V2-specific required field
        end
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      # Ensure pipeline is rebuilt for this test
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Valid V2 event (has currency)
      expect do
        Events::OrderPaidV2.track(order_id: 123, amount: 100.0, currency: "USD")
      end.not_to raise_error

      # Check that valid event was stored
      all_events_after_valid = memory_adapter.events
      expect(all_events_after_valid.count).to eq(1),
                                              "Valid event should be stored immediately. Total events: #{all_events_after_valid.count}"

      # Invalid V2 event (missing currency)
      expect do
        Events::OrderPaidV2.track(order_id: 123, amount: 100.0) # Missing currency
      end.to raise_error(E11y::ValidationError)

      # Only valid event should be stored (invalid event should not be stored)
      all_events = memory_adapter.events
      events = all_events.select do |e|
        e[:event_name] == "order.paid" || e[:event_name]&.include?("OrderPaidV2") || e[:event_class] == v2_event_class
      end
      event_names = all_events.map { |e| e[:event_name] }.uniq.inspect
      event_classes = all_events.map { |e| e[:event_class]&.name }.uniq.inspect
      msg = "Only valid V2 event should be stored. Total: #{all_events.count}, event_names: #{event_names}, event_classes: #{event_classes}"
      expect(events.count).to eq(1), msg
    end

    it "validates V1 and V2 events independently" do
      # Setup: V1 and V2 events with different schemas
      # Test: Track both events
      # Expected: Each validated against its own schema

      # Clear adapter before test to ensure clean state
      memory_adapter.clear!

      v1_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaid"
        end

        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
          # No currency field (V1)
        end
      end
      stub_const("Events::OrderPaid", v1_event_class)

      v2_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderPaidV2"
        end

        adapters :memory

        schema do
          required(:order_id).filled(:integer)
          required(:amount).filled(:decimal)
          required(:currency).filled(:string) # V2 requires currency
        end
      end
      stub_const("Events::OrderPaidV2", v2_event_class)

      # Ensure pipeline is rebuilt for this test
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # V1 event (no currency) - should pass
      expect do
        Events::OrderPaid.track(order_id: 1, amount: 100.0)
      end.not_to raise_error

      # V2 event (with currency) - should pass
      expect do
        Events::OrderPaidV2.track(order_id: 2, amount: 200.0, currency: "USD")
      end.not_to raise_error

      # V2 event (without currency) - should fail
      expect do
        Events::OrderPaidV2.track(order_id: 3, amount: 300.0) # Missing currency
      end.to raise_error(E11y::ValidationError)

      # Only valid events should be stored (after Versioning middleware, event_name is normalized to "order.paid")
      all_events = memory_adapter.events
      # Both V1 and V2 events have normalized event_name "order.paid" after Versioning middleware
      order_paid_classes = [v1_event_class, v2_event_class]
      events_with_order_paid = all_events.select do |e|
        e[:event_name] == "order.paid" || e[:event_name]&.include?("OrderPaid") || order_paid_classes.include?(e[:event_class])
      end
      event_names = all_events.map { |e| e[:event_name] }.uniq.inspect
      event_classes = all_events.map { |e| e[:event_class]&.name }.uniq.inspect
      msg = "Both V1 and V2 valid events should be stored. Total: #{all_events.count}, event_names: #{event_names}, event_classes: #{event_classes}"
      expect(events_with_order_paid.count).to eq(2), msg
    end
  end
end
