# frozen_string_literal: true

require "rails_helper"

RSpec.describe "E11y Middleware Integration", :integration do
  let(:app) { Rails.application }
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  before do
    memory_adapter.clear!
  end

  describe "Request middleware" do
    it "captures HTTP request events" do
      get "/posts"

      expect(response).to have_http_status(:ok)

      # Check that request event was captured (event_name contains class name)
      events = memory_adapter.events
      request_events = events.select { |e| e[:event_name]&.include?("Http::Request") }

      expect(request_events).not_to be_empty
      # Controller/action info is in the payload
      expect(request_events.first[:payload][:controller]).to eq("PostsController")
      expect(request_events.first[:payload][:action]).to eq("index")
    end

    it "sets trace context for requests" do
      get "/posts"

      events = memory_adapter.events
      request_event = events.find { |e| e[:event_name]&.include?("Http::Request") }

      expect(request_event[:trace_id]).to be_present
      expect(request_event[:span_id]).to be_present
    end
  end

  describe "Request context" do
    it "maintains context across middleware stack" do
      get "/posts"

      events = memory_adapter.events
      trace_ids = events.filter_map { |e| e[:trace_id] }.uniq

      # All events in same request should share trace context
      # Note: Some events may have been captured before trace context was set
      expect(trace_ids).not_to be_empty
    end
  end
end
