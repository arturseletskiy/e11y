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
      # Create some posts to render
      Post.create!(title: "Post 1", body: "Body 1")
      Post.create!(title: "Post 2", body: "Body 2")
      
      memory_adapter.clear!
      
      # Make a request that renders a view template
      get "/posts_list"
      
      expect(response).to be_successful
      
      events = memory_adapter.events
      # Rails emits render_template.action_view events for view rendering
      render_events = events.select { |e| e[:event_name]&.include?("View::Render") }
      
      expect(render_events).not_to be_empty
      
      # The event should include template identifier
      template_event = render_events.find { |e| e[:payload][:identifier]&.include?("posts/list") }
      expect(template_event).not_to be_nil
      expect(template_event[:payload][:identifier]).to include("posts/list.html.erb")
    end
  end
end
