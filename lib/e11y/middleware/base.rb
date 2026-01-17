# frozen_string_literal: true

module E11y
  module Middleware
    # Base class for all E11y middleware components
    #
    # @abstract Subclass and implement {#call}
    #
    # @example Define custom middleware
    #   class CustomMiddleware < E11y::Middleware::Base
    #     def call(event)
    #       # Process event
    #       yield event # Pass to next middleware
    #     end
    #   end
    class Base
      # Process event
      #
      # @param event [Event::Base] event to process
      # @yield [event] passes event to next middleware in chain
      # @return [void]
      def call(_event)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end
    end
  end
end
