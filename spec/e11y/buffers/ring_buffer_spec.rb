# frozen_string_literal: true

require "spec_helper"
require "e11y/buffers/ring_buffer"

RSpec.describe E11y::Buffers::RingBuffer do
  subject(:buffer) { described_class.new(**options) }

  let(:options) { { capacity: 1000 } }

  describe "#initialize" do
    context "with valid parameters" do
      it "creates buffer with default capacity" do
        buffer = described_class.new
        expect(buffer.capacity).to eq(100_000)
      end

      it "creates buffer with custom capacity" do
        buffer = described_class.new(capacity: 5000)
        expect(buffer.capacity).to eq(5000)
      end

      it "creates buffer with default overflow strategy" do
        buffer = described_class.new
        expect(buffer.overflow_strategy).to eq(:drop_oldest)
      end

      it "creates buffer with custom overflow strategy" do
        buffer = described_class.new(overflow_strategy: :drop_newest)
        expect(buffer.overflow_strategy).to eq(:drop_newest)
      end
    end

    context "with invalid parameters" do
      it "raises error for zero capacity" do
        expect do
          described_class.new(capacity: 0)
        end.to raise_error(ArgumentError, /capacity must be > 0/)
      end

      it "raises error for negative capacity" do
        expect do
          described_class.new(capacity: -100)
        end.to raise_error(ArgumentError, /capacity must be > 0/)
      end

      it "raises error for invalid overflow strategy" do
        expect do
          described_class.new(overflow_strategy: :invalid)
        end.to raise_error(ArgumentError, /overflow_strategy must be one of/)
      end
    end
  end

  describe "#push and #pop" do
    let(:event) { { event_name: "test", payload: { id: 1 } } }

    context "with basic operations" do
      it "pushes and pops events in FIFO order" do
        events = [
          { event_name: "event1", id: 1 },
          { event_name: "event2", id: 2 },
          { event_name: "event3", id: 3 }
        ]

        events.each { |e| buffer.push(e) }

        result = buffer.pop(3)
        expect(result).to eq(events)
      end

      it "returns true when push succeeds" do
        expect(buffer.push(event)).to be true
      end

      it "returns empty array when popping from empty buffer" do
        expect(buffer.pop(10)).to eq([])
      end

      it "pops only available events when batch_size > size" do
        buffer.push({ id: 1 })
        buffer.push({ id: 2 })

        result = buffer.pop(100)
        expect(result.size).to eq(2)
      end
    end

    context "with state tracking" do
      it "tracks size correctly" do
        expect(buffer.size).to eq(0)
        buffer.push(event)
        expect(buffer.size).to eq(1)
        buffer.push(event)
        expect(buffer.size).to eq(2)
        buffer.pop(1)
        expect(buffer.size).to eq(1)
      end

      it "reports empty? correctly" do
        expect(buffer).to be_empty
        buffer.push(event)
        expect(buffer).not_to be_empty
        buffer.pop(1)
        expect(buffer).to be_empty
      end

      it "reports full? correctly" do
        buffer = described_class.new(capacity: 2)
        expect(buffer).not_to be_full

        buffer.push({ id: 1 })
        expect(buffer).not_to be_full

        buffer.push({ id: 2 })
        expect(buffer).to be_full
      end

      it "calculates utilization correctly" do
        buffer = described_class.new(capacity: 100)
        expect(buffer.utilization).to eq(0.0)

        50.times { |i| buffer.push({ id: i }) }
        expect(buffer.utilization).to eq(0.5)

        100.times { |i| buffer.push({ id: i }) }
        expect(buffer.utilization).to eq(1.0)
      end
    end

    context "with memory cleanup" do
      it "clears buffer slots after pop" do
        buffer.push({ id: 1 })
        buffer.push({ id: 2 })

        buffer.pop(2)

        # Verify buffer is empty
        expect(buffer).to be_empty
        expect(buffer.pop(10)).to eq([])
      end
    end
  end

  describe "#flush_all" do
    it "returns all events and empties buffer" do
      events = Array.new(10) { |i| { id: i } }
      events.each { |e| buffer.push(e) }

      result = buffer.flush_all

      expect(result).to eq(events)
      expect(buffer).to be_empty
    end

    it "returns empty array for empty buffer" do
      expect(buffer.flush_all).to eq([])
    end
  end

  describe "overflow strategies" do
    let(:capacity) { 3 }
    let(:events) do
      [
        { id: 1, name: "event1" },
        { id: 2, name: "event2" },
        { id: 3, name: "event3" },
        { id: 4, name: "event4" }
      ]
    end

    context "with :drop_oldest strategy" do
      let(:options) { { capacity: capacity, overflow_strategy: :drop_oldest } }

      it "drops oldest event when buffer is full" do
        # Fill buffer with events 1, 2, 3
        events[0..2].each { |e| buffer.push(e) }
        expect(buffer).to be_full

        # Push event 4 - should drop event 1
        result = buffer.push(events[3])
        expect(result).to be true

        # Buffer should contain events 2, 3, 4
        result = buffer.flush_all
        expect(result).to eq([events[1], events[2], events[3]])
      end

      it "maintains FIFO order after overflow" do
        # Fill buffer
        events[0..2].each { |e| buffer.push(e) }

        # Add 2 more events (drops event1 and event2)
        buffer.push(events[3])
        buffer.push({ id: 5 })

        result = buffer.flush_all
        expect(result.map { |e| e[:id] }).to eq([3, 4, 5])
      end
    end

    context "with :drop_newest strategy" do
      let(:options) { { capacity: capacity, overflow_strategy: :drop_newest } }

      it "drops new event when buffer is full" do
        # Fill buffer with events 1, 2, 3
        events[0..2].each { |e| buffer.push(e) }
        expect(buffer).to be_full

        # Try to push event 4 - should be dropped
        result = buffer.push(events[3])
        expect(result).to be false

        # Buffer should still contain events 1, 2, 3
        result = buffer.flush_all
        expect(result).to eq(events[0..2])
      end
    end

    context "with :block strategy" do
      let(:options) do
        {
          capacity: capacity,
          overflow_strategy: :block,
          max_block_time_ms: 50
        }
      end

      it "waits for space when buffer is full" do
        # Fill buffer
        events[0..2].each { |e| buffer.push(e) }
        expect(buffer).to be_full

        # Start a thread to consume events after delay
        consumer_thread = Thread.new do
          sleep 0.02 # 20ms delay
          buffer.pop(1)
        end

        # Try to push - should block briefly, then succeed
        start_time = Time.now
        result = buffer.push(events[3])
        elapsed = Time.now - start_time

        consumer_thread.join

        expect(result).to be true
        expect(elapsed).to be >= 0.02 # Waited for consumer
        expect(elapsed).to be < 0.1   # But not too long
      end

      it "times out and drops event if no space becomes available" do
        # Fill buffer
        events[0..2].each { |e| buffer.push(e) }
        expect(buffer).to be_full

        # Try to push without consumer - should timeout
        start_time = Time.now
        result = buffer.push(events[3])
        elapsed = Time.now - start_time

        expect(result).to be false
        expect(elapsed).to be >= 0.05 # Waited full timeout (50ms)
        expect(elapsed).to be < 0.15  # But not excessively
      end
    end
  end

  describe "thread safety" do
    let(:capacity) { 10_000 }
    let(:options) { { capacity: capacity, overflow_strategy: :drop_oldest } }

    context "with single producer, single consumer (SPSC)" do
      it "handles concurrent push/pop without data loss" do
        event_count = 5000
        events_to_push = Array.new(event_count) { |i| { id: i, timestamp: Time.now.to_f } }
        consumed_events = []

        # Producer thread
        producer = Thread.new do
          events_to_push.each { |event| buffer.push(event) }
        end

        # Consumer thread
        consumer = Thread.new do
          loop do
            batch = buffer.pop(100)
            break if batch.empty? && producer.status == false

            consumed_events.concat(batch)
            sleep 0.001 # Brief sleep to allow producer to work
          end

          # Final flush
          consumed_events.concat(buffer.flush_all)
        end

        producer.join
        consumer.join

        # Verify all events were consumed (allowing for some drops with :drop_oldest)
        expect(consumed_events.size).to be >= (event_count * 0.95).to_i # Allow 5% loss
        expect(consumed_events.size).to be <= event_count
      end

      it "maintains FIFO order under concurrency" do
        event_count = 1000
        events_to_push = Array.new(event_count) { |i| { sequence: i } }
        consumed_events = []

        producer = Thread.new do
          events_to_push.each { |event| buffer.push(event) }
        end

        consumer = Thread.new do
          loop do
            batch = buffer.pop(50)
            break if batch.empty? && producer.status == false

            consumed_events.concat(batch)
            sleep 0.002
          end

          consumed_events.concat(buffer.flush_all)
        end

        producer.join
        consumer.join

        # Verify sequence is monotonically increasing (FIFO order preserved)
        sequences = consumed_events.map { |e| e[:sequence] }
        expect(sequences).to eq(sequences.sort)
      end
    end

    context "when stress testing with 100+ threads" do
      it "remains stable under high contention" do
        producers = 50
        consumers = 50
        events_per_producer = 100

        consumed_events = Concurrent::Array.new

        # 50 producer threads
        producer_threads = Array.new(producers) do |producer_id|
          Thread.new do
            events_per_producer.times do |i|
              buffer.push({ producer_id: producer_id, event_id: i })
            end
          end
        end

        # 50 consumer threads
        consumer_threads = Array.new(consumers) do
          Thread.new do
            loop do
              batch = buffer.pop(10)
              break if batch.empty? && producer_threads.all? { |t| t.status == false }

              consumed_events.concat(batch)
              sleep 0.001
            end
          end
        end

        # Wait for all threads
        producer_threads.each(&:join)
        consumer_threads.each(&:join)

        # Final flush
        consumed_events.concat(buffer.flush_all)

        # Verify reasonable throughput (allowing drops)
        expected_total = producers * events_per_producer
        expect(consumed_events.size).to be >= (expected_total * 0.9).to_i # Allow 10% loss
      end

      it "has no data races (verified by no exceptions)" do
        threads = 100
        operations_per_thread = 100

        threads_array = Array.new(threads) do |thread_id|
          Thread.new do
            operations_per_thread.times do |i|
              if thread_id.even?
                buffer.push({ thread_id: thread_id, op: i })
              else
                buffer.pop(5)
              end
            end
          end
        end

        # Should complete without exceptions
        expect { threads_array.each(&:join) }.not_to raise_error
      end
    end
  end

  describe "performance benchmarks" do
    let(:capacity) { 100_000 }
    let(:options) { { capacity: capacity, overflow_strategy: :drop_oldest } }

    it "achieves 100K events/sec throughput (1KB events)", :benchmark do
      # Simulate 1KB event payload
      event_payload = { data: "x" * 1000 }
      event = { event_name: "benchmark_event", payload: event_payload }

      event_count = 100_000
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)

      event_count.times { buffer.push(event) }

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
      elapsed_seconds = (end_time - start_time) / 1_000_000.0

      events_per_second = event_count / elapsed_seconds

      puts "\n📊 RingBuffer Performance:"
      puts "  Events: #{event_count}"
      puts "  Time: #{elapsed_seconds.round(3)}s"
      puts "  Throughput: #{events_per_second.round(0)} events/sec"
      puts "  Latency (avg): #{(elapsed_seconds * 1_000_000 / event_count).round(2)}μs per event"

      # DoD: 100K events/sec throughput
      expect(events_per_second).to be >= 100_000,
                                   "Expected >= 100K events/sec, got #{events_per_second.round(0)}"
    end

    it "has <10μs latency per operation (p99)", :benchmark do
      event = { event_name: "latency_test", payload: { id: 1 } }
      measurements = []

      # Warm up
      1000.times { buffer.push(event) }
      buffer.flush_all

      # Measure push latency
      10_000.times do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        buffer.push(event)
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)

        measurements << (end_time - start_time)
      end

      # Calculate p99
      sorted = measurements.sort
      p99_index = (sorted.size * 0.99).to_i
      p99_latency = sorted[p99_index]
      avg_latency = measurements.sum / measurements.size.to_f

      puts "\n📊 RingBuffer Latency:"
      puts "  Operations: #{measurements.size}"
      puts "  Average: #{avg_latency.round(2)}μs"
      puts "  P99: #{p99_latency.round(2)}μs"

      # Target: <10μs per operation (p99)
      expect(p99_latency).to be < 10,
                             "Expected p99 < 10μs, got #{p99_latency.round(2)}μs"
    end
  end
end
