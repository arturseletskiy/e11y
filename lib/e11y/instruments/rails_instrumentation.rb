# frozen_string_literal: true

module E11y
  module Instruments
    # Rails instrumentation integration
    #
    # Maps ActiveSupport::Notifications to E11y events (unidirectional flow)
    # See ADR-008 §4.1 for architecture decisions
    #
    # @example Subscribe to Rails events
    #   E11y::Instruments::RailsInstrumentation.setup!
    class RailsInstrumentation
      # Setup Rails instrumentation
      #
      # @return [void]
      def self.setup!
        # TODO: Implement in Phase 2 (ADR-008)
        raise NotImplementedError, "RailsInstrumentation will be implemented in Phase 2"
      end
    end
  end
end
