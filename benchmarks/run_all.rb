#!/usr/bin/env ruby
# frozen_string_literal: true

# E11y Benchmarks Runner
#
# Run all benchmarks:
#   bundle exec ruby benchmarks/run_all.rb
#
# Run with specific scale:
#   SCALE=small bundle exec ruby benchmarks/run_all.rb
#   SCALE=medium bundle exec ruby benchmarks/run_all.rb
#   SCALE=large bundle exec ruby benchmarks/run_all.rb

require "bundler/setup"

# Load main benchmark suite
load File.expand_path("e11y_benchmarks.rb", __dir__)

puts "\n✅ All benchmarks completed"
puts "\nFor detailed benchmarks, run:"
puts "  bundle exec ruby benchmarks/e11y_benchmarks.rb"
