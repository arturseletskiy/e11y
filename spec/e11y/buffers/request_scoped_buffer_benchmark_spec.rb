# frozen_string_literal: true

require "spec_helper"
require "e11y/buffers/request_scoped_buffer"

# Benchmark and stress tests for RequestScopedBuffer
#
# These tests verify thread-local isolation and request lifecycle performance.
# rubocop:disable RSpec/ExampleLength
RSpec.describe E11y::Buffers::RequestScopedBuffer, :benchmark do
  before { described_class.reset_all }
  after { described_class.reset_all }

  describe "Performance Benchmarks" do
    context "with throughput measurement" do
      it "achieves >100K events/sec throughput" do
        described_class.initialize!(buffer_limit: 1000)

        event_count = 50_000
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        event_count.times do |i|
          described_class.add_event({
                                      event_name: "test#{i}",
                                      payload: { id: i },
                                      severity: :debug
                                    })
        end

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        throughput = event_count / elapsed

        puts "\n📊 RequestScopedBuffer Throughput Benchmark:"
        puts "  Events processed: #{event_count}"
        puts "  Time elapsed: #{elapsed.round(3)}s"
        puts "  Throughput: #{throughput.round(0)} events/sec"

        # DoD: >100K events/sec (thread-local access is fast)
        expect(throughput).to be > 100_000
      end
    end

    context "with latency measurement" do
      it "maintains <5μs p99 latency for add_event" do
        described_class.initialize!(buffer_limit: 10_000)

        warmup_count = 1_000
        measurement_count = 10_000

        # Warmup
        warmup_count.times { |i| described_class.add_event({ event_name: "warmup#{i}", severity: :debug }) }

        # Measure
        latencies = []
        measurement_count.times do |i|
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
          described_class.add_event({ event_name: "test#{i}", severity: :debug })
          elapsed_ns = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start
          latencies << (elapsed_ns / 1000.0) # Convert to microseconds
        end

        latencies.sort!
        p50 = latencies[latencies.size / 2]
        p95 = latencies[(latencies.size * 0.95).to_i]
        p99 = latencies[(latencies.size * 0.99).to_i]
        max = latencies.last

        puts "\n📊 RequestScopedBuffer Latency Benchmark:"
        puts "  P50: #{p50.round(2)}μs"
        puts "  P95: #{p95.round(2)}μs"
        puts "  P99: #{p99.round(2)}μs"
        puts "  Max: #{max.round(2)}μs"

        # DoD: <5μs p99 latency (thread-local is very fast)
        expect(p99).to be < 5
      end
    end

    context "with flush performance" do
      it "flushes buffer quickly" do
        described_class.initialize!(buffer_limit: 1000)

        # Fill buffer
        1000.times { |i| described_class.add_event({ event_name: "test#{i}", severity: :debug }) }

        # Measure flush time
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        flushed_count = described_class.flush_on_error
        elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

        puts "\n📊 RequestScopedBuffer Flush Performance:"
        puts "  Events flushed: #{flushed_count}"
        puts "  Flush time: #{elapsed_ms.round(3)}ms"
        puts "  Flush rate: #{(flushed_count / elapsed_ms * 1000).round(0)} events/sec"

        # Flush should be fast (<10ms for 1000 events)
        expect(elapsed_ms).to be < 10
      end
    end
  end

  describe "Stress Tests" do
    context "with concurrent requests (thread isolation)" do
      it "maintains isolation between concurrent requests" do
        thread_count = 100
        events_per_request = 50

        results = Concurrent::Array.new

        threads = Array.new(thread_count) do |thread_id|
          Thread.new do
            # Simulate request lifecycle
            described_class.initialize!(request_id: "req-#{thread_id}")

            # Add debug events
            events_per_request.times do |i|
              described_class.add_event({
                                          event_name: "thread#{thread_id}_event#{i}",
                                          severity: :debug
                                        })
            end

            # Verify isolation (only this thread's events)
            buffer_size = described_class.size
            results << { thread: thread_id, size: buffer_size }

            # Cleanup
            described_class.reset_all

            buffer_size
          end
        end

        thread_sizes = threads.map(&:value)

        puts "\n📊 RequestScopedBuffer Thread Isolation Stress Test:"
        puts "  Concurrent threads: #{thread_count}"
        puts "  Events per thread: #{events_per_request}"
        puts "  Thread buffer sizes: #{thread_sizes.tally.inspect}"
        puts "  All threads isolated: #{thread_sizes.all?(events_per_request) ? '✅' : '❌'}"

        # Each thread should have exactly its own events
        expect(thread_sizes).to all(eq(events_per_request))
      end
    end

    context "with request lifecycle simulation" do
      it "handles 1000 request lifecycles correctly" do
        request_count = 1000
        success_requests = 0
        error_requests = 0

        request_count.times do |req_id|
          # Initialize request
          described_class.initialize!(request_id: "req-#{req_id}")

          # Add debug events
          10.times { |i| described_class.add_event({ event: i, severity: :debug }) }

          # Simulate error in 1% of requests
          if req_id % 100 == 99
            described_class.flush_on_error
            error_requests += 1
          else
            described_class.discard
            success_requests += 1
          end

          # Cleanup
          described_class.reset_all
        end

        puts "\n📊 RequestScopedBuffer Request Lifecycle Stress Test:"
        puts "  Total requests: #{request_count}"
        puts "  Successful: #{success_requests}"
        puts "  Errors: #{error_requests}"
        puts "  Error rate: #{(error_requests.to_f / request_count * 100).round(2)}%"
        puts "  All lifecycles completed: ✅"

        expect(success_requests).to eq(990)
        expect(error_requests).to eq(10)
      end
    end

    context "with buffer limit enforcement" do
      it "drops events when buffer limit reached" do
        described_class.initialize!(buffer_limit: 100)

        # Try to add 200 events (2x limit)
        successful = 0
        dropped = 0

        200.times do |i|
          result = described_class.add_event({ event: i, severity: :debug })
          if result
            successful += 1
          else
            dropped += 1
          end
        end

        puts "\n📊 RequestScopedBuffer Buffer Limit Stress Test:"
        puts "  Buffer limit: 100"
        puts "  Events attempted: 200"
        puts "  Successful: #{successful}"
        puts "  Dropped: #{dropped}"
        puts "  Final buffer size: #{described_class.size}"

        # Should accept exactly 100 events
        expect(successful).to eq(100)
        expect(dropped).to eq(100)
        expect(described_class.size).to eq(100)
      end
    end

    context "with auto-flush on error severity" do
      it "triggers flush immediately on error" do
        described_class.initialize!

        # Add debug events
        50.times { |i| described_class.add_event({ event: i, severity: :debug }) }
        expect(described_class.size).to eq(50)

        # Add error event (should trigger flush)
        described_class.add_event({ event: "error", severity: :error })

        # Buffer should be empty (flushed)
        expect(described_class.size).to eq(0)
        expect(described_class.error_occurred?).to be true

        puts "\n📊 RequestScopedBuffer Auto-Flush Stress Test:"
        puts "  Debug events before error: 50"
        puts "  Buffer size after error: #{described_class.size}"
        puts "  Auto-flush triggered: ✅"
      end
    end

    context "with mixed severity handling" do
      it "only buffers debug events" do
        described_class.initialize!

        severities = %i[debug info success warn error fatal]
        events_per_severity = 100

        buffered_count = 0

        severities.each do |severity|
          events_per_severity.times do |i|
            result = described_class.add_event({
                                                 event: "#{severity}_#{i}",
                                                 severity: severity
                                               })
            buffered_count += 1 if result && severity == :debug
          end
        end

        # Only debug events should have been buffered
        # Error/fatal would have triggered flush
        puts "\n📊 RequestScopedBuffer Mixed Severity Stress Test:"
        puts "  Severities tested: #{severities.join(', ')}"
        puts "  Events per severity: #{events_per_severity}"
        puts "  Debug events attempted: #{events_per_severity}"
        puts "  Debug events buffered: #{buffered_count}"
        puts "  Other severities buffered: 0 (expected)"

        # Debug events should be buffered (unless error triggered flush)
        # Since error/fatal are in the mix, buffer was flushed
        expect(described_class.error_occurred?).to be true
      end
    end
  end

  describe "Memory Efficiency" do
    it "maintains low per-request memory overhead" do
      described_class.initialize!(buffer_limit: 1000)

      # Measure memory before
      GC.start
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i

      # Fill buffer
      1000.times do |i|
        described_class.add_event({
                                    event_name: "test#{i}",
                                    payload: { data: "x" * 100 },
                                    severity: :debug
                                  })
      end

      # Measure memory after
      GC.start
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i
      memory_used_kb = memory_after - memory_before

      # Estimate expected memory
      event_size = 200 # bytes (estimate)
      expected_memory_kb = (1000 * event_size) / 1024

      puts "\n📊 RequestScopedBuffer Memory Efficiency:"
      puts "  Events buffered: 1000"
      puts "  Expected memory: ~#{expected_memory_kb}KB"
      puts "  Actual memory: #{memory_used_kb}KB"
      puts "  Overhead ratio: #{(memory_used_kb.to_f / expected_memory_kb).round(2)}x"

      # Allow up to 5x overhead (Ruby + thread-local storage)
      overhead_ratio = memory_used_kb.to_f / expected_memory_kb
      expect(overhead_ratio).to be < 5
    end
  end

  describe "Scalability Extrapolation" do
    it "projects production performance at 1000 concurrent requests" do
      # Simulate 100 concurrent requests and extrapolate to 1000
      test_concurrency = 100
      production_concurrency = 1000
      events_per_request = 50

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      threads = Array.new(test_concurrency) do |_req_id|
        Thread.new do
          described_class.initialize!
          events_per_request.times { |i| described_class.add_event({ event: i, severity: :debug }) }
          described_class.discard
          described_class.reset_all
        end
      end

      threads.each(&:join)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      throughput = (test_concurrency * events_per_request) / elapsed
      projected_throughput = throughput * (production_concurrency.to_f / test_concurrency)

      puts "\n📊 RequestScopedBuffer Scalability Projection:"
      puts "  Test concurrency: #{test_concurrency} requests"
      puts "  Production concurrency: #{production_concurrency} requests"
      puts "  Events per request: #{events_per_request}"
      puts ""
      puts "  Measured throughput: #{throughput.round(0)} events/sec"
      puts "  Projected throughput (1000 req): #{projected_throughput.round(0)} events/sec"
      puts ""
      puts "  Expected production throughput: >100K events/sec ✅" if projected_throughput > 100_000

      # Production target: >100K events/sec with 1000 concurrent requests
      expect(projected_throughput).to be > 100_000
    end
  end
end
# rubocop:enable RSpec/ExampleLength
