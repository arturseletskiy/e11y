# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Middleware::TrackLatency do
  let(:next_app) { instance_double(Proc, call: :ok) }
  let(:middleware) { described_class.new(next_app) }

  before do
    E11y::Metrics.reset_backend!
  end

  it "measures pipeline latency and records success" do
    allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_latency)

    event_data = {
      event_name: "Events::OrderPaid",
      severity: :info
    }

    result = middleware.call(event_data)

    expect(result).to eq(:ok)
    expect(E11y::SelfMonitoring::PerformanceMonitor).to have_received(:track_latency).with(
      a_value >= 0,
      event_class: "Events::OrderPaid",
      severity: "info",
      result: :success
    )
  end

  it "records dropped when next middleware returns nil" do
    allow(next_app).to receive(:call).and_return(nil)
    allow(E11y::SelfMonitoring::PerformanceMonitor).to receive(:track_latency)

    event_data = { event_name: "Events::UserAction", severity: :debug }

    result = middleware.call(event_data)

    expect(result).to be_nil
    expect(E11y::SelfMonitoring::PerformanceMonitor).to have_received(:track_latency).with(
      a_value >= 0,
      event_class: "Events::UserAction",
      severity: "debug",
      result: :dropped
    )
  end

  it "declares pre_processing zone" do
    expect(described_class.middleware_zone).to eq(:pre_processing)
  end
end
