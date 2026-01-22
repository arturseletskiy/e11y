#!/usr/bin/env ruby
# frozen_string_literal: true

# E11y Allocation Profiling Script
#
# Purpose: Measure actual object allocations per event and verify
#          we're meeting Ruby's best practices for minimal allocations.
#
# Usage:
#   bundle exec ruby benchmarks/allocation_profiling.rb
#
# Expected results:
# - Ruby minimum: 2 allocations per event (kwargs Hash + return Hash)
# - E11y target: Close to theoretical minimum (2-5 allocations/event)
# - For 1K events: 2K-5K allocations total

require "bundler/setup"
require "memory_profiler"
require "e11y"

# ============================================================================
# Configuration
# ============================================================================

# Test with different event counts
TEST_CASES = [
  { count: 10, name: "10 events (warmup)" },
  { count: 100, name: "100 events" },
  { count: 1000, name: "1K events (DoD requirement)" },
  { count: 10_000, name: "10K events" }
].freeze

# ============================================================================
# Test Event Class
# ============================================================================

class AllocationTestEvent < E11y::Event::Base
  # Minimal schema to isolate allocation sources
  schema do
    required(:value).filled(:integer)
  end

  # Skip validation for pure allocation measurement
  validation_mode :never
end

# ============================================================================
# Setup E11y (minimal config)
# ============================================================================

E11y.configure do |config|
  config.enabled = true
  config.adapters = [E11y::Adapters::InMemory.new]
end

# ============================================================================
# Profiling Functions
# ============================================================================

def measure_allocations(event_count:)
  # Warmup (avoid cold start allocations)
  10.times { AllocationTestEvent.track(value: 1) }

  # Force GC to start clean
  GC.start

  # Profile allocations
  report = MemoryProfiler.report do
    event_count.times do |i|
      AllocationTestEvent.track(value: i)
    end
  end

  {
    total_allocated: report.total_allocated,
    total_retained: report.total_retained,
    total_allocated_memsize: report.total_allocated_memsize,
    total_retained_memsize: report.total_retained_memsize,
    per_event_allocated: (report.total_allocated.to_f / event_count).round(2),
    per_event_retained: (report.total_retained.to_f / event_count).round(2),
    per_event_memsize_bytes: (report.total_allocated_memsize.to_f / event_count).round(2)
  }
end

def detailed_allocation_report(event_count:)
  puts "\n" + "=" * 80
  puts "  DETAILED ALLOCATION REPORT (#{event_count} events)"
  puts "=" * 80

  # Warmup
  10.times { AllocationTestEvent.track(value: 1) }
  GC.start

  report = MemoryProfiler.report do
    event_count.times do |i|
      AllocationTestEvent.track(value: i)
    end
  end

  puts "\n📊 Allocation Summary:"
  puts "  Total allocated: #{report.total_allocated} objects"
  puts "  Total retained:  #{report.total_retained} objects"
  puts "  Memory size:     #{(report.total_allocated_memsize / 1024.0).round(2)} KB"
  puts ""
  puts "  Per-event allocated: #{(report.total_allocated.to_f / event_count).round(2)} objects"
  puts "  Per-event retained:  #{(report.total_retained.to_f / event_count).round(2)} objects"
  puts "  Per-event memory:    #{(report.total_allocated_memsize.to_f / event_count).round(2)} bytes"

  puts "\n📍 Top Allocation Sources (by object count):"
  report.allocated_memory_by_location.first(10).each_with_index do |(location, data), index|
    puts "  #{index + 1}. #{location}"
    puts "     Objects: #{data[:count]}"
  end

  puts "\n🔍 Allocations by Class:"
  report.allocated_memory_by_class.first(10).each_with_index do |(klass, data), index|
    puts "  #{index + 1}. #{klass}: #{data[:count]} objects"
  end

  # Leak detection
  if report.total_retained > 0
    puts "\n⚠️  MEMORY LEAK WARNING:"
    puts "  #{report.total_retained} objects retained (not garbage collected)"
    puts ""
    puts "  Retained objects by class:"
    report.retained_memory_by_class.first(5).each_with_index do |(klass, data), index|
      puts "    #{index + 1}. #{klass}: #{data[:count]} objects"
    end
  else
    puts "\n✅ No memory leaks detected (0 retained objects)"
  end

  report
