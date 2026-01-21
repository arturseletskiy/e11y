#!/usr/bin/env ruby
# frozen_string_literal: true

# E11y Performance Benchmark Suite
#
# Tests performance at 3 scale levels:
# - Small: 1K events/sec
# - Medium: 10K events/sec
# - Large: 100K events/sec
#
# Run:
#   bundle exec ruby benchmarks/e11y_benchmarks.rb
#
# Run specific scale:
#   SCALE=small bundle exec ruby benchmarks/e11y_benchmarks.rb
#
# ADR-001 §5: Performance Requirements

require "bundler/setup"
require "benchmark"
require "benchmark/ips"
require "memory_profiler"
require "e11y"

# ============================================================================
# Configuration
# ============================================================================

SCALE = (ENV["SCALE"] || "all").downcase
WARMUP_TIME = 2 # seconds
BENCHMARK_TIME = 5 # seconds

# Performance targets
TARGETS = {
  small: {
    name: "Small Scale (1K events/sec)",
    track_latency_p99_us: 50, # <50μs p99
    buffer_throughput: 10_000,      # 10K events/sec
    memory_mb: 100,                 # <100MB
    cpu_percent: 5                  # <5%
  },
  medium: {
    name: "Medium Scale (10K events/sec)",
    track_latency_p99_us: 1000, # <1ms p99
    buffer_throughput: 50_000,      # 50K events/sec
    memory_mb: 500,                 # <500MB
    cpu_percent: 10                 # <10%
  },
  large: {
    name: "Large Scale (100K events/sec)",
    track_latency_p99_us: 5000, # <5ms p99
    buffer_throughput: 100_000,     # 100K events/sec (per process)
    memory_mb: 2000,                # <2GB
    cpu_percent: 15                 # <15%
  }
}.freeze

# ============================================================================
# Test Event Classes
# ============================================================================

class BenchmarkEvent < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:action).filled(:string)
    required(:timestamp).filled(:time)
  end
end

class SimpleBenchmarkEvent < E11y::Event::Base
  schema do
    required(:value).filled(:integer)
  end
end

# ============================================================================
# Helper Methods
# ============================================================================

def setup_e11y(buffer_size: 10_000)
  E11y.configure do |config|
    config.enabled = true

    # Use InMemory adapter for clean benchmarks (no I/O overhead)
    config.adapters = [
      E11y::Adapters::InMemory.new
    ]
  end
end

def measure_track_latency(event_class:, count:, scale_name:)
  latencies = []

  count.times do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    event_class.track(
      user_id: "user_#{rand(1000)}",
      action: "test_action",
      timestamp: Time.now
    )
    finish = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    latencies << (finish - start)
  end

  latencies.sort!
  p50_index = (count * 0.5).to_i
  p99_index = (count * 0.99).to_i
  p999_index = (count * 0.999).to_i

  {
    p50: latencies[p50_index],
    p99: latencies[p99_index],
    p999: latencies[p999_index],
    min: latencies.first,
    max: latencies.last,
    mean: (latencies.sum / count.to_f)
  }
end

def measure_buffer_throughput(event_class:, duration_sec:)
  count = 0
  start_time = Time.now

  while Time.now - start_time < duration_sec
    event_class.track(value: count)
    count += 1
  end

  actual_duration = Time.now - start_time
  throughput = (count / actual_duration).round

  { count: count, duration: actual_duration, throughput: throughput }
end

def measure_memory_usage(event_count:)
  GC.start # Clean slate

  report = MemoryProfiler.report do
    event_count.times do |i|
      SimpleBenchmarkEvent.track(value: i)
    end
  end

  memory_mb = (report.total_allocated_memsize / 1024.0 / 1024.0).round(2)
  memory_per_event_kb = ((report.total_allocated_memsize / event_count.to_f) / 1024.0).round(2)

  {
    total_mb: memory_mb,
    per_event_kb: memory_per_event_kb,
    total_allocated: report.total_allocated,
    total_retained: report.total_retained
  }
end

def print_header(scale_name)
  puts "\n"
  puts "=" * 80
  puts "  #{TARGETS[scale_name][:name]}"
  puts "=" * 80
  puts ""
end

