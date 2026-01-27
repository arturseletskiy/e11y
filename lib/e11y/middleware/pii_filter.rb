# frozen_string_literal: true

module E11y
  module Middleware
    # PII Filter Middleware - 3-Tier Strategy
    #
    # Filters Personally Identifiable Information (PII) from event payloads
    # before they reach adapters. Implements ADR-006 3-tier security model.
    #
    # **Three-Tier Strategy:**
    # - Tier 1: No PII (`contains_pii false`) - Skip filtering (0ms overhead)
    # - Tier 2: Default - Rails filters only (~0.05ms overhead)
    # - Tier 3: Explicit PII (`contains_pii true`) - Deep filtering (~0.2ms overhead)
    #
    # @example Basic Usage (Tier 2 - Default)
    #   class Events::OrderCreated < E11y::Event::Base
    #     schema do
    #       required(:order_id).filled(:string)
    #       optional(:api_key).filled(:string)  # Rails will filter this
    #     end
    #   end
    #
    # @example Tier 1: No PII (High Performance)
    #   class Events::HealthCheck < E11y::Event::Base
    #     contains_pii false  # Skip all filtering
    #   end
    #
    # @example Tier 3: Explicit PII (Deep Filtering)
    #   class Events::UserRegistered < E11y::Event::Base
    #     contains_pii true
    #
    #     pii_filtering do
    #       masks :password
    #       hashes :email
    #       allows :user_id
    #     end
    #   end
    #
    # @see ADR-006 PII Security & Compliance
    # @see UC-007 PII Filtering
    # @see E11y::PII::Patterns
    # rubocop:disable Metrics/ClassLength
    # PII filter is a cohesive security component with 3-tier filtering strategy
    class PIIFilter < Base
      middleware_zone :security

      # Initialize PII filtering middleware
      #
      # @param app [Proc] Next middleware in chain
      # @param config [Hash] Configuration options
      def initialize(app, config = {})
        super(app)
        @config = config
      end

      # Process event and filter PII based on tier
      #
      # @param event_data [Hash] Event data with payload
      # @return [Hash] Processed event data
      # rubocop:disable Lint/DuplicateBranch
      # Unknown tiers intentionally fallback to no filtering (same as tier1)
      def call(event_data)
        # Determine filtering tier
        tier = determine_tier(event_data)

        case tier
        when :tier1
          # Tier 1: No PII - Skip filtering (0ms overhead)
          @app.call(event_data)
        when :tier2
          # Tier 2: Rails filters only (~0.05ms overhead)
          filtered_data = apply_rails_filters(event_data)
          @app.call(filtered_data)
        when :tier3
          # Tier 3: Deep filtering (~0.2ms overhead)
          filtered_data = apply_deep_filtering(event_data)
          @app.call(filtered_data)
        else
          @app.call(event_data)
        end
      end
      # rubocop:enable Lint/DuplicateBranch

      private

      # Determine PII filtering tier for event
      #
      # @param event_data [Hash] Event data
      # @return [Symbol] :tier1, :tier2, or :tier3
      def determine_tier(event_data)
        event_class = event_data[:event_class]
        return :tier2 unless event_class.respond_to?(:pii_tier)

        # Return tier directly from event class
        event_class.pii_tier
      end

      # Apply Rails filter_parameters (Tier 2)
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Filtered event data
      def apply_rails_filters(event_data)
        # Clone to avoid modifying original
        filtered_data = deep_dup(event_data)

        # Apply Rails parameter filter
        filtered_data[:payload] = parameter_filter.filter(filtered_data[:payload])

        filtered_data
      end

      # Apply deep PII filtering (Tier 3)
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Filtered event data
      def apply_deep_filtering(event_data)
        event_class = event_data[:event_class]
        return event_data unless event_class

        # Clone to avoid modifying original
        filtered_data = deep_dup(event_data)

        # Get PII filtering config from event class
        pii_config = event_class.pii_filtering_config if event_class.respond_to?(:pii_filtering_config)
        return filtered_data unless pii_config

        # Apply field-level strategies
        filtered_data[:payload] = apply_field_strategies(
          filtered_data[:payload],
          pii_config
        )

        # Apply pattern-based filtering
        filtered_data[:payload] = apply_pattern_filtering(
          filtered_data[:payload]
        )

        filtered_data
      end

      # Apply field-level filtering strategies
      #
      # @param payload [Hash] Payload to filter
      # @param config [Hash] PII configuration
      # @return [Hash] Filtered payload
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
      # Field strategies require case/when for each PII filtering strategy type
      def apply_field_strategies(payload, config)
        return payload unless config

        filtered = {}

        payload.each do |key, value|
          # Normalize key to symbol for config lookup (config uses symbol keys)
          normalized_key = key.is_a?(Symbol) ? key : key.to_sym
          strategy = config.dig(:fields, normalized_key, :strategy) || :allow

          # rubocop:disable Lint/DuplicateBranch
          # Unknown strategies intentionally fallback to allow (same as :allow)
          filtered[key] = case strategy
                          when :mask
                            "[FILTERED]"
                          when :hash
                            hash_value(value)
                          when :partial
                            partial_mask(value)
                          when :redact
                            nil
                          when :allow
                            value
                          else
                            value
                          end
          # rubocop:enable Lint/DuplicateBranch
        end

        filtered
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

      # Apply pattern-based filtering to string values
      #
      # @param data [Object] Data to filter (recursively)
      # @return [Object] Filtered data
      def apply_pattern_filtering(data)
        case data
        when Hash
          data.transform_values { |v| apply_pattern_filtering(v) }
        when Array
          data.map { |v| apply_pattern_filtering(v) }
        when String
          filter_string_patterns(data)
        else
          data
        end
      end

      # Filter PII patterns in string
      #
      # @param str [String] String to filter
      # @return [String] Filtered string
      def filter_string_patterns(str)
        result = str.dup

        # Apply all PII patterns
        E11y::PII::Patterns::ALL.each do |pattern|
          result = result.gsub(pattern, "[FILTERED]")
        end

        result
      end

      # Hash value using SHA256
      #
      # @param value [Object] Value to hash
      # @return [String] Hashed value
      def hash_value(value)
        return "[FILTERED]" if value.nil?

        require "digest"
        "hashed_#{Digest::SHA256.hexdigest(value.to_s)[0..15]}"
      end

      # Partial mask (show first/last chars)
      #
      # @param value [String] Value to mask
      # @return [String] Partially masked value
      def partial_mask(value)
        return "[FILTERED]" unless value.is_a?(String)
        return "[FILTERED]" if value.length < 4

        if value.include?("@")
          # Email: show first 2 chars before @, last 3 chars after @
          local, domain = value.split("@", 2)
          "#{local[0..1]}***#{domain[-3..]}"
        else
          # Generic: show first/last 2 chars
          "#{value[0..1]}***#{value[-2..]}"
        end
      end

      # Deep duplicate data structure
      #
      # @param data [Object] Data to duplicate
      # @return [Object] Duplicated data
      def deep_dup(data)
        case data
        when Hash
          data.transform_values { |v| deep_dup(v) }
        when Array
          data.map { |v| deep_dup(v) }
        when String, Symbol, Integer, Float, TrueClass, FalseClass, NilClass
          data
        else
          begin
            data.dup
          rescue StandardError
            data
          end
        end
      end

      # Get Rails parameter filter
      #
      # Uses Rails.application.config.filter_parameters for PII filtering.
      #
      # @return [ActiveSupport::ParameterFilter] Parameter filter
      def parameter_filter
        @parameter_filter ||= ActiveSupport::ParameterFilter.new(
          Rails.application.config.filter_parameters
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
