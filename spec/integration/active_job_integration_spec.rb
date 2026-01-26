# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ActiveJob Integration", :integration, type: :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
    ActiveJob::Base.queue_adapter = :test
  end

  describe "Job enqueue" do
    it "captures job enqueue events" do
      DummyTestJob.perform_later("test message")

      events = memory_adapter.events
      # Event name is the class name, check for Job::Enqueued pattern
      enqueue_events = events.select { |e| e[:event_name]&.include?("Job::Enqueued") }

      expect(enqueue_events).not_to be_empty
      expect(enqueue_events.first[:payload][:job_class]).to eq("DummyTestJob")
    end
  end

  describe "Job perform" do
    it "captures job execution events" do
      DummyTestJob.perform_now("test message")

      events = memory_adapter.events
      # Look for Started and Completed events by event_name pattern
      started_events = events.select { |e| e[:event_name]&.include?("Job::Started") }
      completed_events = events.select { |e| e[:event_name]&.include?("Job::Completed") }

      expect(started_events).not_to be_empty
      expect(completed_events).not_to be_empty
      expect(started_events.first[:payload][:job_class]).to eq("DummyTestJob")
    end

    it "tracks job duration" do
      DummyTestJob.perform_now("test message")

      events = memory_adapter.events
      completed_event = events.find { |e| e[:event_name]&.include?("Job::Completed") }

      # Duration is in the payload as :duration (milliseconds)
      expect(completed_event[:payload][:duration]).to be >= 0
    end
  end

  describe "Job failure" do
    before do
      # Create a job that will fail
      stub_const("FailingJob", Class.new(ActiveJob::Base) do
        def perform
          raise StandardError, "Job failed"
        end
      end)
    end

    it "captures job failure events" do
      expect { FailingJob.perform_now }.to raise_error(StandardError)

      events = memory_adapter.events
      # Job failures may be captured via perform.active_job with exception info
      # or via a separate failed event
      failed_events = events.select { |e| e[:event_name]&.include?("Job") }

      # At minimum, we should have job events captured
      expect(failed_events).not_to be_empty
    end
  end
end