def print_result(name, value, unit, target, passed)
  status = passed ? "✅ PASS" : "❌ FAIL"
  target_str = target ? "(target: #{target}#{unit})" : ""
  puts "  #{name.ljust(30)} #{value}#{unit} #{target_str} #{status}"
end

def print_summary(results)
  puts "\n"
  puts "=" * 80
  puts "  SUMMARY"
  puts "=" * 80

  results.each do |scale, data|
    puts "\n#{TARGETS[scale][:name]}:"
    puts "  Total checks: #{data[:total]}"
    puts "  Passed: #{data[:passed]} ✅"
    puts "  Failed: #{data[:failed]} ❌"
    puts "  Status: #{data[:passed] == data[:total] ? '✅ ALL PASS' : '❌ SOME FAILED'}"
  end
end

# ============================================================================
# Benchmark Suite
# ============================================================================

def run_small_scale_benchmark
  scale = :small
  print_header(scale)

  setup_e11y(buffer_size: 1000)

  results = { total: 0, passed: 0, failed: 0 }

  # 1. track() Latency
  puts "📊 Benchmark: track() Latency (1000 iterations)"
  latency = measure_track_latency(
    event_class: BenchmarkEvent,
    count: 1000,
    scale_name: scale
  )

  target_p99 = TARGETS[scale][:track_latency_p99_us]
  passed_p99 = latency[:p99] <= target_p99

  puts "  p50:  #{latency[:p50].round(2)}μs"
  puts "  p99:  #{latency[:p99].round(2)}μs (target: <#{target_p99}μs) #{passed_p99 ? '✅' : '❌'}"
  puts "  p999: #{latency[:p999].round(2)}μs"
  puts "  mean: #{latency[:mean].round(2)}μs"

  results[:total] += 1
  passed_p99 ? results[:passed] += 1 : results[:failed] += 1

  # 2. Buffer Throughput
  puts "\n📊 Benchmark: Buffer Throughput (3 seconds)"
  throughput = measure_buffer_throughput(
    event_class: SimpleBenchmarkEvent,
    duration_sec: 3
  )

  target_throughput = TARGETS[scale][:buffer_throughput]
  passed_throughput = throughput[:throughput] >= target_throughput

  print_result(
    "Buffer Throughput",
    throughput[:throughput],
    " events/sec",
    ">#{target_throughput}",
    passed_throughput
  )

  results[:total] += 1
  passed_throughput ? results[:passed] += 1 : results[:failed] += 1

  # 3. Memory Usage
  puts "\n📊 Benchmark: Memory Usage (1K events)"
  memory = measure_memory_usage(event_count: 1000)

  target_memory = TARGETS[scale][:memory_mb]
  passed_memory = memory[:total_mb] <= target_memory

  print_result(
    "Memory Usage (1K events)",
    memory[:total_mb],
    " MB",
    "<#{target_memory}",
    passed_memory
  )
  puts "  Memory per event: #{memory[:per_event_kb]} KB"

  results[:total] += 1
  passed_memory ? results[:passed] += 1 : results[:failed] += 1

  # 4. CPU Overhead (informational, no strict check)
  puts "\n📊 Benchmark: CPU Overhead (informational)"
  puts "  Note: CPU measurement is approximate"
  puts "  Target: <#{TARGETS[scale][:cpu_percent]}%"
  puts "  (Manual profiling recommended for accurate CPU %)"

  results
end

