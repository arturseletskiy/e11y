# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/tracker"

# rubocop:disable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
# Integration test for SLO tracking, grouped by functionality not class structure.
RSpec.describe E11y::Instruments::Sidekiq::ServerMiddleware, "SLO Integration" do
  let(:middleware) { described_class.new }
  let(:worker) { double("Worker") }
  let(:job) { { "class" => "TestJob", "jid" => "12345", "queue" => "default" } }
  let(:queue) { "default" }

  before do
    E11y.reset!
    E11y::Metrics.reset_backend!
    allow(E11y::Buffers::EphemeralBuffer).to receive(:initialize!)
    allow(E11y::Buffers::EphemeralBuffer).to receive(:flush_on_error)
  end

  after do
    E11y.reset!
  end

  context "when SLO tracking is enabled" do
    before do
      E11y.configure do |config|
        config.slo_tracking.enabled = true
      end
    end

    it "tracks successful job SLO metrics" do
      expect(E11y::SLO::Tracker).to receive(:track_background_job) do |args|
        expect(args[:job_class]).to eq("TestJob")
        expect(args[:status]).to eq(:success)
        expect(args[:duration_ms]).to be >= 0 # Can be 0 for fast jobs
        expect(args[:queue]).to eq("default")
      end

      middleware.call(worker, job, queue) { true }
    end

    it "tracks failed job SLO metrics" do
      expect(E11y::SLO::Tracker).to receive(:track_background_job) do |args|
        expect(args[:job_class]).to eq("TestJob")
        expect(args[:status]).to eq(:failed)
        expect(args[:duration_ms]).to be > 0
      end

      expect do
        middleware.call(worker, job, queue) { raise StandardError, "Job failed" }
      end.to raise_error(StandardError, "Job failed")
    end

    it "tracks job duration from start to finish" do
      slow_job = proc { sleep 0.05 } # 50ms job

      expect(E11y::SLO::Tracker).to receive(:track_background_job) do |args|
        expect(args[:duration_ms]).to be > 45 # At least 45ms
      end

      middleware.call(worker, job, queue, &slow_job)
    end

    it "includes queue name in metrics" do
      critical_queue_job = job.merge("queue" => "critical")

      expect(E11y::SLO::Tracker).to receive(:track_background_job).with(
        hash_including(queue: "critical")
      )

      middleware.call(worker, critical_queue_job, "critical") { true }
    end

    it "doesn't fail if SLO tracking fails" do
      allow(E11y::SLO::Tracker).to receive(:track_background_job).and_raise(StandardError, "SLO error")

      expect do
        middleware.call(worker, job, queue) { true }
      end.not_to raise_error
    end
  end

  context "when SLO tracking is disabled" do
    before do
      E11y.configure do |config|
        config.slo_tracking.enabled = false
      end
    end

    it "does not track any SLO metrics" do
      expect(E11y::SLO::Tracker).not_to receive(:track_background_job)

      middleware.call(worker, job, queue) { true }
    end
  end

  context "when testing UC-004 compliance" do
    before do
      E11y.configure do |config|
        config.slo_tracking.enabled = true
      end
    end

    it "provides zero-config SLO tracking for Sidekiq jobs" do
      # Just enable config and it works - no additional setup needed
      expect(E11y::SLO::Tracker).to receive(:track_background_job)

      middleware.call(worker, job, queue) { true }
    end

    it "tracks job duration for latency SLO" do
      expect(E11y::SLO::Tracker).to receive(:track_background_job).with(
        hash_including(:duration_ms)
      )

      middleware.call(worker, job, queue) { true }
    end

    it "tracks job status for success rate SLO" do
      expect(E11y::SLO::Tracker).to receive(:track_background_job).with(
        hash_including(status: :success)
      )

      middleware.call(worker, job, queue) { true }
    end
  end

  context "when testing ADR-003 compliance" do
    before do
      E11y.configure do |config|
        config.slo_tracking.enabled = true
      end
    end

    it "tracks service-level SLO (background jobs)" do
      expect(E11y::SLO::Tracker).to receive(:track_background_job).with(
        hash_including(job_class: "TestJob")
      )

      middleware.call(worker, job, queue) { true }
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat, RSpec/DescribeMethod
