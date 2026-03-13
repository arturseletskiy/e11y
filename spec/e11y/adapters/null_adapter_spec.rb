# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Adapters::Null do
  let(:adapter) { described_class.new }

  describe "#initialize" do
    it "starts with empty events list" do
      expect(adapter.events).to eq([])
    end
  end

  describe "#write" do
    let(:event_data) { { event_name: "order.created", severity: :info, amount: 99.99 } }

    it "returns true" do
      expect(adapter.write(event_data)).to be(true)
    end

    it "stores event in @events" do
      adapter.write(event_data)
      expect(adapter.events.size).to eq(1)
    end

    it "stores event with correct data" do
      adapter.write(event_data)
      expect(adapter.events.last[:event_name]).to eq("order.created")
    end

    it "accumulates multiple events" do
      adapter.write(event_name: "first.event", severity: :info)
      adapter.write(event_name: "second.event", severity: :warn)
      expect(adapter.events.size).to eq(2)
    end

    it "makes a dup copy — original hash is not mutated by later modification" do
      original = { event_name: "user.signed_up", severity: :info }
      adapter.write(original)
      original[:severity] = :error
      expect(adapter.events.last[:severity]).to eq(:info)
    end
  end

  describe "#write_batch" do
    let(:events) do
      [
        { event_name: "batch.event.1", severity: :info },
        { event_name: "batch.event.2", severity: :warn },
        { event_name: "batch.event.3", severity: :error }
      ]
    end

    it "returns true" do
      expect(adapter.write_batch(events)).to be(true)
    end

    it "stores all events" do
      adapter.write_batch(events)
      expect(adapter.events.size).to eq(3)
    end

    it "preserves event data" do
      adapter.write_batch(events)
      names = adapter.events.map { |e| e[:event_name] }
      expect(names).to eq(["batch.event.1", "batch.event.2", "batch.event.3"])
    end

    it "makes dup copies — originals are not mutated by later modification" do
      mutable_events = [
        { event_name: "batch.dup.test", severity: :info }
      ]
      adapter.write_batch(mutable_events)
      mutable_events.first[:severity] = :fatal
      expect(adapter.events.last[:severity]).to eq(:info)
    end

    it "appends to already-stored events" do
      adapter.write(event_name: "existing.event", severity: :info)
      adapter.write_batch(events)
      expect(adapter.events.size).to eq(4)
    end
  end

  describe "#events" do
    it "returns all accumulated events in order" do
      adapter.write(event_name: "first", severity: :info)
      adapter.write(event_name: "second", severity: :warn)
      expect(adapter.events.map { |e| e[:event_name] }).to eq(%w[first second])
    end
  end

  describe "#clear!" do
    before do
      adapter.write(event_name: "to.be.cleared", severity: :info)
      adapter.write(event_name: "also.cleared", severity: :warn)
    end

    it "removes all stored events" do
      adapter.clear!
      expect(adapter.events).to be_empty
    end

    it "allows writing after clearing" do
      adapter.clear!
      adapter.write(event_name: "after.clear", severity: :info)
      expect(adapter.events.size).to eq(1)
    end
  end

  describe "#healthy?" do
    it "always returns true" do
      expect(adapter.healthy?).to be(true)
    end
  end

  describe "#capabilities" do
    subject(:caps) { adapter.capabilities }

    it "returns a hash" do
      expect(caps).to be_a(Hash)
    end

    it "reports batching: true" do
      expect(caps[:batching]).to be(true)
    end
  end

  describe "thread safety" do
    it "does not lose events under concurrent writes" do
      threads = Array.new(20) do |i|
        Thread.new do
          adapter.write(event_name: "concurrent.event.#{i}", severity: :info)
        end
      end
      threads.each(&:join)
      expect(adapter.events.size).to eq(20)
    end

    it "does not lose events under concurrent write_batch calls" do
      threads = Array.new(5) do |i|
        Thread.new do
          adapter.write_batch([
                                { event_name: "batch.#{i}.a", severity: :info },
                                { event_name: "batch.#{i}.b", severity: :info }
                              ])
        end
      end
      threads.each(&:join)
      expect(adapter.events.size).to eq(10)
    end
  end
end

RSpec.describe E11y::Adapters::NullAdapter do
  it "is an alias for E11y::Adapters::Null" do
    expect(described_class).to eq(E11y::Adapters::Null)
  end

  it "can be instantiated directly" do
    adapter = described_class.new
    expect(adapter).to be_a(E11y::Adapters::Null)
  end
end

RSpec.describe "NullAdapter integration with E11y.configure" do
  let(:null_adapter) { E11y::Adapters::NullAdapter.new }

  # Register the null adapter under the :logs key so the default routing
  # (severity :info → :logs) delivers events to it.
  before do
    E11y.configure do |c|
      c.adapters[:logs] = null_adapter
    end
  end

  it "receives events tracked through E11y pipeline" do
    # Build a simple event class for this integration test.
    # sample_rate 1.0 ensures the sampling middleware always passes the event through.
    event_class = Class.new(E11y::Event::Base) do
      contains_pii false
      sample_rate 1.0

      schema do
        required(:order_id).filled(:string)
      end
    end

    stub_const("Events::NullAdapterIntegrationTest", event_class)

    event_class.track(order_id: "ord-123")

    expect(null_adapter.events.size).to eq(1)
    # Event data stored by the routing middleware includes :payload with the fields
    expect(null_adapter.events.last[:payload][:order_id]).to eq("ord-123")
  end

  it "can be cleared between test examples" do
    null_adapter.write(event_name: "leftover.event", severity: :info)
    null_adapter.clear!
    expect(null_adapter.events).to be_empty
  end
end
