# frozen_string_literal: true

require "rails_helper"

# EventSLO Middleware Integration Tests for ADR-014, UC-004
# Tests SLO status computation, metric emission, and graceful error handling
#
# Scenarios:
# 1. Events with SLO enabled emit metrics
# 2. SLO status computation (success/failure)
# 3. Events without SLO pass through
# 4. Error handling (never fails event tracking)

RSpec.describe "EventSLO Middleware Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }

  before do
    memory_adapter.clear!
    E11y::Current.reset

    # CRITICAL: Don't reset Yabeda in Rails - it breaks metric registration
    # Yabeda.reset! destroys the :e11y group and all metrics configured by Railtie

    # Configure Yabeda adapter if needed
    if yabeda_adapter
      yabeda_adapter_instance = E11y::Adapters::Yabeda.new(auto_register: true)
      E11y.config.adapters[:yabeda] = yabeda_adapter_instance

      # Metrics will be registered automatically via auto_register
      # Don't call Yabeda.configure! - it was already called by Railtie
    end

    # Ensure EventSLO middleware is enabled in pipeline
    # Remove existing EventSLO middleware first to avoid duplicates
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::EventSlo }

    # Add EventSLO middleware BEFORE Routing (post_processing zone, but Routing writes to adapters)
    routing_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Routing }
    insert_index = routing_index || E11y.config.pipeline.middlewares.length
    E11y.config.pipeline.middlewares.insert(
      insert_index,
      E11y::Pipeline::Builder::MiddlewareEntry.new(
        middleware_class: E11y::Middleware::EventSlo,
        args: [],
        options: {}
      )
    )
    E11y.config.instance_variable_set(:@built_pipeline, nil)

    # Mock E11y::Metrics
    allow(E11y::Metrics).to receive(:increment)
  end

  after do
    memory_adapter.clear!
    E11y::Current.reset
    Yabeda.reset! if defined?(Yabeda)
    # Reset pipeline to avoid state pollution between test files
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  describe "Scenario 1: Events with SLO enabled emit metrics" do
    it "emits SLO metric for events with SLO enabled" do
      # Setup: Event with SLO enabled
      # Test: Track event
      # Expected: SLO metric emitted

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::PaymentProcessed"
        end

        def self.event_name
          "payment.processed"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from do |payload|
              payload[:status] == "completed" ? "success" : "failure"
            end
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::PaymentProcessed", slo_event_class)

      Events::PaymentProcessed.track(payment_id: "p123", status: "completed")

      # Verify SLO metric was emitted
      expect(E11y::Metrics).to have_received(:increment).with(
        :slo_event_result_total,
        hash_including(
          event_name: "payment.processed",
          slo_status: "success"
        )
      )

      # Event should still be stored (after Versioning middleware, event_name is normalized)
      all_events = memory_adapter.events
      events = all_events.select { |e| ["payment.processed", "Events::PaymentProcessed"].include?(e[:event_name]) }
      expect(events.count).to eq(1), "Event should be stored. Total events: #{all_events.count}, event_names: #{all_events.map do |e|
        e[:event_name]
      end.uniq.inspect}"
    end

    it "emits metrics with correct labels" do
      # Setup: Event with SLO and custom labels
      # Test: Track event
      # Expected: Metric emitted with correct labels

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::OrderProcessed"
        end

        def self.event_name
          "order.processed"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from { |payload| payload[:status] == "completed" ? "success" : "failure" }
            cfg.contributes_to "order_success_rate"
            cfg.group_by :payment_method
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::OrderProcessed", slo_event_class)

      Events::OrderProcessed.track(order_id: 123, status: "completed", payment_method: "card")

      # Verify metric with labels
      expect(E11y::Metrics).to have_received(:increment).with(
        :slo_event_result_total,
        hash_including(
          event_name: "order.processed",
          slo_status: "success",
          slo_name: "order_success_rate",
          group_by: "card"
        )
      )
    end
  end

  describe "Scenario 2: SLO status computation" do
    it "computes success status correctly" do
      # Setup: Event with SLO status proc returning "success"
      # Test: Track event with success payload
      # Expected: Metric emitted with slo_status="success"

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::TaskCompleted"
        end

        def self.event_name
          "task.completed"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from do |payload|
              payload[:result] == "success" ? "success" : "failure"
            end
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::TaskCompleted", slo_event_class)

      Events::TaskCompleted.track(task_id: 1, result: "success")

      expect(E11y::Metrics).to have_received(:increment).with(
        :slo_event_result_total,
        hash_including(slo_status: "success")
      )
    end

    it "computes failure status correctly" do
      # Setup: Event with SLO status proc returning "failure"
      # Test: Track event with failure payload
      # Expected: Metric emitted with slo_status="failure"

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::TaskFailed"
        end

        def self.event_name
          "task.failed"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from do |payload|
              payload[:error].present? ? "failure" : "success"
            end
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::TaskFailed", slo_event_class)

      Events::TaskFailed.track(task_id: 1, error: "Timeout")

      expect(E11y::Metrics).to have_received(:increment).with(
        :slo_event_result_total,
        hash_including(slo_status: "failure")
      )
    end

    it "skips metric emission when slo_status is nil" do
      # Setup: Event with SLO status proc returning nil
      # Test: Track event
      # Expected: No metric emitted (status not counted)

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::TaskPending"
        end

        def self.event_name
          "task.pending"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from do |_payload|
              nil # Not counted in SLO
            end
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::TaskPending", slo_event_class)

      Events::TaskPending.track(task_id: 1, status: "pending")

      # Should not emit metric (slo_status is nil)
      expect(E11y::Metrics).not_to have_received(:increment)
    end
  end

  describe "Scenario 3: Events without SLO pass through" do
    it "allows events without SLO to pass through" do
      # Setup: Event without SLO config
      # Test: Track event
      # Expected: Event passes through, no SLO metric emitted

      no_slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::HealthCheck"
        end

        def self.event_name
          "health.check"
        end

        adapters :memory

        def self.respond_to?(method)
          method != :slo_config && super
        end
      end
      stub_const("Events::HealthCheck", no_slo_event_class)

      Events::HealthCheck.track(service: "api", status: "ok")

      # Should not emit SLO metric
      expect(E11y::Metrics).not_to have_received(:increment)

      # Event should still be stored (after Versioning middleware, event_name is normalized)
      all_events = memory_adapter.events
      events = all_events.select { |e| ["health.check", "Events::HealthCheck"].include?(e[:event_name]) }
      expect(events.count).to eq(1)
    end

    it "allows events with SLO disabled to pass through" do
      # Setup: Event with SLO config but enabled: false
      # Test: Track event
      # Expected: Event passes through, no SLO metric emitted

      disabled_slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::DisabledSLOEvent"
        end

        def self.event_name
          "disabled.slo.event"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled false # SLO disabled
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::DisabledSLOEvent", disabled_slo_event_class)

      Events::DisabledSLOEvent.track(data: "test")

      # Should not emit SLO metric
      expect(E11y::Metrics).not_to have_received(:increment)

      # Event should still be stored (after Versioning middleware, event_name is normalized)
      all_events = memory_adapter.events
      events = all_events.select { |e| ["disabled.slo.event", "Events::DisabledSLOEvent"].include?(e[:event_name]) }
      expect(events.count).to eq(1)
    end
  end

  describe "Scenario 4: Error handling" do
    it "handles SLO status computation errors gracefully" do
      # Setup: Event with SLO status proc that raises error
      # Test: Track event
      # Expected: Error caught, event still tracked

      error_slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::ErrorSLOEvent"
        end

        def self.event_name
          "error.slo.event"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from do |_payload|
              raise StandardError, "SLO computation error"
            end
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::ErrorSLOEvent", error_slo_event_class)

      # Should not raise error (graceful handling)
      expect do
        Events::ErrorSLOEvent.track(data: "test")
      end.not_to raise_error

      # Event should still be stored (after Versioning middleware, event_name is normalized)
      all_events = memory_adapter.events
      events = all_events.select { |e| ["error.slo.event", "Events::ErrorSLOEvent"].include?(e[:event_name]) }
      expect(events.count).to eq(1)
    end

    it "handles metric emission errors gracefully" do
      # Setup: Event with SLO, but Metrics.increment raises error
      # Test: Track event
      # Expected: Error caught, event still tracked

      slo_event_class = Class.new(E11y::Event::Base) do
        def self.name
          "Events::MetricErrorEvent"
        end

        def self.event_name
          "metric.error.event"
        end

        adapters :memory

        def self.slo_config
          @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
            cfg.enabled true
            cfg.slo_status_from { |_payload| "success" }
          end
        end

        def self.respond_to?(method)
          method == :slo_config || super
        end
      end
      stub_const("Events::MetricErrorEvent", slo_event_class)

      # Mock Metrics.increment to raise error
      allow(E11y::Metrics).to receive(:increment).and_raise(StandardError.new("Metric error"))

      # Should not raise error (graceful handling)
      expect do
        Events::MetricErrorEvent.track(data: "test")
      end.not_to raise_error

      # Event should still be stored (after Versioning middleware, event_name is normalized)
      all_events = memory_adapter.events
      events = all_events.select { |e| ["metric.error.event", "Events::MetricErrorEvent"].include?(e[:event_name]) }
      expect(events.count).to eq(1)
    end
  end
end
