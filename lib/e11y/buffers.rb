# frozen_string_literal: true

module E11y
  # Event buffering implementations
  #
  # This module contains buffer implementations for high-throughput event storage:
  # - RingBuffer: Lock-free SPSC ring buffer (100K+ events/sec)
  # - AdaptiveBuffer: Memory-aware buffer with backpressure (Phase 1.2.2)
  #
  # @see E11y::Buffers::RingBuffer
  # @see ADR-001 §3.3 (Buffer Architecture)
  module Buffers
  end
end
