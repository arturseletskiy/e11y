# frozen_string_literal: true

module E11y
  module Middleware
    # Base class for all E11y middlewares.
    #
    # Provides the contract for middleware chain pattern and zone-based organization.
    # All middlewares must inherit from this class.
    #
    # @abstract Subclasses must implement {#call} to process events.
    #
    # @example Basic Middleware
    #   class MyMiddleware < E11y::Middleware::Base
    #     middleware_zone :pre_processing
    #
    #     def call(event_data)
    #       # Process event
    #       event_data[:custom_field] = "value"
    #
    #       # Continue chain
    #       @app.call(event_data)
    #     end
    #   end
    #
    # @example Zone-Aware Middleware
    #   class SafeEnrichment < E11y::Middleware::Base
    #     middleware_zone :pre_processing
    #     modifies_fields :metadata, :context
    #
    #     def call(event_data)
    #       validate_zone_rules!(event_data)
    #
    #       event_data[:payload][:metadata] = fetch_metadata
    #       @app.call(event_data)
    #     end
    #   end
    #
    # @see ADR-015 Middleware Execution Order
    # @see ADR-015 §3.4 Middleware Zones & Modification Rules
    class Base
      # Valid middleware zones in execution order
      VALID_ZONES = %i[
        pre_processing
        security
        routing
        post_processing
        adapters
      ].freeze

      class << self
        # Declare which zone this middleware belongs to.
        #
        # Zones define execution order and modification constraints:
        # - `:pre_processing` - Add fields before PII filtering
        # - `:security` - PII filtering (critical zone)
        # - `:routing` - Rate limiting, sampling (read-only decisions)
        # - `:post_processing` - Add metadata after PII filtering
        # - `:adapters` - Route to buffers and adapters
        #
        # @param zone [Symbol] The zone this middleware belongs to
        # @return [Symbol] The assigned zone
        # @raise [ArgumentError] if zone is not valid
        #
        # @example
        #   class MyMiddleware < E11y::Middleware::Base
        #     middleware_zone :pre_processing
        #   end
        #
        # @see ADR-015 §3.4.2 Middleware Zones
        def middleware_zone(zone = nil)
          if zone
            unless VALID_ZONES.include?(zone)
              raise ArgumentError,
                    "Invalid middleware zone: #{zone.inspect}. " \
                    "Must be one of #{VALID_ZONES.inspect}"
            end
            @middleware_zone = zone
          end

          # Return zone (getter if no argument provided)
          @middleware_zone || inherited_zone
        end

        # Declare which fields this middleware modifies.
        #
        # Used for zone validation and documentation.
        #
        # @param fields [Array<Symbol>] Field names this middleware modifies
        # @return [Array<Symbol>] The declared modified fields
        #
        # @example
        #   class MyMiddleware < E11y::Middleware::Base
        #     modifies_fields :trace_id, :timestamp
        #   end
        def modifies_fields(*fields)
          @modifies_fields = fields if fields.any?
          @modifies_fields || []
        end

        private

        # Get zone from parent class if not explicitly set on current class
        # @return [Symbol, nil]
        def inherited_zone
          return nil unless superclass.respond_to?(:middleware_zone, true)
          return nil if superclass == E11y::Middleware::Base

          superclass.middleware_zone
        end
      end

      # Initialize middleware with the next middleware in chain.
      #
      # @param app [#call] The next middleware or final endpoint in the chain
      def initialize(app)
        @app = app
      end

      # Process an event and pass it to the next middleware.
      #
      # @abstract Subclasses must implement this method
      # @param event_data [Hash] The event hash to process
      # @return [void]
      # @raise [NotImplementedError] if not implemented by subclass
      #
      # @example
      #   def call(event_data)
      #     # Pre-processing
      #     event_data[:processed_at] = Time.now.utc
      #
      #     # Continue chain
      #     @app.call(event_data)
      #   end
      def call(_event_data)
        raise NotImplementedError,
              "#{self.class.name} must implement #call(event_data)"
      end
    end
  end
end
