# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/tracker"

RSpec.describe E11y::SLO::Tracker do
  before do
    E11y::Metrics.reset_backend!
    E11y.reset!
  end

  after do
    E11y.reset!
  end

  describe ".track_http_request" do
    context "when SLO tracking is enabled" do
      before do
        E11y.configure do |config|
          config.slo_tracking_enabled = true
        end
      end

      it "tracks HTTP request count with normalized status" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_http_requests_total,
          { controller: "OrdersController", action: "create", status: "2xx" }
        )

        described_class.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 42.5
        )
      end

      it "tracks HTTP request duration histogram" do
        expect(E11y::Metrics).to receive(:increment) # request count
        expect(E11y::Metrics).to receive(:histogram).with(
          :slo_http_request_duration_seconds,
          0.0425, # 42.5ms -> 0.0425s
          { controller: "OrdersController", action: "create" },
          buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
        )

        described_class.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 42.5
        )
      end

      it "normalizes 4xx status" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_http_requests_total,
          { controller: "OrdersController", action: "show", status: "4xx" }
        )

        allow(E11y::Metrics).to receive(:histogram)

        described_class.track_http_request(
          controller: "OrdersController",
          action: "show",
          status: 404,
          duration_ms: 10
        )
      end

      it "normalizes 5xx status" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_http_requests_total,
          { controller: "OrdersController", action: "create", status: "5xx" }
        )

        allow(E11y::Metrics).to receive(:histogram)

        described_class.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 500,
          duration_ms: 100
        )
      end
    end

    context "when SLO tracking is disabled" do
      before do
        E11y.configure do |config|
          config.slo_tracking_enabled = false
        end
      end

      it "does not track any metrics" do
        expect(E11y::Metrics).not_to receive(:increment)
        expect(E11y::Metrics).not_to receive(:histogram)

        described_class.track_http_request(
          controller: "OrdersController",
          action: "create",
          status: 200,
          duration_ms: 42.5
        )
      end
    end
  end

  describe ".track_background_job" do
    context "when SLO tracking is enabled" do
      before do
        E11y.configure do |config|
          config.slo_tracking_enabled = true
        end
      end

      it "tracks successful job count" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_background_jobs_total,
          { job_class: "ProcessOrderJob", status: "success" }
        )

        expect(E11y::Metrics).to receive(:histogram) # duration

        described_class.track_background_job(
          job_class: "ProcessOrderJob",
          status: :success,
          duration_ms: 1500
        )
      end

      it "tracks job duration for successful jobs" do
        allow(E11y::Metrics).to receive(:increment)

        expect(E11y::Metrics).to receive(:histogram).with(
          :slo_background_job_duration_seconds,
          1.5, # 1500ms -> 1.5s
          { job_class: "ProcessOrderJob" },
          buckets: [0.1, 0.5, 1, 5, 10, 30, 60, 300, 600]
        )

        described_class.track_background_job(
          job_class: "ProcessOrderJob",
          status: :success,
          duration_ms: 1500
        )
      end

      it "tracks failed job count" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_background_jobs_total,
          { job_class: "ProcessOrderJob", status: "failed" }
        )

        expect(E11y::Metrics).not_to receive(:histogram) # no duration for failed jobs

        described_class.track_background_job(
          job_class: "ProcessOrderJob",
          status: :failed,
          duration_ms: 500
        )
      end

      it "includes queue in labels when provided" do
        expect(E11y::Metrics).to receive(:increment).with(
          :slo_background_jobs_total,
          { job_class: "ProcessOrderJob", status: "success", queue: "critical" }
        )

        allow(E11y::Metrics).to receive(:histogram)

        described_class.track_background_job(
          job_class: "ProcessOrderJob",
          status: :success,
          duration_ms: 1000,
          queue: "critical"
        )
      end
    end

    context "when SLO tracking is disabled" do
      before do
        E11y.configure do |config|
          config.slo_tracking_enabled = false
        end
      end

      it "does not track any metrics" do
        expect(E11y::Metrics).not_to receive(:increment)
        expect(E11y::Metrics).not_to receive(:histogram)

        described_class.track_background_job(
          job_class: "ProcessOrderJob",
          status: :success,
          duration_ms: 1500
        )
      end
    end
  end

  describe ".enabled?" do
    it "returns true when slo_tracking is enabled" do
      E11y.configure do |config|
        config.slo_tracking_enabled = true
      end

      expect(described_class.enabled?).to be true
    end

    it "returns false when slo_tracking is disabled" do
      E11y.configure do |config|
        config.slo_tracking_enabled = false
      end

      expect(described_class.enabled?).to be false
    end

    it "returns true when slo_tracking is not configured (default enabled)" do
      # Don't configure slo_tracking at all — default is enabled
      expect(described_class.enabled?).to be true
    end
  end

  describe ".normalize_status" do
    it "normalizes 2xx to 2xx" do
      expect(described_class.send(:normalize_status, 200)).to eq("2xx")
      expect(described_class.send(:normalize_status, 204)).to eq("2xx")
    end

    it "normalizes 3xx to 3xx" do
      expect(described_class.send(:normalize_status, 301)).to eq("3xx")
      expect(described_class.send(:normalize_status, 302)).to eq("3xx")
    end

    it "normalizes 4xx to 4xx" do
      expect(described_class.send(:normalize_status, 400)).to eq("4xx")
      expect(described_class.send(:normalize_status, 404)).to eq("4xx")
    end

    it "normalizes 5xx to 5xx" do
      expect(described_class.send(:normalize_status, 500)).to eq("5xx")
      expect(described_class.send(:normalize_status, 503)).to eq("5xx")
    end

    it "returns unknown for invalid statuses" do
      expect(described_class.send(:normalize_status, 99)).to eq("unknown")
      expect(described_class.send(:normalize_status, 600)).to eq("unknown")
    end
  end

  context "when testing UC-004 compliance" do
    it "supports zero-config SLO tracking" do
      E11y.configure do |config|
        config.slo_tracking_enabled = true
      end

      # HTTP requests tracked
      allow(E11y::Metrics).to receive(:increment)
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_http_request(
        controller: "OrdersController",
        action: "create",
        status: 200,
        duration_ms: 50
      )

      # Background jobs tracked
      described_class.track_background_job(
        job_class: "ProcessOrderJob",
        status: :success,
        duration_ms: 1000
      )

      # Metrics should have been called
      expect(E11y::Metrics).to have_received(:increment).at_least(:twice)
      expect(E11y::Metrics).to have_received(:histogram).at_least(:twice)
    end
  end

  context "when testing ADR-003 compliance" do
    it "tracks application-wide SLO metrics" do
      E11y.configure do |config|
        config.slo_tracking_enabled = true
      end

      expect(E11y::Metrics).to receive(:increment).with(
        :slo_http_requests_total,
        hash_including(controller: "OrdersController")
      )

      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_http_request(
        controller: "OrdersController",
        action: "create",
        status: 200,
        duration_ms: 42
      )
    end
  end
end
