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

    it "includes start_processing mapping" do
      expect(described_class::DEFAULT_RAILS_EVENT_MAPPING["start_processing.action_controller"])
        .to eq("E11y::Events::Rails::Http::StartProcessing")
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
    it "returns early when rails_instrumentation is disabled" do
      allow(E11y.config).to receive(:rails_instrumentation_enabled).and_return(false)
      expect(described_class).not_to receive(:event_mapping)
      described_class.setup!
    end

    it "subscribes to configured events when enabled" do
      allow(E11y.config).to receive_messages(rails_instrumentation_enabled: true, rails_instrumentation_custom_mappings: {},
                                             rails_instrumentation_ignore_events: [])
      allow(described_class).to receive(:ignored?).and_return(false)

      expect(described_class).to receive(:subscribe_to_event).at_least(:once)
      described_class.instance_variable_set(:@event_mapping, nil) # Reset cache
      described_class.setup!
    end

    it "skips ignored events" do
      allow(E11y.config).to receive_messages(rails_instrumentation_enabled: true, rails_instrumentation_custom_mappings: {},
                                             rails_instrumentation_ignore_events: ["sql.active_record"])

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
      allow(E11y.config).to receive(:rails_instrumentation_custom_mappings).and_return({})

      mapping = described_class.event_mapping
      expect(mapping).to include(described_class::DEFAULT_RAILS_EVENT_MAPPING)
    end

    it "applies custom mappings from config" do
      custom_event_class = double(name: "CustomEventClass")
      allow(E11y.config).to receive(:rails_instrumentation_custom_mappings).and_return("custom.event" => custom_event_class)

      mapping = described_class.event_mapping
      expect(mapping["custom.event"]).to eq("CustomEventClass")
    end

    it "caches the mapping" do
      allow(E11y.config).to receive(:rails_instrumentation_custom_mappings).and_return({})

      mapping1 = described_class.event_mapping
      mapping2 = described_class.event_mapping
      expect(mapping1.object_id).to eq(mapping2.object_id)
    end

    it "handles nil custom_mappings" do
      allow(E11y.config).to receive(:rails_instrumentation_custom_mappings).and_return(nil)

      expect { described_class.event_mapping }.not_to raise_error
    end
  end

  describe ".ignored?" do
    it "returns false when pattern not in ignore list" do
      allow(E11y.config).to receive(:rails_instrumentation_ignore_events).and_return(["other.event"])

      expect(described_class.ignored?("sql.active_record")).to be false
    end

    it "returns true when pattern in ignore list" do
      allow(E11y.config).to receive(:rails_instrumentation_ignore_events).and_return(["sql.active_record"])

      expect(described_class.ignored?("sql.active_record")).to be true
    end

    it "handles nil ignore_events" do
      allow(E11y.config).to receive(:rails_instrumentation_ignore_events).and_return(nil)

      expect(described_class.ignored?("sql.active_record")).to be false
    end

    it "handles empty ignore_events array" do
      allow(E11y.config).to receive(:rails_instrumentation_ignore_events).and_return([])

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

  describe ".extract_job_exception_info" do
    it "extracts error_class and error_message from exception array" do
      payload = { exception: ["RuntimeError", "Something went wrong"] }
      result = described_class.extract_job_exception_info(payload)
      expect(result).to eq(error_class: "RuntimeError", error_message: "Something went wrong")
    end

    it "extracts from exception object" do
      error = StandardError.new("Test error")
      payload = { exception: error }
      result = described_class.extract_job_exception_info(payload)
      expect(result).to eq(error_class: "StandardError", error_message: "Test error")
    end

    it "returns empty hash when no exception" do
      expect(described_class.extract_job_exception_info({})).to eq({})
    end
  end

  describe "perform.active_job routing to Failed" do
    it "routes to Failed event when payload has exception" do
      start_time = Time.now
      finish_time = start_time + 0.1
      payload = {
        job: double("Job", class: double(name: "FailingJob"), job_id: "123", queue_name: "default"),
        exception: ["RuntimeError", "Job crashed"]
      }

      expect(E11y::Events::Rails::Job::Failed).to receive(:track).with(
        hash_including(
          event_name: "perform.active_job",
          job_class: "FailingJob",
          job_id: "123",
          queue: "default",
          error_class: "RuntimeError",
          error_message: "Job crashed"
        )
      )
      expect(E11y::Events::Rails::Job::Completed).not_to receive(:track)

      described_class.track_rails_event(
        "perform.active_job", start_time, finish_time, payload,
        "E11y::Events::Rails::Job::Completed"
      )
    end

    it "routes to Completed when no exception" do
      start_time = Time.now
      finish_time = start_time + 0.1
      payload = {
        job: double("Job", class: double(name: "SuccessJob"), job_id: "456", queue_name: "default")
      }

      expect(E11y::Events::Rails::Job::Completed).to receive(:track).with(
        hash_including(event_name: "perform.active_job", job_class: "SuccessJob")
      )
      expect(E11y::Events::Rails::Job::Failed).not_to receive(:track)

      described_class.track_rails_event(
        "perform.active_job", start_time, finish_time, payload,
        "E11y::Events::Rails::Job::Completed"
      )
    end
  end

  describe ".coerce_symbol_values" do
    it "converts Symbol values to String" do
      payload = { super_operation: :fetch, key: "users/1" }
      result = described_class.coerce_symbol_values(payload)
      expect(result[:super_operation]).to eq("fetch")
      expect(result[:key]).to eq("users/1")
    end

    it "leaves non-Symbol values unchanged" do
      payload = { count: 42, hit: true, key: nil }
      result = described_class.coerce_symbol_values(payload)
      expect(result).to eq(payload)
    end
  end

  describe "cache_read.active_support with Symbol super_operation (regression BUG-005)" do
    it "does not raise validation error when Rails passes super_operation as Symbol" do
      start_time = Time.now
      finish_time = start_time + 0.001
      payload = { key: "users/1", hit: true, super_operation: :fetch }

      expect {
        described_class.track_rails_event(
          "cache_read.active_support", start_time, finish_time, payload,
          "E11y::Events::Rails::Cache::Read"
        )
      }.not_to output(/Validation failed.*super_operation/).to_stderr
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
