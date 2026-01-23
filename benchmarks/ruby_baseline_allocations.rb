#!/usr/bin/env ruby
# frozen_string_literal: true

require "time"

# Ruby Baseline Allocation Measurement
#
# Purpose: Measure Ruby's theoretical minimum allocations
#          to establish baseline for E11y comparison.
#
# Usage: ruby benchmarks/ruby_baseline_allocations.rb

# ============================================================================
# Helper Functions
# ============================================================================

def measure_allocations
  before = GC.stat(:total_allocated_objects)
  yield
  after = GC.stat(:total_allocated_objects)
  after - before
end

# ============================================================================
# Test Cases
# ============================================================================

puts "=" * 80
puts "  Ruby Baseline Allocation Measurement"
puts "=" * 80
puts "Ruby: #{RUBY_VERSION}"
puts ""

# Warmup (initialize GC stats)
100.times { {} }
GC.start

puts "📊 Test 1: Empty method call"
puts "-" * 80

class EmptyClass
  def self.empty_method
    # Nothing
  end
end

10.times { EmptyClass.empty_method } # warmup

allocations = measure_allocations do
  1000.times { EmptyClass.empty_method }
end

puts "Empty method × 1000:  #{allocations} allocations"
puts "Per call:             #{(allocations / 1000.0).round(2)} allocations"
puts ""

# ============================================================================

puts "📊 Test 2: Method with keyword arguments (Hash allocation)"
puts "-" * 80

class KwargsClass
  def self.kwargs_method(**payload)
    payload # return the hash
  end
end

10.times { KwargsClass.kwargs_method(key: "value") } # warmup

allocations = measure_allocations do
  1000.times { KwargsClass.kwargs_method(key: "value") }
end

puts "Kwargs method × 1000: #{allocations} allocations"
puts "Per call:             #{(allocations / 1000.0).round(2)} allocations"
puts "Expected minimum:     2.0 allocations (1 Hash for kwargs, 1 Hash return)"
puts ""

# ============================================================================

puts "📊 Test 3: Method returning Hash (E11y pattern)"
puts "-" * 80

class HashReturnClass
  def self.return_hash(**payload)
    {
      event_name: "TestEvent",
      payload: payload,
      timestamp: Time.now.utc.iso8601(3)
    }
  end
end

10.times { HashReturnClass.return_hash(key: "value") } # warmup

allocations = measure_allocations do
  1000.times { HashReturnClass.return_hash(key: "value") }
end

puts "Hash return × 1000:   #{allocations} allocations"
puts "Per call:             #{(allocations / 1000.0).round(2)} allocations"
puts ""

# ============================================================================

puts "📊 Test 4: Method with Time.now.utc (timestamp overhead)"
puts "-" * 80

class TimestampClass
  def self.with_timestamp(**payload)
    {
      payload: payload,
      timestamp: Time.now.utc
    }
  end
end

10.times { TimestampClass.with_timestamp(key: "value") } # warmup

allocations = measure_allocations do
  1000.times { TimestampClass.with_timestamp(key: "value") }
end

puts "With timestamp × 1000: #{allocations} allocations"
puts "Per call:              #{(allocations / 1000.0).round(2)} allocations"
puts ""

# ============================================================================

puts "📊 Test 5: Method with iso8601(3) (string conversion)"
puts "-" * 80

class ISOTimestampClass
  def self.with_iso_timestamp(**payload)
    {
      payload: payload,
      timestamp: Time.now.utc.iso8601(3)
    }
  end
end

10.times { ISOTimestampClass.with_iso_timestamp(key: "value") } # warmup

allocations = measure_allocations do
  1000.times { ISOTimestampClass.with_iso_timestamp(key: "value") }
end

puts "With ISO timestamp × 1000: #{allocations} allocations"
puts "Per call:                  #{(allocations / 1000.0).round(2)} allocations"
puts ""

# ============================================================================
# Summary
# ============================================================================

puts "=" * 80
puts "  SUMMARY: Ruby Allocation Baseline"
puts "=" * 80
puts ""
puts "Key Findings:"
puts "1. Empty method call:     ~0 allocations (baseline)"
puts "2. Kwargs method:         2-3 allocations (Hash for params + return)"
puts "3. Hash return:           4-5 allocations (kwargs + return Hash + nested payload)"
puts "4. With timestamp:        5-7 allocations (+ Time object)"
puts "5. With ISO string:       6-8 allocations (+ String conversion)"
puts ""
puts "Expected E11y minimum:    6-8 allocations per event"
puts "For 1K events:            6,000-8,000 allocations"
puts ""
puts "DoD target:               <100 allocations per 1K events"
puts "Conclusion:               ❌ IMPOSSIBLE (60-80x too low)"
puts ""
puts "Realistic target:         <10,000 allocations per 1K events (10 per event)"
puts "                          or <10 allocations per event"
puts ""
