# frozen_string_literal: true

module E11y
  module Pipeline
    # Validator for middleware zone rules and constraints.
    #
    # Provides boot-time validation to ensure middleware zones are correctly
    # ordered and PII bypass is prevented.
    #
    # **Design Decision:** Only boot-time validation is performed.
    # Runtime validation was deemed unnecessary as:
    # - Boot-time validation catches all configuration errors
    # - Runtime validation adds ~1ms overhead per event
    # - Pipeline configuration is static after boot
    #
    # @see ADR-015 §3.4.5 Zone Validation
    # @see ADR-015 §3.4.4 Custom Middleware Constraints
    class ZoneValidator
      # Error raised when zone ordering is invalid
      class ZoneOrderError < E11y::InvalidPipelineError; end

      # Zone ordering constraints (valid transitions)
      ZONE_ORDER = %i[
        pre_processing
        security
        routing
        post_processing
        adapters
      ].freeze

      # @param middlewares [Array<MiddlewareEntry>] Middleware entries to validate
      def initialize(middlewares)
        @middlewares = middlewares
      end

      # Validate zone ordering at boot time.
      #
      # Ensures middlewares are ordered correctly according to their declared zones.
      # This is a comprehensive check that runs once during application boot.
      #
      # @return [void]
      # @raise [ZoneOrderError] if zone ordering is invalid
      #
      # @example
      #   validator = ZoneValidator.new(pipeline.middlewares)
      #   validator.validate_boot_time!
      def validate_boot_time!
        return if @middlewares.empty?

        previous_zone_index = -1

        @middlewares.each_with_index do |entry, index|
          middleware_zone = entry.middleware_class.middleware_zone

          # Skip middlewares without declared zone (optional)
          next unless middleware_zone

          current_zone_index = zone_index(middleware_zone)

          # Validate zone progression (must be non-decreasing)
          if current_zone_index < previous_zone_index
            previous_entry = @middlewares[index - 1]
            previous_zone = previous_entry.middleware_class.middleware_zone

            raise ZoneOrderError,
                  build_zone_order_error(entry.middleware_class, middleware_zone,
                                         previous_entry.middleware_class, previous_zone)
          end

          previous_zone_index = current_zone_index
        end
      end

      private

      # Get numeric index for a zone (for ordering validation)
      #
      # @param zone [Symbol] Zone name
      # @return [Integer] Zone index (0-4)
      def zone_index(zone)
        ZONE_ORDER.index(zone) || -1
      end

      # Build detailed error message for zone order violations
      #
      # @param current_middleware [Class] Current middleware class
      # @param current_zone [Symbol] Current middleware zone
      # @param previous_middleware [Class] Previous middleware class
      # @param previous_zone [Symbol] Previous middleware zone
      # @return [String] Formatted error message
      def build_zone_order_error(current_middleware, current_zone,
                                 previous_middleware, previous_zone)
        <<~ERROR
          Invalid middleware zone order detected:

          #{current_middleware.name} (zone: #{current_zone})
          cannot follow
          #{previous_middleware.name} (zone: #{previous_zone})

          Valid zone order: #{ZONE_ORDER.join(' → ')}

          This violation prevents proper middleware execution and may
          create security risks (e.g., PII bypass).

          See ADR-015 §3.4 for middleware zone guidelines.
        ERROR
      end
    end
  end
end
