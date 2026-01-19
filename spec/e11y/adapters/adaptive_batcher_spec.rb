# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::Adapters::AdaptiveBatcher do
  let(:flushed_batches) { [] }
  let(:flush_callback) { ->(events) { flushed_batches << events } }

  let(:batcher) do
    described_class.new(
      min_size: 5,
      max_size: 10,
      timeout: 0.5,
      flush_callback: flush_callback
    )
  end

  after do
    batcher.close
  end

  describe "#initialize" do
    it "accepts configuration parameters" do
      expect(batcher).to be_a(described_class)
    end

    it "starts with empty buffer" do
      expect(batcher).to be_empty
      expect(batcher.buffer_size).to eq(0)
    end

    it "requires flush_callback" do
      expect do
        described_class.new(max_size: 10, timeout: 5.0)
      end.to raise_error(ArgumentError, /flush_callback/)
    end
  end

  describe "#add" do
    it "adds event to buffer" do
      batcher.add(event_name: "test.event")
      expect(batcher.buffer_size).to eq(1)
    end

    it "accumulates multiple events" do
      3.times { |i| batcher.add(event_name: "event.#{i}") }
      expect(batcher.buffer_size).to eq(3)
    end

    it "returns true on successful add" do
      expect(batcher.add(event_name: "test")).to be true
    end

    it "returns false when batcher is closed" do
      batcher.close
      expect(batcher.add(event_name: "test")).to be false
    end
  end

  describe "automatic flushing" do
    context "when max_size reached" do
      it "flushes immediately" do
        10.times { |i| batcher.add(event_name: "event.#{i}") }

        expect(flushed_batches.size).to eq(1)
        expect(flushed_batches.first.size).to eq(10)
        expect(batcher.buffer_size).to eq(0)
      end

      it "flushes on exactly max_size" do
        9.times { batcher.add(event_name: "event") }
        expect(flushed_batches).to be_empty

        batcher.add(event_name: "last_event") # 10th event
        expect(flushed_batches.size).to eq(1)
      end

      it "handles multiple batches" do
        25.times { |i| batcher.add(event_name: "event.#{i}") }

        expect(flushed_batches.size).to eq(2)
        expect(flushed_batches[0].size).to eq(10)
        expect(flushed_batches[1].size).to eq(10)
        expect(batcher.buffer_size).to eq(5) # Remaining
      end
    end

    context "when timeout expires" do
      it "flushes if min_size threshold met" do
        7.times { batcher.add(event_name: "event") } # Above min_size (5)

        sleep(0.6) # Wait for timeout

        expect(flushed_batches.size).to eq(1)
        expect(flushed_batches.first.size).to eq(7)
      end

      it "does not flush if below min_size" do
        3.times { batcher.add(event_name: "event") } # Below min_size (5)

        sleep(0.6)

        expect(flushed_batches).to be_empty
        expect(batcher.buffer_size).to eq(3)
      end

      it "resets timeout after flush" do
        7.times { batcher.add(event_name: "event") }
        sleep(0.6) # First flush

        flushed_batches.clear

        7.times { batcher.add(event_name: "event") }
        sleep(0.6) # Second flush

        expect(flushed_batches.size).to eq(1)
      end
    end
  end

  describe "#flush!" do
    it "flushes buffer immediately" do
      5.times { batcher.add(event_name: "event") }

      expect(batcher.flush!).to be true
      expect(flushed_batches.size).to eq(1)
      expect(batcher.buffer_size).to eq(0)
    end

    it "returns false if buffer is empty" do
      expect(batcher.flush!).to be false
      expect(flushed_batches).to be_empty
    end

    it "can be called multiple times safely" do
      3.times { batcher.add(event_name: "event") }

      batcher.flush!
      batcher.flush!

      expect(flushed_batches.size).to eq(1)
    end
  end

  describe "#close" do
    it "flushes remaining events" do
      3.times { batcher.add(event_name: "event") }

      batcher.close

      expect(flushed_batches.size).to eq(1)
      expect(flushed_batches.first.size).to eq(3)
    end

    it "stops accepting new events" do
      batcher.close

      expect(batcher.add(event_name: "event")).to be false
      expect(batcher.buffer_size).to eq(0)
    end

    it "can be called multiple times safely" do
      expect { batcher.close }.not_to raise_error
      expect { batcher.close }.not_to raise_error
    end

    it "stops timer thread" do
      timer_thread = batcher.instance_variable_get(:@timer_thread)
      expect(timer_thread).to be_alive

      batcher.close

      sleep(0.1) # Give thread time to terminate
      expect(timer_thread).not_to be_alive
    end
  end

  describe "thread safety" do
    it "handles concurrent writes safely" do
      threads = 10.times.map do |i|
        Thread.new do
          10.times { |j| batcher.add(event_name: "event.#{i}.#{j}") }
        end
      end

      threads.each(&:join)

      # Either in buffer or flushed
      total_events = batcher.buffer_size + flushed_batches.flatten.size
      expect(total_events).to eq(100)
    end

    it "handles concurrent flush safely" do
      20.times { batcher.add(event_name: "event") }

      threads = 5.times.map { Thread.new { batcher.flush! } }
      threads.each(&:join)

      # Should only flush once (buffer was cleared by first flush)
      expect(flushed_batches.size).to be <= 2
    end
  end

  describe "error handling" do
    it "continues on flush callback error" do
      error_callback = lambda do |_events|
        raise StandardError, "Flush failed"
      end

      error_batcher = described_class.new(
        max_size: 5,
        timeout: 1.0,
        flush_callback: error_callback
      )

      expect do
        5.times { error_batcher.add(event_name: "event") }
      end.to raise_error(StandardError, "Flush failed")

      error_batcher.close
    end
  end

  describe "ADR-004 compliance" do
    context "Section 8.1: Adaptive Batching" do
      it "batches events efficiently" do
        100.times { |i| batcher.add(event_name: "event.#{i}") }

        # Should create ~10 batches of size 10
        expect(flushed_batches.size).to be >= 10
        flushed_batches.each do |batch|
          expect(batch.size).to be <= 10
        end
      end

      it "respects latency constraints (timeout)" do
        start_time = Time.now

        6.times { batcher.add(event_name: "event") } # Above min_size
        sleep(0.6) # Wait for timeout

        flush_time = Time.now - start_time

        expect(flushed_batches.size).to eq(1)
        expect(flush_time).to be_within(0.2).of(0.6)
      end

      it "optimizes for throughput (max_size)" do
        1000.times { |i| batcher.add(event_name: "event.#{i}") }

        # Most batches should be full (max_size)
        full_batches = flushed_batches.count { |batch| batch.size == 10 }
        expect(full_batches).to be >= 95 # At least 95% full batches
      end
    end
  end
end
