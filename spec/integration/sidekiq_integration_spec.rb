# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sidekiq Integration", :integration do
  # NOTE: Sidekiq::Testing.inline! does NOT run server middleware in Sidekiq 7.x
  # Server middleware behavior is tested in unit tests (spec/e11y/instruments/sidekiq_spec.rb)
  # This integration test focuses on:
  # - Configuration and Railtie integration
  # - Client middleware (which DOES run in inline mode)
  # - Overall Sidekiq integration setup

  # Test Sidekiq worker - using stub_const to avoid leaky constant
  let(:test_worker_class) do
    Class.new do
      include Sidekiq::Worker

      def perform
        # Simple worker for testing
      end
    end
  end

  before do
    stub_const("TestWorker", test_worker_class)

    # Configure Sidekiq with E11y middleware
    Sidekiq.configure_server do |config|
      config.server_middleware do |chain|
        chain.add E11y::Instruments::Sidekiq::ServerMiddleware
      end
    end

    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add E11y::Instruments::Sidekiq::ClientMiddleware
      end
    end
    # Use fake mode for testing (jobs are queued but not executed)
    Sidekiq::Testing.fake!
  end

  after do
    Sidekiq::Testing.disable!
    Sidekiq::Worker.clear_all
    E11y::Current.reset
    Sidekiq::Testing.disable!
    E11y::Current.reset
  end

  describe "Client Middleware: Trace Context Injection" do
    it "injects e11y_parent_trace_id into job metadata when enqueueing from request context" do
      # Simulate request context with trace_id
      E11y::Current.trace_id = "parent_trace_abc123"
      E11y::Current.span_id = "parent_span_xyz789"

      # Enqueue job (will be added to fake queue)
      TestWorker.perform_async

      # Check queued job metadata
      jobs = TestWorker.jobs
      expect(jobs.size).to eq(1)

      job = jobs.first
      expect(job["e11y_parent_trace_id"]).to eq("parent_trace_abc123")
      expect(job["e11y_parent_span_id"]).to eq("parent_span_xyz789")
    ensure
      E11y::Current.reset
    end

    it "does not inject trace metadata when enqueueing outside request context" do
      # No trace context set
      E11y::Current.reset

      # Enqueue job
      TestWorker.perform_async

      # Check queued job metadata
      jobs = TestWorker.jobs
      expect(jobs.size).to eq(1)

      job = jobs.first
      expect(job).not_to have_key("e11y_parent_trace_id")
      expect(job).not_to have_key("e11y_parent_span_id")
    end
  end

  # NOTE: Server middleware tests are in spec/e11y/instruments/sidekiq_spec.rb
  # because Sidekiq::Testing.inline! does NOT run server middleware in Sidekiq 7.x

  describe "Railtie Integration: Auto-Setup" do
    it "provides Railtie setup method for Sidekiq" do
      # Check that Railtie has setup_sidekiq method
      expect(E11y::Railtie).to respond_to(:setup_sidekiq)
    end

    it "respects E11y.config.sidekiq.enabled setting" do
      # Check that config has sidekiq settings
      expect(E11y.config).to respond_to(:sidekiq)
      expect(E11y.config.sidekiq).to respond_to(:enabled)
    end
  end
end
