# frozen_string_literal: true

require "spec_helper"

RSpec.describe "E11y::Events::Rails::Job" do
  describe E11y::Events::Rails::Job::Enqueued do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "enqueue.active_job",
        duration: 2.5,
        job_class: "UserMailerJob",
        job_id: "abc-123",
        queue: "mailers"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:job_class]).to eq("UserMailerJob")
    end
  end

  describe E11y::Events::Rails::Job::Scheduled do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "enqueue_at.active_job",
        duration: 1.5,
        job_class: "ReportJob",
        job_id: "def-456",
        queue: "default"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:job_class]).to eq("ReportJob")
    end
  end

  describe E11y::Events::Rails::Job::Started do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "perform_start.active_job",
        duration: 0.5,
        job_class: "DataSyncJob",
        job_id: "ghi-789",
        queue: "high_priority"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:job_class]).to eq("DataSyncJob")
    end
  end

  describe E11y::Events::Rails::Job::Completed do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "perform.active_job",
        duration: 156.7,
        job_class: "ImportJob",
        job_id: "jkl-012",
        queue: "default"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:job_class]).to eq("ImportJob")
    end
  end

  describe E11y::Events::Rails::Job::Failed do
    it "inherits from E11y::Event::Base" do
      expect(described_class.superclass).to eq(E11y::Event::Base)
    end

    it "has schema defined" do
      expect(described_class).to respond_to(:schema)
    end

    it "can track event with valid payload" do
      result = described_class.track(
        event_name: "perform.active_job",
        duration: 45.2,
        job_class: "FailingJob",
        job_id: "mno-345",
        queue: "default",
        error: "RuntimeError: Something went wrong"
      )
      expect(result).to be_a(Hash)
      expect(result[:payload][:error]).to eq("RuntimeError: Something went wrong")
    end
  end
end
