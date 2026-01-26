# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Adapters Integration", :integration, type: :integration do
  describe "InMemory adapter" do
    let(:memory_adapter) { E11y.config.adapters[:memory] }

    it "stores events in memory" do
      # Verify adapter is configured
      expect(memory_adapter).not_to be_nil, "Memory adapter should be configured in application.rb"

      Post.create!(title: "Test", body: "Body")

      expect(memory_adapter.events).not_to be_empty
    end

    it "allows clearing events" do
      Post.create!(title: "Test", body: "Body")
      expect(memory_adapter.events).not_to be_empty

      memory_adapter.clear!
      expect(memory_adapter.events).to be_empty
    end

    it "provides event count" do
      Post.create!(title: "Test 1", body: "Body 1")
      Post.create!(title: "Test 2", body: "Body 2")

      expect(memory_adapter.events.size).to be > 0
    end
  end

  describe "Multiple adapters" do
    it "can register multiple adapters" do
      # Add stdout adapter using Hash API
      E11y.configure do |config|
        config.adapters[:stdout] = E11y::Adapters::Stdout.new
      end

      expect(E11y.config.adapters[:memory]).to be_present
      expect(E11y.config.adapters[:stdout]).to be_present
    end

    it "sends events to all registered adapters" do
      memory_adapter = E11y.config.adapters[:memory]
      memory_adapter.clear!

      Post.create!(title: "Test", body: "Body")

      # Memory adapter should receive events
      expect(memory_adapter.events).not_to be_empty
    end
  end
end
