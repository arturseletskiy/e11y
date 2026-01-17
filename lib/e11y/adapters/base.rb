# frozen_string_literal: true

module E11y
  module Adapters
    # Base class for all E11y adapters
    #
    # @abstract Subclass and implement {#send_event}
    #
    # @example Define custom adapter
    #   class CustomAdapter < E11y::Adapters::Base
    #     def send_event(event)
    #       # Send event to external system
    #     end
    #   end
    class Base
      # Send event to external system
      #
      # @param event [Event::Base] event to send
      # @return [void]
      # @raise [AdapterError] if sending fails
      def send_event(_event)
        raise NotImplementedError, "#{self.class}#send_event must be implemented"
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] true if adapter can accept events
      def healthy?
        true
      end
    end
  end
end
