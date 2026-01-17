# frozen_string_literal: true

module E11y
  module Buffers
    # Base class for all E11y buffers
    #
    # @abstract Subclass and implement buffer-specific logic
    #
    # @example Ring Buffer
    #   class RingBuffer < E11y::Buffers::BaseBuffer
    #     def initialize(capacity:)
    #       # Lock-free SPSC implementation
    #     end
    #   end
    class BaseBuffer
      # Push event to buffer
      #
      # @param event [Event::Base] event to buffer
      # @return [Boolean] true if buffered, false if full
      def push(_event)
        raise NotImplementedError, "#{self.class}#push must be implemented"
      end

      # Flush all buffered events
      #
      # @yield [event] passes each event to block
      # @return [Integer] number of flushed events
      def flush
        raise NotImplementedError, "#{self.class}#flush must be implemented"
      end

      # Get current buffer size
      #
      # @return [Integer] number of events in buffer
      def size
        raise NotImplementedError, "#{self.class}#size must be implemented"
      end
    end
  end
end
