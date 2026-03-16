# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/self_monitoring_emit"
require "e11y/slo/config_loader"

RSpec.describe E11y::Middleware::SelfMonitoringEmit do
  let(:app) { instance_double(Proc, call: nil) }
  subject(:middleware) { described_class.new(app) }

  describe "#call" do
    context "when event_data is nil" do
      it "passes through without emitting" do
        expect(E11y::Metrics).not_to receive(:increment)
        middleware.call(nil)
        expect(app).to have_received(:call).with(nil)
      end
    end

    context "when self_monitoring is disabled" do
      before { allow(E11y::SLO::ConfigLoader).to receive(:self_monitoring_enabled?).and_return(false) }

      it "does not emit metric" do
        expect(E11y::Metrics).not_to receive(:increment)
        middleware.call(event_name: "order.created", payload: {})
        expect(app).to have_received(:call)
      end
    end

    context "when self_monitoring is enabled" do
      before { allow(E11y::SLO::ConfigLoader).to receive(:self_monitoring_enabled?).and_return(true) }

      it "increments e11y_events_tracked_total with result and event_name" do
        expect(E11y::Metrics).to receive(:increment).with(
          :e11y_events_tracked_total,
          result: "success",
          event_name: "order.created"
        )
        middleware.call(event_name: "order.created", payload: {})
        expect(app).to have_received(:call)
      end

      it "uses 'unknown' when event_name is blank" do
        expect(E11y::Metrics).to receive(:increment).with(
          :e11y_events_tracked_total,
          result: "success",
          event_name: "unknown"
        )
        middleware.call(event_name: "", payload: {})
        expect(app).to have_received(:call)
      end

      it "passes event_data to next middleware" do
        event_data = { event_name: "payment.processed", payload: { id: 1 } }
        middleware.call(event_data)
        expect(app).to have_received(:call).with(event_data)
      end
    end
  end
end