def run_medium_scale_benchmark
  scale = :medium
  print_header(scale)

  setup_e11y(buffer_size: 10_000)

  results = { total: 0, passed: 0, failed: 0 }

  # 1. track() Latency
  puts "📊 Benchmark: track() Latency (10K iterations)"
  latency = measure_track_latency(
    event_class: BenchmarkEvent,
    count: 10_000,
    scale_name: scale
  )

  target_p99 = TARGETS[scale][:track_latency_p99_us]
  passed_p99 = latency[:p99] <= target_p99

  puts "  p50:  #{latency[:p50].round(2)}μs"
  puts "  p99:  #{latency[:p99].round(2)}μs (target: <#{target_p99}μs) #{passed_p99 ? '✅' : '❌'}"
  puts "  p999: #{latency[:p999].round(2)}μs"

  results[:total] += 1
  passed_p99 ? results[:passed] += 1 : results[:failed] += 1

  # 2. Buffer Throughput
  puts "\n📊 Benchmark: Buffer Throughput (5 seconds)"
  throughput = measure_buffer_throughput(
    event_class: SimpleBenchmarkEvent,
    duration_sec: 5
  )

  target_throughput = TARGETS[scale][:buffer_throughput]
  passed_throughput = throughput[:throughput] >= target_throughput

  print_result(
    "Buffer Throughput",
    throughput[:throughput],
    " events/sec",
    ">#{target_throughput}",
    passed_throughput
  )

  results[:total] += 1
  passed_throughput ? results[:passed] += 1 : results[:failed] += 1

  # 3. Memory Usage
  puts "\n📊 Benchmark: Memory Usage (10K events)"
  memory = measure_memory_usage(event_count: 10_000)

  target_memory = TARGETS[scale][:memory_mb]
  passed_memory = memory[:total_mb] <= target_memory

  print_result(
    "Memory Usage (10K events)",
    memory[:total_mb],
    " MB",
    "<#{target_memory}",
    passed_memory
  )

  results[:total] += 1
  passed_memory ? results[:passed] += 1 : results[:failed] += 1

  results
end

def run_large_scale_benchmark
  scale = :large
  print_header(scale)

  setup_e11y(buffer_size: 100_000)

  results = { total: 0, passed: 0, failed: 0 }

  # 1. track() Latency
  puts "📊 Benchmark: track() Latency (100K iterations)"
  latency = measure_track_latency(
    event_class: BenchmarkEvent,
    count: 100_000,
    scale_name: scale
  )

  target_p99 = TARGETS[scale][:track_latency_p99_us]
  passed_p99 = latency[:p99] <= target_p99

  puts "  p50:  #{latency[:p50].round(2)}μs"
  puts "  p99:  #{latency[:p99].round(2)}μs (target: <#{target_p99}μs) #{passed_p99 ? '✅' : '❌'}"
  puts "  p999: #{latency[:p999].round(2)}μs"

  results[:total] += 1
  passed_p99 ? results[:passed] += 1 : results[:failed] += 1

  # 2. Buffer Throughput
  puts "\n📊 Benchmark: Buffer Throughput (10 seconds)"
  throughput = measure_buffer_throughput(
    event_class: SimpleBenchmarkEvent,
    duration_sec: 10
  )

  target_throughput = TARGETS[scale][:buffer_throughput]
  passed_throughput = throughput[:throughput] >= target_throughput

  print_result(
    "Buffer Throughput",
    throughput[:throughput],
    " events/sec",
    ">#{target_throughput}",
    passed_throughput
  )

  results[:total] += 1
  passed_throughput ? results[:passed] += 1 : results[:failed] += 1

  # 3. Memory Usage
  puts "\n📊 Benchmark: Memory Usage (100K events)"
  memory = measure_memory_usage(event_count: 100_000)

  target_memory = TARGETS[scale][:memory_mb]
  passed_memory = memory[:total_mb] <= target_memory

  print_result(
    "Memory Usage (100K events)",
    memory[:total_mb],
    " MB",
    "<#{target_memory}",
    passed_memory
  )

  results[:total] += 1
  passed_memory ? results[:passed] += 1 : results[:failed] += 1

  results
end

# ============================================================================
# Main Runner
# ============================================================================

def main
  puts "🚀 E11y Performance Benchmark Suite"
  puts "ADR-001 §5: Performance Requirements"
  puts "Ruby: #{RUBY_VERSION}"
  puts ""

  all_results = {}

  all_results[:small] = run_small_scale_benchmark if SCALE == "all" || SCALE == "small"

  all_results[:medium] = run_medium_scale_benchmark if SCALE == "all" || SCALE == "medium"

  all_results[:large] = run_large_scale_benchmark if SCALE == "all" || SCALE == "large"

  print_summary(all_results)

  # Exit with error code if any benchmark failed
  failed_count = all_results.values.sum { |r| r[:failed] }
  exit(failed_count > 0 ? 1 : 0)
end

main if __FILE__ == $PROGRAM_NAME
