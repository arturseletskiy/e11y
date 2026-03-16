# frozen_string_literal: true

require "spec_helper"
require "rack/mock"
require "e11y/slo/tracker"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
# Integration test for SLO tracking, grouped by functionality not class structure.
RSpec.describe E11y::Middleware::Request, "SLO Integration" do
  let(:app) { ->(_env) { [200, { "Content-Type" => "text/plain" }, ["OK"]] } }
  let(:middleware) { described_class.new(app) }
  let(:env) do
    Rack::MockRequest.env_for("http://example.com/orders",
                              "REQUEST_METHOD" => "GET",
                              "action_controller.instance" => controller_double)
  end
  let(:controller_double) do
    double("Controller", controller_name: "orders", action_name: "index")
  end

  before do
    E11y.reset!
    E11y::Metrics.reset_backend!
  end

  after do
    E11y.reset!
  end

  context "when SLO tracking is enabled" do
    before do
      E11y.configure do |config|
        config.slo_tracking_enabled = true
      end
    end

    it "tracks HTTP request SLO metrics" do
      expect(E11y::SLO::Tracker).to receive(:track_http_request) do |args|
        expect(args[:controller]).to eq("orders")
        expect(args[:action]).to eq("index")
        expect(args[:status]).to eq(200)
        expect(args[:duration_ms]).to be >= 0 # Can be 0 for fast requests
        expect(args[:duration_ms]).to be < 1000 # Less than 1 second
      end

      middleware.call(env)
    end

    it "tracks duration from request start to finish" do
      # Slow app (100ms)
      slow_app = lambda do |_env|
        sleep 0.1
        [200, {}, ["OK"]]
      end
      slow_middleware = described_class.new(slow_app)

      expect(E11y::SLO::Tracker).to receive(:track_http_request) do |args|
        expect(args[:duration_ms]).to be > 90 # At least 90ms
      end

      slow_middleware.call(env)
    end

    it "tracks different HTTP statuses" do
      error_app = ->(_env) { [500, {}, ["Error"]] }
      error_middleware = described_class.new(error_app)

      expect(E11y::SLO::Tracker).to receive(:track_http_request).with(
        hash_including(status: 500)
      )

      error_middleware.call(env)
    end

    it "handles missing controller gracefully" do
      env_without_controller = Rack::MockRequest.env_for("http://example.com/")

      expect(E11y::SLO::Tracker).to receive(:track_http_request).with(
        hash_including(controller: "unknown", action: "unknown")
      )

      described_class.new(app).call(env_without_controller)
    end

    it "doesn't fail if SLO tracking fails" do
      allow(E11y::SLO::Tracker).to receive(:track_http_request).and_raise(StandardError, "SLO error")

      expect do
        status, = middleware.call(env)
        expect(status).to eq(200)
      end.not_to raise_error
    end
  end

  context "when SLO tracking is disabled" do
    before do
      E11y.configure do |config|
        config.slo_tracking_enabled = false
      end
    end

    it "does not track any SLO metrics" do
      expect(E11y::SLO::Tracker).not_to receive(:track_http_request)

      middleware.call(env)
    end
  end

  context "when testing UC-004 compliance" do
    before do
      E11y.configure do |config|
        config.slo_tracking_enabled = true
      end
    end

    it "provides zero-config SLO tracking for HTTP requests" do
      # Just enable config and it works - no additional setup needed
      expect(E11y::SLO::Tracker).to receive(:track_http_request)

      middleware.call(env)
    end

    it "tracks request duration for latency SLO" do
      expect(E11y::SLO::Tracker).to receive(:track_http_request).with(
        hash_including(:duration_ms)
      )

      middleware.call(env)
    end

    it "tracks request status for availability SLO" do
      expect(E11y::SLO::Tracker).to receive(:track_http_request).with(
        hash_including(:status)
      )

      middleware.call(env)
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
