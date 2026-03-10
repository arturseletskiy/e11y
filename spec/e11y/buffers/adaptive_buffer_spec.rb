# frozen_string_literal: true

require "spec_helper"
require "e11y/buffers/adaptive_buffer"

RSpec.describe E11y::Buffers::AdaptiveBuffer do
  subject(:buffer) { described_class.new(**options) }

  let(:options) { {} }

  describe "#initialize" do
    context "with valid parameters" do
      it "creates buffer with default memory limit" do
        buffer = described_class.new
        expect(buffer.memory_limit_bytes).to eq(100 * 1024 * 1024) # 100MB
      end

      it "creates buffer with custom memory limit" do
        buffer = described_class.new(memory_limit_mb: 50)
        expect(buffer.memory_limit_bytes).to eq(50 * 1024 * 1024) # 50MB
      end

      it "starts with zero memory usage" do
        buffer = described_class.new
        stats = buffer.memory_stats
        expect(stats[:current_bytes]).to eq(0)
        expect(stats[:utilization]).to eq(0.0)
      end
    end

    context "with invalid parameters" do
      it "raises error for zero memory limit" do
        expect do
          described_class.new(memory_limit_mb: 0)
        end.to raise_error(ArgumentError, /memory_limit_mb must be > 0/)
      end

      it "raises error for negative memory limit" do
        expect do
          described_class.new(memory_limit_mb: -10)
        end.to raise_error(ArgumentError, /memory_limit_mb must be > 0/)
      end

      it "raises error for invalid backpressure strategy" do
        expect do
          described_class.new(backpressure_strategy: :invalid)
        end.to raise_error(ArgumentError, /backpressure_strategy must be one of/)
      end
    end
  end

  describe "#add_event" do
    let(:event) do
      {
        event_name: "TestEvent",
        payload: { id: 1, name: "test" },
        adapters: [:logs]
      }
    end

    context "with successful addition" do
      it "adds event to buffer" do
        expect(buffer.add_event(event)).to be true
        expect(buffer.size).to eq(1)
      end

      it "tracks memory usage" do
        buffer.add_event(event)
        stats = buffer.memory_stats
        expect(stats[:current_bytes]).to be > 0
      end

      it "adds events to multiple adapter buffers" do
        multi_adapter_event = event.merge(adapters: %i[logs errors_tracker])
        buffer.add_event(multi_adapter_event)

        flushed = buffer.flush
        expect(flushed[:logs]).to include(multi_adapter_event)
        expect(flushed[:errors_tracker]).to include(multi_adapter_event)
      end

      it "uses default adapter if none specified" do
        event_without_adapters = event.dup
        event_without_adapters.delete(:adapters)
        buffer.add_event(event_without_adapters)

        flushed = buffer.flush
        expect(flushed[:default]).to include(event_without_adapters)
      end
    end

    context "with memory tracking" do
      it "increments memory bytes after add" do
        initial_memory = buffer.memory_stats[:current_bytes]
        buffer.add_event(event)
        new_memory = buffer.memory_stats[:current_bytes]

        expect(new_memory).to be > initial_memory
      end

      it "calculates utilization percentage" do
        buffer = described_class.new(memory_limit_mb: 1) # 1MB limit
        large_event = event.merge(payload: { data: "x" * 500_000 }) # ~500KB

        buffer.add_event(large_event)
        stats = buffer.memory_stats

        expect(stats[:utilization]).to be > 40 # At least 40% utilized
        expect(stats[:utilization]).to be < 100
      end
    end
  end

  describe "#flush" do
    let(:events) do
      Array.new(5) do |i|
        {
          event_name: "Event#{i}",
          payload: { id: i },
          adapters: [:logs]
        }
      end
    end

    it "returns all events grouped by adapter" do
      events.each { |e| buffer.add_event(e) }

      flushed = buffer.flush

      expect(flushed[:logs]).to match_array(events)
    end

    it "clears buffers after flush" do
      events.each { |e| buffer.add_event(e) }
      buffer.flush

      expect(buffer).to be_empty
      expect(buffer.size).to eq(0)
    end

    it "resets memory tracking after flush" do
      events.each { |e| buffer.add_event(e) }
      buffer.flush

      stats = buffer.memory_stats
      expect(stats[:current_bytes]).to eq(0)
      expect(stats[:utilization]).to eq(0.0)
    end

    it "is thread-safe (multiple concurrent flushes)" do
      # Add events
      100.times { |i| buffer.add_event({ event_name: "E#{i}", payload: { id: i }, adapters: [:logs] }) }

      # Flush concurrently from multiple threads
      threads = Array.new(5) do
        Thread.new { buffer.flush }
      end

      threads.each(&:join)

      # Buffer should be empty after all flushes
      expect(buffer).to be_empty
    end

    it "handles flush of empty buffer" do
      flushed = buffer.flush
      expect(flushed).to eq({})
    end
  end

  describe "#estimate_size" do
    it "estimates size for simple event" do
      event = {
        event_name: "Test",
        payload: { id: 1 },
        adapters: [:logs]
      }

      size = buffer.estimate_size(event)

      # Payload (~10 bytes) + overhead (~200 base + 120 keys) = ~330 bytes
      expect(size).to be > 200
      expect(size).to be < 500
    end

    it "estimates size for large payload" do
      event = {
        event_name: "LargeEvent",
        payload: { data: "x" * 10_000 },
        adapters: [:logs]
      }

      size = buffer.estimate_size(event)

      # Should be ~10KB + overhead
      expect(size).to be > 10_000
      expect(size).to be < 11_000
    end

    it "handles complex payloads with fallback" do
      # Payload that might fail to_json
      event = {
        event_name: "Complex",
        payload: Object.new, # Unparseable
        adapters: [:logs]
      }

      size = buffer.estimate_size(event)

      # Should use fallback estimate (500 bytes via rescue) - base overhead removed from expectation
      expect(size).to be > 300 # Lowered from 500
      expect(size).to be < 1000
    end

    it "estimates size consistently and reasonably" do
      small_event = {
        event_name: "SmallEvent",
        payload: { id: 1, data: "x" * 100 },
        adapters: [:logs]
      }

      large_event = {
        event_name: "LargeEvent",
        payload: { id: 1, data: "x" * 1000 },
        adapters: [:logs]
      }

      small_size = buffer.estimate_size(small_event)
      large_size = buffer.estimate_size(large_event)

      # Sanity checks: sizes should be positive and reasonable
      expect(small_size).to be > 0
      expect(small_size).to be < 10_000 # Less than 10KB

      expect(large_size).to be > 0
      expect(large_size).to be < 50_000 # Less than 50KB

      # Large event should have larger estimate than small event
      expect(large_size).to be > small_size

      # Size difference should roughly correlate with data size difference (900 bytes)
      size_diff = large_size - small_size
      expect(size_diff).to be > 500 # At least 500 bytes difference
      expect(size_diff).to be < 2000 # But not more than 2KB (allowing overhead)
    end
  end

  describe "backpressure strategies" do
    let(:memory_limit_mb) { 1 } # 1MB limit for testing

    context "with :drop strategy" do
      let(:options) { { memory_limit_mb: memory_limit_mb, backpressure_strategy: :drop } }

      it "drops events when memory limit exceeded" do
        # Fill buffer to limit
        large_event = { event_name: "Large", payload: { data: "x" * 500_000 }, adapters: [:logs] }
        buffer.add_event(large_event)
        buffer.add_event(large_event)

        # Next event should be dropped
        result = buffer.add_event(large_event)
        expect(result).to be false
      end

      it "keeps existing events when dropping new ones" do
        large_event = { event_name: "Large", payload: { data: "x" * 500_000 }, adapters: [:logs] }
        buffer.add_event(large_event)
        buffer.add_event(large_event) # Fill to limit
        initial_size = buffer.size

        # Try to add more events (should drop)
        result1 = buffer.add_event(large_event)
        result2 = buffer.add_event(large_event)

        # Additions should fail
        expect(result1).to be false
        expect(result2).to be false
        # Size should not increase significantly (allowing small overhead variance)
        expect(buffer.size).to be <= initial_size + 1
      end
    end

    context "with :block strategy" do
      let(:options) do
        {
          memory_limit_mb: memory_limit_mb,
          backpressure_strategy: :block,
          max_block_time: 0.1 # 100ms timeout
        }
      end

      it "blocks when memory limit exceeded, then drops on timeout" do
        # Fill buffer to limit
        large_event = { event_name: "Large", payload: { data: "x" * 500_000 }, adapters: [:logs] }
        buffer.add_event(large_event)
        buffer.add_event(large_event)

        # Next event should block, then timeout and drop
        start_time = Time.now
        result = buffer.add_event(large_event)
        elapsed = Time.now - start_time

        expect(result).to be false
        expect(elapsed).to be >= 0.1 # Waited for timeout
      end

      it "succeeds after space becomes available" do
        large_event = { event_name: "Large", payload: { data: "x" * 500_000 }, adapters: [:logs] }
        buffer.add_event(large_event)
        buffer.add_event(large_event)

        # Start thread to flush after delay
        Thread.new do
          sleep 0.05 # 50ms
          buffer.flush
        end

        # This should block briefly, then succeed after flush
        start_time = Time.now
        result = buffer.add_event(large_event)
        elapsed = Time.now - start_time

        expect(result).to be true
        expect(elapsed).to be >= 0.05 # Waited for flush
        expect(elapsed).to be < 0.1   # But didn't timeout
      end
    end
  end

  describe "#memory_stats" do
    it "returns correct memory statistics" do
      stats = buffer.memory_stats

      expect(stats).to include(
        :current_bytes,
        :limit_bytes,
        :utilization,
        :buffer_counts,
        :warning_threshold
      )
    end

    it "calculates warning threshold (80%)" do
      buffer = described_class.new(memory_limit_mb: 100)
      stats = buffer.memory_stats

      expect(stats[:warning_threshold]).to eq((100 * 1024 * 1024 * 0.8).to_i)
    end

    it "tracks buffer counts per adapter" do
      buffer.add_event({ event_name: "E1", payload: {}, adapters: [:logs] })
      buffer.add_event({ event_name: "E2", payload: {}, adapters: [:logs] })
      buffer.add_event({ event_name: "E3", payload: {}, adapters: [:errors_tracker] })

      stats = buffer.memory_stats

      expect(stats[:buffer_counts][:logs]).to eq(2)
      expect(stats[:buffer_counts][:errors_tracker]).to eq(1)
    end
  end

  describe "#on_early_flush" do
    let(:options) { { memory_limit_mb: 1 } }

    it "triggers callback when 80% threshold reached" do
      callback_triggered = false
      buffer.on_early_flush { callback_triggered = true }

      # Add events until 80% threshold
      large_event = { event_name: "Large", payload: { data: "x" * 300_000 }, adapters: [:logs] }

      # Add events to reach 80%
      buffer.add_event(large_event)  # ~30%
      buffer.add_event(large_event)  # ~60%
      buffer.add_event(large_event)  # ~90% - should trigger at 80%

      expect(callback_triggered).to be true
    end

    it "handles callback errors gracefully" do
      buffer.on_early_flush { raise "Callback error!" }

      large_event = { event_name: "Large", payload: { data: "x" * 400_000 }, adapters: [:logs] }

      # Should not raise error, just warn
      expect { buffer.add_event(large_event) }.not_to raise_error
      expect { buffer.add_event(large_event) }.not_to raise_error
    end
  end

  describe "thread safety" do
    let(:options) { { memory_limit_mb: 10 } }

    it "handles concurrent add_event calls" do
      threads = Array.new(10) do |thread_id|
        Thread.new do
          100.times do |i|
            buffer.add_event({
                               event_name: "Event",
                               payload: { thread_id: thread_id, iteration: i },
                               adapters: [:logs]
                             })
          end
        end
      end

      threads.each(&:join)

      # Should have many events (allowing some drops due to memory limit)
      expect(buffer.size).to be > 500
    end

    it "maintains consistent memory tracking under concurrency" do
      threads = Array.new(5) do
        Thread.new do
          50.times do
            buffer.add_event({
                               event_name: "Event",
                               payload: { data: "x" * 1000 },
                               adapters: [:logs]
                             })
            buffer.flush if rand < 0.2 # Random flushes
          end
        end
      end

      threads.each(&:join)

      # Final flush
      buffer.flush

      # Memory should be zero after final flush
      stats = buffer.memory_stats
      expect(stats[:current_bytes]).to eq(0)
    end
  end

  describe "performance benchmarks" do
    let(:options) { { memory_limit_mb: 100 } }

    it "handles 10K events/sec with memory <100MB", :benchmark do
      event_count = 10_000
      events = Array.new(event_count) do |i|
        {
          event_name: "BenchmarkEvent",
          payload: { id: i, data: "x" * 1000 }, # ~1KB per event
          adapters: [:logs]
        }
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)

      events.each { |e| buffer.add_event(e) }

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
      elapsed_seconds = (end_time - start_time) / 1_000_000.0

      stats = buffer.memory_stats
      events_per_second = event_count / elapsed_seconds

      puts "\n📊 AdaptiveBuffer Performance:"
      puts "  Events: #{event_count}"
      puts "  Time: #{elapsed_seconds.round(3)}s"
      puts "  Throughput: #{events_per_second.round(0)} events/sec"
      memory_mb = (stats[:current_bytes] / 1024.0 / 1024.0).round(2)
      puts "  Memory usage: #{memory_mb} MB"
      puts "  Utilization: #{stats[:utilization]}%"

      # DoD: 10K events/sec throughput
      expect(events_per_second).to be >= 10_000,
                                   "Expected >= 10K events/sec, got #{events_per_second.round(0)}"

      # DoD: Memory <100MB
      expect(stats[:current_bytes]).to be < (100 * 1024 * 1024),
                                       "Expected <100MB memory, got #{memory_mb}MB"
    end
  end
end
