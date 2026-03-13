# frozen_string_literal: true

module E11y
  module Event
    # Configuration for value-based sampling at event class level (FEAT-4848)
    #
    # Allows events to define sampling thresholds based on payload values.
    #
    # @example High-value payment events
    #   class PaymentEvent < E11y::Event::Base
    #     sample_by_value :amount, greater_than: 1000
    #   end
    #
    # @example Range-based sampling
    #   class OrderEvent < E11y::Event::Base
    #     sample_by_value :total, in_range: 100..500
    #   end
    #
    # @example Multiple conditions (OR logic)
    #   class TransactionEvent < E11y::Event::Base
    #     sample_by_value :amount, greater_than: 5000
    #     sample_by_value :status, equals: "vip"
    #   end
    class ValueSamplingConfig
      attr_reader :field, :comparisons

      # Initialize value sampling configuration
      #
      # @param field [String, Symbol] Field to extract value from
      # @param comparisons [Hash] Comparison rules
      # @option comparisons [Numeric] :greater_than (>) Sample if value > threshold
      # @option comparisons [Numeric] :less_than (<) Sample if value < threshold
      # @option comparisons [Object] :equals (==) Sample if value == threshold
      # @option comparisons [Range] :in_range Sample if value in range
      def initialize(field, comparisons = {})
        @field = field
        @comparisons = comparisons
        validate_comparisons!
      end

      # Check if event_data matches sampling criteria
      #
      # @param event_data [Hash] Event payload
      # @param extractor [E11y::Sampling::ValueExtractor] Value extractor
      # @return [Boolean] true if value matches any comparison
      def matches?(event_data, extractor)
        value = extractor.extract(event_data, field)

        comparisons.any? do |comparison_type, threshold|
          case comparison_type
          when :greater_than
            value > threshold
          when :less_than
            value < threshold
          when :equals
            value == threshold
          when :in_range
            threshold.cover?(value)
          else
            false
          end
        end
      end

      # Valid comparison types for value-based sampling
      VALID_COMPARISON_TYPES = %i[greater_than less_than equals in_range].freeze
      # Comparison types that require numeric thresholds
      NUMERIC_COMPARISON_TYPES = %i[greater_than less_than].freeze

      private

      # Validation requires checking multiple comparison types and threshold types
      def validate_comparisons!
        raise ArgumentError, "At least one comparison required" if comparisons.empty?

        comparisons.each do |type, threshold|
          raise ArgumentError, "Invalid comparison type: #{type}" unless VALID_COMPARISON_TYPES.include?(type)

          raise ArgumentError, "in_range requires a Range" if type == :in_range && !threshold.is_a?(Range)

          raise ArgumentError, "#{type} requires a Numeric threshold" if NUMERIC_COMPARISON_TYPES.include?(type) && !threshold.is_a?(Numeric)
        end
      end
    end
  end
end
