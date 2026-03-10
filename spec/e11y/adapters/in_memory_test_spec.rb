# frozen_string_literal: true

require "spec_helper"
require "e11y/adapters/in_memory"
require "e11y/adapters/in_memory_test"

RSpec.describe E11y::Adapters::InMemoryTest do
  subject(:adapter) { described_class.new }

  let(:app_event)   { { event_name: "order.paid", severity: :info, payload: {} } }
  let(:rails_event) { { event_name: "E11y::Events::Rails::RequestCompleted", severity: :info, payload: {} } }

  describe "#last_event" do
    it "skips Rails instrumentation events" do
      adapter.write(app_event)
      adapter.write(rails_event)
      expect(adapter.last_event).to eq(app_event)
    end

    it "returns nil when only Rails events are present" do
      adapter.write(rails_event)
      expect(adapter.last_event).to be_nil
    end

    it "returns the most recent non-Rails event" do
      adapter.write(app_event)
      adapter.write({ event_name: "order.failed", severity: :error, payload: {} })
      adapter.write(rails_event)
      expect(adapter.last_event[:event_name]).to eq("order.failed")
    end
  end

  it "inherits all InMemory behaviour" do
    adapter.write(app_event)
    expect(adapter.event_count).to eq(1)
    expect(adapter.events).to include(app_event)
  end
end
