# frozen_string_literal: true

module E11y
  module Sampling
    # ValueExtractor for extracting numeric values from event payloads (FEAT-4847)
    #
    # Supports:
    # - Nested field access (dot notation: "user.balance")
    # - Type coercion (strings to numbers)
    # - Nil handling (returns 0.0 for missing fields)
    #
    # Used by value-based sampling to prioritize high-value events.
    #
    # @example Basic usage
    #   extractor = ValueExtractor.new
    #   event_data = { amount: 1500, currency: "USD" }
    #   value = extractor.extract(event_data, :amount) # => 1500.0
    #
    # @example Nested fields
    #   event_data = { user: { balance: 5000 } }
    #   value = extractor.extract(event_data, "user.balance") # => 5000.0
    #
    # @example Type coercion
    #   event_data = { amount: "1234.56" }
    #   value = extractor.extract(event_data, :amount) # => 1234.56
    #
    # @example Nil handling
    #   event_data = {}
    #   value = extractor.extract(event_data, :missing) # => 0.0
    class ValueExtractor
      # Extract numeric value from event data
      #
      # @param event_data [Hash] Event payload
      # @param field [String, Symbol] Field path (supports dot notation for nested fields)
      # @return [Float] Extracted value (0.0 if field is missing or non-numeric)
      def extract(event_data, field)
        value = navigate_to_field(event_data, field)
        coerce_to_number(value)
      end

      private

      # Navigate to nested field using dot notation
      #
      # @param data [Hash] Current data hash
      # @param field [String, Symbol] Field path
      # @return [Object, nil] Field value or nil if not found
      def navigate_to_field(data, field)
        return nil unless data.is_a?(Hash)

        field_path = field.to_s.split(".")
        field_path.reduce(data) do |current, key|
          break nil unless current.is_a?(Hash)

          current[key.to_sym] || current[key.to_s]
        end
      end

      # Coerce value to Float
      #
      # @param value [Object] Value to coerce
      # @return [Float] Numeric value (0.0 for nil or non-coercible)
      def coerce_to_number(value)
        return 0.0 if value.nil?

        case value
        when Numeric
          value.to_f
        when String
          # Try to convert string to float
          Float(value)
        else
          # Non-numeric types default to 0.0
          0.0
        end
      rescue ArgumentError, TypeError
        # Invalid numeric string or type - return 0.0
        0.0
      end
    end
  end
end
