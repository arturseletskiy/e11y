# frozen_string_literal: true

module E11y
  module Pipeline
    # Builder for configuring and validating middleware pipelines.
    #
    # Provides zone-based middleware organization with boot-time validation
    # to ensure correct execution order per ADR-015 §3.4.
    #
    # @example Basic Pipeline Configuration
    #   builder = E11y::Pipeline::Builder.new
    #
    #   builder.use E11y::Middleware::TraceContext
    #   builder.use E11y::Middleware::Validation
    #   builder.use E11y::Middleware::PIIFilter
    #
    #   builder.validate_zones! # Boot-time validation
    #
    #   pipeline = builder.build(final_app)
    #   pipeline.call(event_data)
    #
    # @example Zone-Based Configuration
    #   builder.zone(:pre_processing) do
    #     use E11y::Middleware::TraceContext
    #     use E11y::Middleware::Validation
    #   end
    #
    #   builder.zone(:security) do
    #     use E11y::Middleware::PIIFilter
    #   end
    #
    # @see E11y::Middleware::Base
    # @see ADR-015 §3.4 Middleware Zones & Modification Rules
    class Builder
      # Middleware entry: [middleware_class, args, options]
      MiddlewareEntry = Struct.new(:middleware_class, :args, :options)

      # @return [Array<MiddlewareEntry>] Registered middlewares
      attr_reader :middlewares

      def initialize
        @middlewares = []
      end

      # Add a middleware to the pipeline.
      #
      # @param middleware_class [Class] Middleware class (must inherit from Base)
      # @param args [Array] Positional arguments for middleware constructor
      # @param options [Hash] Keyword arguments for middleware constructor
      # @return [self] For method chaining
      #
      # @example
      #   builder.use E11y::Middleware::TraceContext
      #   builder.use E11y::Middleware::RateLimiting, limit: 1000
      #
      # @see ADR-015 Pipeline Flow
      def use(middleware_class, *args, **options)
        unless middleware_class < E11y::Middleware::Base
          raise ArgumentError,
                "Middleware #{middleware_class} must inherit from E11y::Middleware::Base"
        end

        @middlewares << MiddlewareEntry.new(
          middleware_class: middleware_class,
          args: args,
          options: options
        )

        self
      end

      # Configure middlewares within a specific zone.
      #
      # This is a convenience method for organizing middleware configuration.
      # Zone validation happens at boot-time via {#validate_zones!}.
      #
      # @param zone [Symbol] The zone name (must be valid per Middleware::Base::VALID_ZONES)
      # @yield Block for configuring middlewares in this zone (executed in builder context)
      # @return [self] For method chaining
      #
      # @example
      #   builder.zone(:security) do
      #     use E11y::Middleware::PIIFilter
      #   end
      #
      # @see ADR-015 §3.4.2 Middleware Zones
      def zone(zone, &block)
        unless E11y::Middleware::Base::VALID_ZONES.include?(zone)
          raise ArgumentError,
                "Invalid zone: #{zone.inspect}. " \
                "Must be one of #{E11y::Middleware::Base::VALID_ZONES.inspect}"
        end

        instance_eval(&block) if block
        self
      end

      # Build the middleware pipeline.
      #
      # Constructs a chain of middleware instances, passing each middleware
      # to the next one in reverse order (Rack pattern).
      #
      # @param app [#call] The final application/endpoint in the chain
      # @return [#call] The complete middleware pipeline
      #
      # @example
      #   pipeline = builder.build(final_app)
      #   result = pipeline.call(event_data)
      def build(app)
        @middlewares.reverse.reduce(app) do |next_app, entry|
          entry.middleware_class.new(next_app, *entry.args, **entry.options)
        end
      end

      # Validate middleware zone ordering at boot time.
      #
      # Ensures middlewares are ordered correctly according to their declared zones.
      # This prevents zone violations like PII filtering running after custom middleware.
      #
      # Delegates to {E11y::Pipeline::ZoneValidator} for validation logic.
      #
      # @return [void]
      # @raise [E11y::InvalidPipelineError] if zone ordering is invalid
      #
      # @example Boot-time validation
      #   Rails.application.config.after_initialize do
      #     E11y.pipeline_builder.validate_zones!
      #   end
      #
      # @see E11y::Pipeline::ZoneValidator
      # @see ADR-015 §3.4.5 Zone Validation
      def validate_zones!
        validator = E11y::Pipeline::ZoneValidator.new(@middlewares)
        validator.validate_boot_time!
      end

      # Clear all registered middlewares.
      #
      # @return [void]
      def clear
        @middlewares.clear
      end

      private

      # Get numeric index for a zone (for ordering validation)
      #
      # @param zone [Symbol] Zone name
      # @return [Integer] Zone index (0-4)
      def zone_index(zone)
        E11y::Middleware::Base::VALID_ZONES.index(zone) || -1
      end
    end
  end
end
