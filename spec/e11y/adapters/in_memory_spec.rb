# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Adapters::InMemory do
  let(:adapter) { described_class.new }
  let(:paid_order_event) { { event_name: "order.paid", severity: :success, payload: { order_id: "123" } } }
  let(:failed_order_event) { { event_name: "order.failed", severity: :error, payload: { order_id: "456" } } }
  let(:user_created_event) { { event_name: "user.created", severity: :info, payload: { user_id: "789" } } }

  describe "#initialize" do
    it "defaults to 1000 max_events" do
      expect(adapter.max_events).to eq(1000)
    end

    it "accepts custom max_events" do
      custom_adapter = described_class.new(max_events: 100)
      expect(custom_adapter.max_events).to eq(100)
    end

    it "allows unlimited events with max_events: nil" do
      unlimited_adapter = described_class.new(max_events: nil)
      expect(unlimited_adapter.max_events).to be_nil
    end

    it "initializes dropped_count to 0" do
      expect(adapter.dropped_count).to eq(0)
    end
  end

  describe "#write" do
    it "stores event in memory" do
      adapter.write(paid_order_event)
      expect(adapter.events).to eq([paid_order_event])
    end

    it "returns true on success" do
      expect(adapter.write(paid_order_event)).to be true
    end

    it "appends events in order" do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
      adapter.write(user_created_event)

      expect(adapter.events).to eq([paid_order_event, failed_order_event, user_created_event])
    end

    it "is thread-safe" do
      threads = Array.new(10) do |i|
        Thread.new { adapter.write({ event_name: "test.#{i}", severity: :info }) }
      end

      threads.each(&:join)

      expect(adapter.events.size).to eq(10)
    end
  end

  describe "#write_batch" do
    let(:batch) { [paid_order_event, failed_order_event, user_created_event] }

    it "stores all events from batch" do
      adapter.write_batch(batch)
      expect(adapter.events).to eq(batch)
    end

    it "tracks batches separately" do
      adapter.write_batch(batch)
      expect(adapter.batches).to eq([batch])
    end

    it "returns true on success" do
      expect(adapter.write_batch(batch)).to be true
    end

    it "appends batch events to events list" do
      adapter.write(paid_order_event)
      adapter.write_batch([failed_order_event, user_created_event])

      expect(adapter.events).to eq([paid_order_event, failed_order_event, user_created_event])
    end

    it "is thread-safe" do
      threads = Array.new(5) do |i|
        Thread.new { adapter.write_batch([{ event_name: "batch.#{i}.event", severity: :info }]) }
      end

      threads.each(&:join)

      expect(adapter.batches.size).to eq(5)
    end
  end

  # rubocop:disable RSpec/RepeatedExampleGroupDescription
  # Testing #clear! method in two contexts: basic operations and memory limits
  describe "#clear!" do
    before do
      adapter.write(paid_order_event)
      adapter.write_batch([failed_order_event, user_created_event])
    end

    it "clears all events" do
      adapter.clear!
      expect(adapter.events).to be_empty
    end

    it "clears all batches" do
      adapter.clear!
      expect(adapter.batches).to be_empty
    end

    it "resets dropped_count" do
      limited_adapter = described_class.new(max_events: 1)
      limited_adapter.write(paid_order_event)
      limited_adapter.write(failed_order_event)

      expect(limited_adapter.dropped_count).to be > 0
      limited_adapter.clear!
      expect(limited_adapter.dropped_count).to eq(0)
    end
  end
  # rubocop:enable RSpec/RepeatedExampleGroupDescription

  describe "memory limit enforcement" do
    context "with default limit (1000 events)" do
      it "enforces default 1000 event limit" do
        1500.times { |i| adapter.write({ event_name: "event.#{i}", severity: :info }) }

        expect(adapter.events.size).to eq(1000)
        expect(adapter.dropped_count).to eq(500)
      end

      it "drops oldest events first (FIFO)" do
        1100.times { |i| adapter.write({ event_name: "event.#{i}", severity: :info }) }

        # Should have events 100-1099 (oldest 0-99 dropped)
        expect(adapter.events.first[:event_name]).to eq("event.100")
        expect(adapter.events.last[:event_name]).to eq("event.1099")
      end
    end

    context "with custom limit" do
      let(:limited_adapter) { described_class.new(max_events: 3) }

      it "enforces custom limit" do
        5.times { |i| limited_adapter.write({ event_name: "event.#{i}", severity: :info }) }

        expect(limited_adapter.events.size).to eq(3)
        expect(limited_adapter.dropped_count).to eq(2)
      end

      it "drops correct number on batch write" do
        limited_adapter.write_batch([paid_order_event, failed_order_event, user_created_event, paid_order_event,
                                     failed_order_event])

        expect(limited_adapter.events.size).to eq(3)
        expect(limited_adapter.dropped_count).to eq(2)
      end
    end

    context "with unlimited (nil)" do
      let(:unlimited_adapter) { described_class.new(max_events: nil) }

      it "does not enforce limit" do
        2000.times { |i| unlimited_adapter.write({ event_name: "event.#{i}", severity: :info }) }

        expect(unlimited_adapter.events.size).to eq(2000)
        expect(unlimited_adapter.dropped_count).to eq(0)
      end
    end

    it "tracks dropped count across multiple writes" do
      limited = described_class.new(max_events: 5)

      limited.write(paid_order_event)
      expect(limited.dropped_count).to eq(0)

      limited.write_batch([failed_order_event, user_created_event, paid_order_event, failed_order_event])
      expect(limited.dropped_count).to eq(0)

      limited.write_batch([user_created_event, paid_order_event, failed_order_event]) # Total 8, limit 5
      expect(limited.dropped_count).to eq(3)
    end
  end

  # rubocop:disable RSpec/RepeatedExampleGroupDescription
  # Second block tests #clear! in context of regular operations
  describe "#clear!" do
    before do
      adapter.write(paid_order_event)
      adapter.write_batch([failed_order_event, user_created_event])
    end

    it "clears all events" do
      adapter.clear!
      expect(adapter.events).to be_empty
    end

    it "clears all batches" do
      adapter.clear!
      expect(adapter.batches).to be_empty
    end
  end

  describe "#find_events" do
    before do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
      adapter.write(user_created_event)
    end

    it "finds events by string pattern" do
      results = adapter.find_events("order.paid")
      expect(results).to eq([paid_order_event])
    end

    it "finds events by regex pattern" do
      results = adapter.find_events(/order/)
      expect(results).to eq([paid_order_event, failed_order_event])
    end

    it "returns empty array when no matches" do
      results = adapter.find_events("nonexistent")
      expect(results).to be_empty
    end
  end

  describe "#clear" do
    before do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
    end

    it "clears all events" do
      adapter.clear
      expect(adapter.events).to be_empty
    end

    it "clears all batches" do
      adapter.write_batch([user_created_event])
      adapter.clear
      expect(adapter.batches).to be_empty
    end

    it "resets dropped_count" do
      # Force a drop by filling the adapter to capacity
      adapter.instance_variable_set(:@dropped_count, 3)
      adapter.clear
      expect(adapter.dropped_count).to eq(0)
    end
  end

  describe "#last_event" do
    it "returns nil when no events" do
      expect(adapter.last_event).to be_nil
    end

    it "returns the most recently written event" do
      adapter.write({ event_name: "order.paid", severity: :info, payload: {} })
      adapter.write({ event_name: "order.failed", severity: :error, payload: {} })
      expect(adapter.last_event[:event_name]).to eq("order.failed")
    end

    it "includes Rails instrumentation events (no filter in base adapter)" do
      adapter.write({ event_name: "order.paid", severity: :info, payload: {} })
      rails_evt = { event_name: "E11y::Events::Rails::RequestCompleted", severity: :info, payload: {} }
      adapter.write(rails_evt)
      expect(adapter.last_event).to eq(rails_evt)
    end
  end

  describe "#event_count" do
    before do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
      adapter.write(user_created_event)
      adapter.write(paid_order_event) # Duplicate
    end

    it "returns total count without event_name" do
      expect(adapter.event_count).to eq(4)
    end

    it "returns count for specific event_name (keyword arg)" do
      expect(adapter.event_count(event_name: "order.paid")).to eq(2)
    end

    it "returns count for specific event_name (positional string arg)" do
      expect(adapter.event_count("order.paid")).to eq(2)
    end

    it "returns zero for non-existent event_name via positional arg" do
      expect(adapter.event_count("nonexistent")).to eq(0)
    end

    it "returns zero for non-existent event_name" do
      expect(adapter.event_count(event_name: "nonexistent")).to eq(0)
    end
  end

  describe "#last_events" do
    before do
      5.times { |i| adapter.write({ event_name: "event.#{i}", severity: :info }) }
    end

    it "returns last N events" do
      results = adapter.last_events(3)
      expect(results.size).to eq(3)
      expect(results.map { |e| e[:event_name] }).to eq(["event.2", "event.3", "event.4"])
    end

    it "defaults to 10 events" do
      expect(adapter.last_events.size).to eq(5)
    end

    it "handles count larger than total events" do
      results = adapter.last_events(100)
      expect(results.size).to eq(5)
    end
  end

  describe "#first_events" do
    before do
      5.times { |i| adapter.write({ event_name: "event.#{i}", severity: :info }) }
    end

    it "returns first N events" do
      results = adapter.first_events(3)
      expect(results.size).to eq(3)
      expect(results.map { |e| e[:event_name] }).to eq(["event.0", "event.1", "event.2"])
    end

    it "defaults to 10 events" do
      expect(adapter.first_events.size).to eq(5)
    end

    it "handles count larger than total events" do
      results = adapter.first_events(100)
      expect(results.size).to eq(5)
    end
  end

  describe "#events_by_severity" do
    before do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
      adapter.write(user_created_event)
    end

    it "filters events by severity" do
      results = adapter.events_by_severity(:error)
      expect(results).to eq([failed_order_event])
    end

    it "returns empty array when no matches" do
      results = adapter.events_by_severity(:fatal)
      expect(results).to be_empty
    end

    it "returns all matching events" do
      adapter.write({ event_name: "another.error", severity: :error })
      results = adapter.events_by_severity(:error)
      expect(results.size).to eq(2)
    end
  end

  describe "#any_event?" do
    before do
      adapter.write(paid_order_event)
      adapter.write(failed_order_event)
    end

    it "returns true when pattern matches" do
      expect(adapter.any_event?(/order/)).to be true
    end

    it "returns false when pattern does not match" do
      expect(adapter.any_event?(/payment/)).to be false
    end

    it "works with string patterns" do
      expect(adapter.any_event?("order.paid")).to be true
    end
  end

  describe "#capabilities" do
    it "supports batching" do
      expect(adapter.capabilities[:batching]).to be true
    end

    it "does not support compression" do
      expect(adapter.capabilities[:compression]).to be false
    end

    it "is not async" do
      expect(adapter.capabilities[:async]).to be false
    end

    it "is not streaming" do
      expect(adapter.capabilities[:streaming]).to be false
    end
  end

  describe "#healthy?" do
    it "returns true" do
      expect(adapter).to be_healthy
    end
  end

  describe "#close" do
    it "does not raise error" do
      expect { adapter.close }.not_to raise_error
    end
  end

  describe "ADR-004 compliance" do
    it "inherits from Base" do
      expect(adapter).to be_a(E11y::Adapters::Base)
    end

    it "implements all required methods" do
      expect(adapter).to respond_to(:write)
      expect(adapter).to respond_to(:write_batch)
      expect(adapter).to respond_to(:healthy?)
      expect(adapter).to respond_to(:close)
      expect(adapter).to respond_to(:capabilities)
    end
  end

  describe "test helper methods" do
    it "provides query methods for testing" do
      expect(adapter).to respond_to(:find_events)
      expect(adapter).to respond_to(:event_count)
      expect(adapter).to respond_to(:last_event)
      expect(adapter).to respond_to(:last_events)
      expect(adapter).to respond_to(:first_events)
      expect(adapter).to respond_to(:events_by_severity)
      expect(adapter).to respond_to(:any_event?)
      expect(adapter).to respond_to(:clear!)
      expect(adapter).to respond_to(:clear)
    end
  end
end
# rubocop:enable RSpec/RepeatedExampleGroupDescription
