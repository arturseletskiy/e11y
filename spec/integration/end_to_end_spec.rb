# frozen_string_literal: true

require "rails_helper"

RSpec.describe "End-to-End Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
  end

  describe "Complete request lifecycle" do
    it "captures all events from request to response" do
      post "/posts", params: { post: { title: "Integration Test", body: "Full lifecycle test" } }

      expect(response).to have_http_status(:created)

      events = memory_adapter.events

      # Should have multiple event types (event_name contains the class name)
      event_names = events.filter_map { |e| e[:event_name] }.uniq

      # Check for database and HTTP events by pattern
      expect(event_names.any? { |n| n.include?("Database::Query") }).to be(true)
      expect(event_names.any? { |n| n.include?("Http::Request") }).to be(true)

      # All events should have trace_id
      trace_ids = events.filter_map { |e| e[:trace_id] }.uniq
      expect(trace_ids).not_to be_empty
    end

    it "maintains context across database operations" do
      get "/posts"

      # Create a post which will trigger DB query
      Post.create!(title: "Context Test", body: "Testing context")

      events = memory_adapter.events

      # All events should have trace context
      events.each do |event|
        expect(event[:trace_id]).to be_present
        expect(event[:service_name]).to eq("dummy_app")
        expect(event[:environment]).to eq("test")
      end
    end
  end

  describe "Error handling" do
    it "captures errors without breaking request" do
      expect { get "/test_error" }.to raise_error(StandardError)

      # Events should still be captured before error
      events = memory_adapter.events
      expect(events).not_to be_empty
    end
  end

  describe "Performance" do
    it "handles multiple concurrent requests" do
      # CRITICAL: Clear adapter immediately before test to ensure clean state
      # The before hook at describe level may not be sufficient due to test execution order
      memory_adapter.clear!
      
      threads = Array.new(5) do
        Thread.new do
          get "/posts"
        end
      end

      threads.each(&:join)

      events = memory_adapter.events

      # Should have events from all requests - look for Http::Request events
      request_events = events.select { |e| e[:event_name]&.include?("Http::Request") }
      expect(request_events.size).to eq(5)

      # Each request should have unique trace_id
      trace_ids = request_events.map { |e| e[:trace_id] }.uniq
      expect(trace_ids.size).to eq(5)
    end
  end
end
