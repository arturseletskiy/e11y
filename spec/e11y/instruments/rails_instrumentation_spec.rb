# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Instruments::RailsInstrumentation do
  # Stub ActiveSupport::Notifications if not available
  before do
    unless defined?(ActiveSupport::Notifications)
      stub_const("ActiveSupport::Notifications", Module.new do
        def self.subscribe(_pattern, &); end
      end)
    end
  end

  describe "DEFAULT_RAILS_EVENT_MAPPING" do
    it "defines mappings for Rails events" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING).to be_a(Hash)
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING).not_to be_empty
    end

    it "includes database query mapping" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["sql.active_record"]).to eq("E11y::Events::Rails::Database::Query")
    end

    it "includes HTTP request mapping" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["process_action.action_controller"])
        .to eq("E11y::Events::Rails::Http::Request")
    end

    it "includes view rendering mapping" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["render_template.action_view"]).to eq("E11y::Events::Rails::View::Render")
    end

    it "includes cache operations mappings" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["cache_read.active_support"]).to eq("E11y::Events::Rails::Cache::Read")
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["cache_write.active_support"]).to eq("E11y::Events::Rails::Cache::Write")
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["cache_delete.active_support"]).to eq("E11y::Events::Rails::Cache::Delete")
    end

    it "includes job processing mappings" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["enqueue.active_job"]).to eq("E11y::Events::Rails::Job::Enqueued")
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["perform.active_job"]).to eq("E11y::Events::Rails::Job::Completed")
    end

    it "is frozen" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING).to be_frozen
    end
  end

  describe ".setup!" do
    it "returns early if rails_instrumentation not enabled" do
      allow(E11y.config).to receive(:rails_instrumentation).and_return(nil)
      expect(described_class).not_to receive(:event_mapping)
      described_class.setup!
    end

    it "returns early if rails_instrumentation.enabled is false" do
      config = double(enabled: false)
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)
      expect(described_class).not_to receive(:event_mapping)
      described_class.setup!
    end

    it "subscribes to configured events when enabled" do
      config = double(enabled: true, custom_mappings: {}, ignore_events: [])
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)
      allow(described_class).to receive(:ignored?).and_return(false)

      expect(described_class).to receive(:subscribe_to_event).at_least(:once)
      described_class.instance_variable_set(:@event_mapping, nil) # Reset cache
      described_class.setup!
    end

    it "skips ignored events" do
      config = double(enabled: true, custom_mappings: {}, ignore_events: ["sql.active_record"])
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect(described_class).not_to receive(:subscribe_to_event).with("sql.active_record", anything)
      described_class.instance_variable_set(:@event_mapping, nil) # Reset cache
      described_class.setup!
    end
  end

  describe ".event_mapping" do
    before do
      described_class.instance_variable_set(:@event_mapping, nil) # Reset cache
    end

    it "returns DEFAULT_RAILS_EVENT_MAPPING when no custom mappings" do
      config = double(custom_mappings: {})
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      mapping = described_class.event_mapping
      expect(mapping).to include(described_class::DEFAULT_RAILS_EVENT_MAPPING)
    end

    it "applies custom mappings from config" do
      custom_event_class = double(name: "CustomEventClass")
      config = double(custom_mappings: { "custom.event" => custom_event_class })
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      mapping = described_class.event_mapping
      expect(mapping["custom.event"]).to eq("CustomEventClass")
    end

    it "caches the mapping" do
      config = double(custom_mappings: {})
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      mapping1 = described_class.event_mapping
      mapping2 = described_class.event_mapping
      expect(mapping1.object_id).to eq(mapping2.object_id)
    end

    it "handles nil custom_mappings" do
      config = double(custom_mappings: nil)
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect { described_class.event_mapping }.not_to raise_error
    end
  end

  describe ".ignored?" do
    it "returns false when pattern not in ignore list" do
      config = double(ignore_events: ["other.event"])
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect(described_class.ignored?("sql.active_record")).to be false
    end

    it "returns true when pattern in ignore list" do
      config = double(ignore_events: ["sql.active_record"])
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect(described_class.ignored?("sql.active_record")).to be true
    end

    it "handles nil ignore_events" do
      config = double(ignore_events: nil)
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect(described_class.ignored?("sql.active_record")).to be false
    end

    it "handles empty ignore_events array" do
      config = double(ignore_events: [])
      allow(E11y.config).to receive(:rails_instrumentation).and_return(config)

      expect(described_class.ignored?("sql.active_record")).to be false
    end
  end

  describe ".extract_job_info_from_object" do
    it "extracts job info from job object" do
      job = double("Job", class: double(name: "MyJob"), job_id: "123", queue_name: "default")
      payload = { job: job, other: "data" }
      result = described_class.extract_job_info_from_object(payload)

      expect(result[:job_class]).to eq("MyJob")
      expect(result[:job_id]).to eq("123")
      expect(result[:queue]).to eq("default")
      expect(result[:other]).to eq("data")
      expect(result).not_to have_key(:job)
    end

    it "returns payload unchanged when no job object" do
      payload = { controller: "Users", action: "index" }
      result = described_class.extract_job_info_from_object(payload)

      expect(result).to eq(payload)
    end

    it "does not override existing job fields" do
      job = double("Job", class: double(name: "NewJob"), job_id: "456", queue_name: "low")
      payload = { job: job, job_class: "ExistingJob", job_id: "789" }
      result = described_class.extract_job_info_from_object(payload)

      expect(result[:job_class]).to eq("ExistingJob")
      expect(result[:job_id]).to eq("789")
      expect(result[:queue]).to eq("low")
    end
  end

  describe ".resolve_event_class" do
    it "resolves existing constant" do
      stub_const("TestEventClass", Class.new)
      result = described_class.resolve_event_class("TestEventClass")
      expect(result).to eq(TestEventClass)
    end

    it "returns nil for non-existent constant" do
      result = described_class.resolve_event_class("NonExistentEventClass")
      expect(result).to be_nil
    end

    it "warns when class not found" do
      expect do
        described_class.resolve_event_class("MissingClass")
      end.to output(/Event class not found.*MissingClass/).to_stderr
    end

    it "handles nested constant names" do
      stub_const("Events::Rails::CustomEvent", Class.new)
      result = described_class.resolve_event_class("Events::Rails::CustomEvent")
      expect(result).to eq(Events::Rails::CustomEvent)
    end
  end

  describe ".subscribe_to_event" do
    let(:event_class) { double("EventClass", track: true) }

    before do
      allow(described_class).to receive(:resolve_event_class).and_return(event_class)
    end

    it "subscribes to ActiveSupport::Notifications" do
      expect(ActiveSupport::Notifications).to receive(:subscribe).with("test.event")
      described_class.subscribe_to_event("test.event", "TestEventClass")
    end

    it "calculates duration in milliseconds" do
      allow(ActiveSupport::Notifications).to receive(:subscribe).and_yield(
        "test.event", Time.now, Time.now + 1, "id", {}
      )

      expect(event_class).to receive(:track).with(hash_including(duration: be_within(50).of(1000)))
      described_class.subscribe_to_event("test.event", "TestEventClass")
    end

    it "passes all payload fields to event class" do
      payload = { controller: "Users", action: "index", custom_field: "value" }
      allow(ActiveSupport::Notifications).to receive(:subscribe).and_yield(
        "test.event", Time.now, Time.now, "id", payload
      )

      expect(event_class).to receive(:track) do |args|
        expect(args[:controller]).to eq("Users")
        expect(args[:action]).to eq("index")
        expect(args[:custom_field]).to eq("value")
      end
      described_class.subscribe_to_event("test.event", "TestEventClass")
    end

    it "skips tracking when event class cannot be resolved" do
      allow(described_class).to receive(:resolve_event_class).and_return(nil)
      allow(ActiveSupport::Notifications).to receive(:subscribe).and_yield(
        "test.event", Time.now, Time.now, "id", {}
      )

      expect(event_class).not_to receive(:track)
      described_class.subscribe_to_event("test.event", "MissingClass")
    end

    it "handles tracking errors gracefully" do
      allow(ActiveSupport::Notifications).to receive(:subscribe).and_yield(
        "test.event", Time.now, Time.now, "id", {}
      )
      allow(event_class).to receive(:track).and_raise(StandardError, "Tracking failed")

      expect do
        described_class.subscribe_to_event("test.event", "TestEventClass")
      end.to output(/Failed to track Rails event.*Tracking failed/).to_stderr
    end
  end
end
