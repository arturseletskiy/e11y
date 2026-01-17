# frozen_string_literal: true

module E11y
  module Middleware
    # Validation middleware performs schema validation on event payloads.
    #
    # This middleware runs in the pre-processing zone, AFTER TraceContext and
    # BEFORE PII filtering. It validates the event payload against the schema
    # defined in the event class.
    #
    # **CRITICAL:** Validation MUST use the ORIGINAL class name (e.g., Events::OrderPaidV2),
    # NOT the normalized name (Events::OrderPaid), because schemas are version-specific.
    #
    # @see ADR-015 §3.1 Pipeline Flow (line 96-97)
    # @see ADR-015 §3.2 Why Each Middleware Needs Original Class Name (line 125)
    # @see E11y::Event::Base#validate_payload! for validation logic
    #
    # @example Valid event passes through
    #   class Events::OrderPaid < E11y::Event::Base
    #     schema do
    #       required(:order_id).filled(:integer)
    #     end
    #   end
    #
    #   event_data = {
    #     event_class: Events::OrderPaid,
    #     payload: { order_id: 123 }
    #   }
    #
    #   # Validation passes ✅
    #   middleware.call(event_data) # → event_data (unchanged)
    #
    # @example Invalid event raises error
    #   event_data = {
    #     event_class: Events::OrderPaid,
    #     payload: { order_id: "invalid" } # ❌ Should be integer
    #   }
    #
    #   middleware.call(event_data)
    #   # Raises E11y::ValidationError: "Validation failed for Events::OrderPaid: order_id must be an integer"
    #
    # @example Schema-less events pass through
    #   class Events::SimpleEvent < E11y::Event::Base
    #     # No schema defined
    #   end
    #
    #   # Validation skipped (no schema) ✅
    #   middleware.call(event_data) # → event_data (unchanged)
    class Validation < Base
      middleware_zone :pre_processing

      # Validates event payload against its schema.
      #
      # @param event_data [Hash] The event data to validate
      # @option event_data [Class] :event_class The event class (required)
      # @option event_data [Hash] :payload The event payload (required)
      # @return [Hash, nil] Validated event data, or nil if dropped
      # @raise [E11y::ValidationError] if validation fails
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def call(event_data)
        # Skip validation if no event_class or payload
        return @app.call(event_data) unless event_data[:event_class] && event_data[:payload]

        event_class = event_data[:event_class]
        payload = event_data[:payload]

        # Get compiled schema from event class
        schema = event_class.compiled_schema

        # Skip validation if no schema defined (schema-less events)
        unless schema
          increment_metric("e11y.middleware.validation.skipped")
          return @app.call(event_data)
        end

        # Perform validation
        result = schema.call(payload)

        if result.success?
          # Validation passed
          increment_metric("e11y.middleware.validation.passed")
          @app.call(event_data)
        else
          # Validation failed - raise error with details
          increment_metric("e11y.middleware.validation.failed")

          error_message = format_validation_errors(event_class, result.errors)
          raise E11y::ValidationError, error_message
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      # Format validation errors into a human-readable message.
      #
      # @param event_class [Class] The event class
      # @param errors [Dry::Schema::MessageSet] Validation errors
      # @return [String] Formatted error message
      def format_validation_errors(event_class, errors)
        error_details = errors.to_h.map do |field, messages|
          "#{field}: #{messages.join(', ')}"
        end.join("; ")

        "Validation failed for #{event_class.name}: #{error_details}"
      end

      # Placeholder for metrics instrumentation.
      #
      # @param metric_name [String] Metric name
      # @return [void]
      def increment_metric(_metric_name)
        # TODO: Integrate with Yabeda/Prometheus in Phase 2
        # Yabeda.e11y.middleware_validation_passed.increment
      end
    end
  end
end
