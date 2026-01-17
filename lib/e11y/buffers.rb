# frozen_string_literal: true

# E11y::Buffers module - Event buffering implementations
#
# This module contains buffer implementations for high-throughput event storage:
# - RingBuffer: Lock-free SPSC ring buffer (100K+ events/sec)
# - AdaptiveBuffer: Memory-aware buffer with backpressure (Phase 1.2.2)
#
# @see E11y::Buffers::RingBuffer
# @see ADR-001 §3.3 (Buffer Architecture)
module E11y
  module Buffers
  end
end
