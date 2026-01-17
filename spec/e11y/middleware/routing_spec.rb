# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/routing"

RSpec.describe E11y::Middleware::Routing do
  let(:final_app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(final_app) }

  describe ".middleware_zone" do
    it "declares adapters zone (FINAL middleware)" do
      expect(described_class.middleware_zone).to eq(:adapters)
    end
  end

  describe "#call" do
    context "with standard event (info severity)" do
      it "routes to main buffer" do
        event_data = {
          event_name: "Events::OrderPaid",
          severity: :info,
          adapters: %i[logs errors_tracker],
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:routing][:buffer_type]).to eq(:main)
      end

      it "includes adapter list in routing metadata" do
        event_data = {
          event_name: "Events::OrderPaid",
          severity: :info,
          adapters: %i[logs errors_tracker],
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:routing][:adapters]).to eq(%i[logs errors_tracker])
      end

      it "includes routed_at timestamp" do
        event_data = {
          event_name: "Events::OrderPaid",
          severity: :info,
          adapters: [:logs],
          payload: { order_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:routing][:routed_at]).to be_a(Time)
        expect(result[:routing][:routed_at]).to be_within(1).of(Time.now.utc)
      end

      it "calls the next middleware in the chain" do
        event_data = {
          event_name: "Events::OrderPaid",
          severity: :info,
          adapters: [:logs],
          payload: { order_id: 123 }
        }

        allow(final_app).to receive(:call).and_call_original

        middleware.call(event_data)

        expect(final_app).to have_received(:call).with(event_data)
      end
    end

    context "with debug event" do
      it "routes to request_scoped buffer" do
        event_data = {
          event_name: "Events::DebugInfo",
          severity: :debug,
          adapters: [:logs],
          payload: { debug_data: "..." }
        }

        result = middleware.call(event_data)

        expect(result[:routing][:buffer_type]).to eq(:request_scoped)
      end
    end

    context "with audit event" do
      it "routes to audit buffer" do
        event_data = {
          event_name: "Events::PermissionChanged",
          severity: :warn,
          audit_event: true,
          adapters: [:audit_encrypted],
          payload: { user_id: 123 }
        }

        result = middleware.call(event_data)

        expect(result[:routing][:buffer_type]).to eq(:audit)
      end

      it "prioritizes audit flag over severity" do
        # Even if severity is :info, audit flag takes precedence
        event_data = {
          event_name: "Events::AuditEvent",
          severity: :info,
          audit_event: true,
          adapters: [:audit_encrypted],
          payload: {}
        }

        result = middleware.call(event_data)

        expect(result[:routing][:buffer_type]).to eq(:audit)
      end
    end

    context "with missing adapters or severity" do
      it "skips routing if adapters missing" do
        event_data = {
          event_name: "Events::Test",
          severity: :info,
          payload: {}
        }

        allow(middleware).to receive(:increment_metric)

        result = middleware.call(event_data)

        expect(result[:routing]).to be_nil
        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.routing.skipped")
      end

      it "skips routing if severity missing" do
        event_data = {
          event_name: "Events::Test",
          adapters: [:logs],
          payload: {}
        }

        allow(middleware).to receive(:increment_metric)

        result = middleware.call(event_data)

        expect(result[:routing]).to be_nil
        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.routing.skipped")
      end
    end

    context "with metrics" do
      it "increments routed metric with buffer type" do
        event_data = {
          event_name: "Events::OrderPaid",
          severity: :info,
          adapters: %i[logs errors_tracker],
          payload: {}
        }

        allow(middleware).to receive(:increment_metric)

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.routing.routed",
                buffer: :main,
                severity: :info,
                adapters_count: 2)
      end

      it "increments metric with correct adapters count" do
        event_data = {
          event_name: "Events::Test",
          severity: :debug,
          adapters: [:logs],
          payload: {}
        }

        allow(middleware).to receive(:increment_metric)

        middleware.call(event_data)

        expect(middleware).to have_received(:increment_metric)
          .with("e11y.middleware.routing.routed",
                buffer: :request_scoped,
                severity: :debug,
                adapters_count: 1)
      end
    end
  end

  describe "routing rules" do
    it "routes audit events to audit buffer" do
      event_data = {
        severity: :warn,
        audit_event: true,
        adapters: [:audit_encrypted],
        payload: {}
      }

      result = middleware.call(event_data)

      expect(result[:routing][:buffer_type]).to eq(:audit)
    end

    it "routes debug events to request_scoped buffer" do
      event_data = {
        severity: :debug,
        adapters: [:logs],
        payload: {}
      }

      result = middleware.call(event_data)

      expect(result[:routing][:buffer_type]).to eq(:request_scoped)
    end

    it "routes other severities to main buffer" do
      %i[info warn error fatal success].each do |severity|
        event_data = {
          severity: severity,
          adapters: [:logs],
          payload: {}
        }

        result = middleware.call(event_data)

        expect(result[:routing][:buffer_type]).to eq(:main)
      end
    end
  end

  describe "ADR-015 compliance" do
    it "runs in adapters zone (FINAL middleware)" do
      expect(described_class.middleware_zone).to eq(:adapters)
    end

    it "runs AFTER all processing (receives normalized event)" do
      # Event should already be normalized by Versioning middleware
      event_data = {
        event_name: "Events::OrderPaid", # Normalized (no V2)
        payload: { v: 2 }, # Version explicit
        severity: :info,
        adapters: [:logs]
      }

      result = middleware.call(event_data)

      # Routing works with normalized event
      expect(result[:routing][:buffer_type]).to eq(:main)
      expect(result[:event_name]).to eq("Events::OrderPaid") # Still normalized
    end
  end

  describe "UC-001 compliance (Request-Scoped Debug Buffering)" do
    it "routes debug events to request_scoped buffer" do
      debug_event = {
        event_name: "Events::DebugInfo",
        severity: :debug,
        adapters: [:logs],
        payload: { request_id: "abc123" }
      }

      result = middleware.call(debug_event)

      expect(result[:routing][:buffer_type]).to eq(:request_scoped)
    end

    it "routes non-debug events to main buffer (immediate sending)" do
      error_event = {
        event_name: "Events::OrderFailed",
        severity: :error,
        adapters: %i[logs errors_tracker],
        payload: { order_id: 123 }
      }

      result = middleware.call(error_event)

      expect(result[:routing][:buffer_type]).to eq(:main)
    end
  end

  describe "integration" do
    it "works with full pipeline execution" do
      # Simulate complete pipeline
      trace_context_middleware = Class.new(E11y::Middleware::Base) do
        def call(event_data)
          event_data[:trace_id] = "abc123"
          @app.call(event_data)
        end
      end

      pipeline = trace_context_middleware.new(middleware)
      event_data = {
        event_name: "Events::OrderPaid",
        severity: :info,
        adapters: [:logs],
        payload: { order_id: 123 }
      }

      result = pipeline.call(event_data)

      expect(result[:trace_id]).to eq("abc123") # From upstream middleware
      expect(result[:routing][:buffer_type]).to eq(:main) # From Routing
    end

    it "passes event_data to Collector (next app in Phase 2)" do
      # In Phase 2, final_app will be the Collector
      collector_received = nil
      collector = lambda do |event_data|
        collector_received = event_data
        nil
      end

      routing_middleware = described_class.new(collector)
      event_data = {
        event_name: "Events::OrderPaid",
        severity: :info,
        adapters: %i[logs errors_tracker],
        payload: { order_id: 123 }
      }

      routing_middleware.call(event_data)

      # Collector receives complete event with routing metadata
      expect(collector_received[:event_name]).to eq("Events::OrderPaid")
      expect(collector_received[:routing][:buffer_type]).to eq(:main)
      expect(collector_received[:routing][:adapters]).to eq(%i[logs errors_tracker])
    end
  end
end
