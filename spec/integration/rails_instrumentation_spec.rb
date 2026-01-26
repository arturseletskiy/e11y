# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rails Instrumentation Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }

  describe "ActiveRecord instrumentation" do
    it "captures database queries" do
      Post.create!(title: "Test Post", body: "Test body")

      events = memory_adapter.events
      query_events = events.select { |e| e[:event_name]&.include?("Database::Query") }

      expect(query_events).not_to be_empty

      insert_event = query_events.find { |e| e[:payload][:sql]&.include?("INSERT INTO") }
      expect(insert_event).not_to be_nil
      expect(insert_event[:payload][:sql]).to include("INSERT INTO")
    end

    it "tracks query duration" do
      Post.create!(title: "Test Post", body: "Test body")

      events = memory_adapter.events
      query_event = events.find { |e| e[:event_name]&.include?("Database::Query") }

      # Duration is in the payload
      expect(query_event[:payload][:duration]).to be > 0
    end
  end

  describe "ActionController instrumentation" do
    it "captures controller processing" do
      get "/posts"

      events = memory_adapter.events
      # Http::Request events capture controller processing
      request_events = events.select { |e| e[:event_name]&.include?("Http::Request") }

      expect(request_events).not_to be_empty
      expect(request_events.first[:payload][:controller]).to eq("PostsController")
      expect(request_events.first[:payload][:action]).to eq("index")
    end

    it "captures redirects" do
      get "/test_redirect"

      events = memory_adapter.events
      redirect_events = events.select { |e| e[:event_name]&.include?("Http::Redirect") }

      expect(redirect_events).not_to be_empty
      expect(redirect_events.first[:payload][:location]).to include("/posts")
    end
  end

  describe "View rendering instrumentation" do
    it "captures view rendering events" do
      # This would require actual view templates
      # For now, we're using JSON rendering which doesn't trigger view events
      skip "Add view template tests when needed"
    end
  end
end
