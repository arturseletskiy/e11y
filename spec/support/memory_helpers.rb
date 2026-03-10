# frozen_string_literal: true

require "memory_profiler"

# MemoryHelpers — included in tests tagged :memory and :benchmark.
#
# Provides #measure_allocations to encapsulate the warmup→GC→profile pattern
# so individual tests don't repeat boilerplate.
module MemoryHelpers
  # Warm up the code path, force GC, then profile allocations.
  #
  # @param count   [Integer] iterations to profile (default: 100)
  # @param warmup  [Integer] unmeasured warmup iterations (default: 10)
  # @yield the operation to profile (called count + warmup times total)
  # @return [MemoryProfiler::Results]
  def measure_allocations(count: 100, warmup: 10, &block)
    warmup.times { block.call }
    GC.start
    GC.compact if GC.respond_to?(:compact)
    MemoryProfiler.report { count.times { block.call } }
  end
end

RSpec.configure do |config|
  config.include MemoryHelpers, :memory
  config.include MemoryHelpers, :benchmark
end
