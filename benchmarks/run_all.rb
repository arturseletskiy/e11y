#!/usr/bin/env ruby
# frozen_string_literal: true

# E11y Benchmarks Runner
#
# Run all benchmarks:
#   bundle exec ruby benchmarks/run_all.rb
#
# Run with specific iterations:
#   ITERATIONS=10000 bundle exec ruby benchmarks/run_all.rb

require "bundler/setup"
require "benchmark"
require "e11y"

ITERATIONS = (ENV["ITERATIONS"] || 1000).to_i

puts "🚀 E11y Benchmarks (#{ITERATIONS} iterations)"
puts "=" * 60

# Benchmarks will be implemented in Phase 1+
# Examples:
# - Event creation (zero-allocation goal)
# - Buffer operations (push/flush)
# - Middleware chain execution
# - Adapter send performance

puts "\n⚠️  Benchmarks will be implemented in Phase 1+"
puts "Expected metrics (from ADR-009):"
puts "  - Event creation: < 10µs per event (zero-allocation)"
puts "  - Buffer push: < 1µs (lock-free)"
puts "  - Middleware: < 5µs per middleware"
puts "  - Memory: < 100KB baseline, < 10MB under load"