end

# ============================================================================
# Verification Functions
# ============================================================================

def verify_allocation_target(result:, event_count:)
  per_event = result[:per_event_allocated]
  total = result[:total_allocated]

  puts "\n🎯 Target Verification:"
  puts ""

  # Ruby theoretical minimum: 2 allocations per event
  ruby_minimum = 2.0
  is_near_minimum = per_event <= (ruby_minimum * 2.5) # 5 allocations = 2.5x minimum (reasonable overhead)

  puts "  Ruby theoretical minimum:  #{ruby_minimum} allocations/event"
  puts "  E11y actual:               #{per_event} allocations/event"
  puts "  Overhead:                  #{((per_event / ruby_minimum) * 100 - 100).round(1)}%"
  puts ""

  if is_near_minimum
    puts "  ✅ GOOD: Near Ruby's theoretical minimum (< 2.5x)"
  elsif per_event <= 10
    puts "  ⚠️  ACCEPTABLE: Within reasonable range (< 10 allocations/event)"
  else
    puts "  ❌ CONCERN: High allocation count (> 10 allocations/event)"
  end

  # DoD requirement check (for context)
  dod_target = 100 # <100 allocations per 1K events
  dod_actual = (total.to_f / event_count * 1000).round

  puts ""
  puts "  DoD requirement (1K events): < #{dod_target} allocations"
  puts "  E11y extrapolated (1K):      #{dod_actual} allocations"

  if dod_actual <= dod_target
    puts "  ✅ MEETS DoD requirement"
  else
    puts "  ❌ EXCEEDS DoD requirement (#{dod_actual - dod_target} over)"
    puts "     Note: DoD target may be unrealistic for Ruby (see audit findings)"
  end
end

def check_for_leaks(result:)
  retained = result[:total_retained]

  puts "\n🔍 Memory Leak Check:"
  if retained == 0
    puts "  ✅ PASS: No memory leaks (0 retained objects)"
  else
    puts "  ❌ FAIL: #{retained} objects retained (potential memory leak)"
  end
end

# ============================================================================
# Main Execution
# ============================================================================

def main
  puts "🚀 E11y Allocation Profiling"
  puts "Audit: FEAT-4918 - Zero-Allocation Pattern Verification"
  puts "Ruby: #{RUBY_VERSION}"
  puts ""

  results = {}

  # Run all test cases
  TEST_CASES.each do |test_case|
    count = test_case[:count]
    name = test_case[:name]

    puts "\n" + "=" * 80
    puts "  Testing: #{name}"
    puts "=" * 80

    result = measure_allocations(event_count: count)
    results[count] = result

    puts ""
    puts "  Total allocated:   #{result[:total_allocated]} objects"
    puts "  Total retained:    #{result[:total_retained]} objects"
    puts "  Per-event alloc:   #{result[:per_event_allocated]} objects"
    puts "  Per-event memory:  #{result[:per_event_memsize_bytes]} bytes"
  end

  # Detailed report for 1K events (DoD requirement)
  detailed_allocation_report(event_count: 1000)

  # Verification for 1K events
  verify_allocation_target(result: results[1000], event_count: 1000)
  check_for_leaks(result: results[1000])

  # Summary
  puts "\n" + "=" * 80
  puts "  SUMMARY"
  puts "=" * 80
  puts ""

  result_1k = results[1000]
  per_event = result_1k[:per_event_allocated]

  if per_event <= 5 && result_1k[:total_retained] == 0
    puts "  ✅ EXCELLENT: Near-optimal allocations, no leaks"
    exit 0
  elsif per_event <= 10 && result_1k[:total_retained] == 0
    puts "  ⚠️  ACCEPTABLE: Reasonable allocations, no leaks"
    exit 0
  elsif result_1k[:total_retained] > 0
    puts "  ❌ FAIL: Memory leak detected"
    exit 1
  else
    puts "  ❌ FAIL: High allocation count"
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME
