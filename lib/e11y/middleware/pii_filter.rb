# frozen_string_literal: true

require "active_support/parameter_filter"

module E11y
  module Middleware
    # PII Filter Middleware
    #
    # Filters Personally Identifiable Information (PII) from event payloads
    # before they reach adapters. Implements ADR-006 security model.
    #
    # **Filtering modes:**
    # - :no_pii — Skip filtering (contains_pii false, 0ms overhead)
    # - :rails_filters — Rails filter_parameters only (~0.05ms overhead)
    # - :explicit_pii — Field strategies, optionally per-adapter via exclude_adapters (~0.2ms)
    #
    # @example Basic Usage (:rails_filters - default)
    #   class Events::OrderCreated < E11y::Event::Base
    #     schema do
    #       required(:order_id).filled(:string)
    #       optional(:api_key).filled(:string)  # Rails will filter this
    #     end
    #   end
    #
    # @example :no_pii (skip filtering)
    #   class Events::HealthCheck < E11y::Event::Base
    #     contains_pii false
    #   end
    #
    # @example :explicit_pii (field strategies)
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

      # Process event and filter PII based on filtering mode
      #
      # @param event_data [Hash] Event data with payload
      # @return [Hash] Processed event data
      # rubocop:disable Lint/DuplicateBranch
      def call(event_data)
        return @app.call(event_data) if event_data[:dlq_replayed]

        mode = filtering_mode(event_data)

        case mode
        when :no_pii
          @app.call(event_data)
        when :rails_filters
          filtered_data = apply_rails_filters(event_data)
          @app.call(filtered_data)
        when :explicit_pii
          filtered_data = apply_explicit_pii_filtering(event_data)
          @app.call(filtered_data)
        else
          @app.call(event_data)
        end
      end
      # rubocop:enable Lint/DuplicateBranch

      private

      def filtering_mode(event_data)
        event_class = event_data[:event_class]
        return :rails_filters unless event_class.respond_to?(:pii_filtering_mode)

        event_class.pii_filtering_mode
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

      # :explicit_pii — field strategies, optionally payload_rewrites when exclude_adapters present.
      def apply_explicit_pii_filtering(event_data)
        event_class = event_data[:event_class]
        return event_data unless event_class

        pii_config = event_class.pii_filtering_config if event_class.respond_to?(:pii_filtering_config)
        return event_data unless pii_config

        # 1. Base payload (most restrictive)
        base_payload = apply_field_strategies(deep_dup(event_data[:payload]), pii_config, nil)
        base_payload = apply_pattern_filtering(base_payload, pii_config, [])

        filtered_data = deep_dup(event_data)
        filtered_data[:payload] = base_payload

        # 2. payload_rewrites: per-adapter overrides for exclude_adapters fields only
        has_exclude_adapters = pii_config[:fields]&.any? { |_, v| v[:exclude_adapters]&.any? }
        filtered_data[:payload_rewrites] = build_payload_rewrites(event_data, pii_config) if has_exclude_adapters

        filtered_data
      end

      # Build payload_rewrites: { adapter_name => { field => original_value } }
      # Only fields with exclude_adapters.include?(adapter) get original value.
      def build_payload_rewrites(event_data, pii_config)
        adapters = AdapterResolver.resolve(event_data)
        return {} unless adapters.any?

        original_payload = event_data[:payload] || {}
        rewrites = {}

        adapters.each do |adapter_name|
          adapter_rewrites = {}
          pii_config[:fields]&.each do |field, opts|
            next unless opts[:exclude_adapters]&.include?(adapter_name)

            key = original_payload.key?(field) ? field : field.to_s
            adapter_rewrites[key] = original_payload[key] if original_payload.key?(key)
          end
          rewrites[adapter_name] = adapter_rewrites if adapter_rewrites.any?
        end
        rewrites
      end

      # Apply field-level filtering strategies
      #
      # @param payload [Hash] Payload to filter
      # @param config [Hash] PII configuration
      # @param adapter_name [Symbol, nil] When set, use :skip for fields with exclude_adapters.include?(adapter_name)
      # @return [Hash] Filtered payload
      # rubocop:disable Metrics/MethodLength
      def apply_field_strategies(payload, config, adapter_name = nil)
        return payload unless config

        filtered = {}

        payload.each do |key, value|
          normalized_key = key.is_a?(Symbol) ? key : key.to_sym
          field_config = config.dig(:fields, normalized_key) || {}
          strategy = field_config[:strategy] || :allow

          # Per-adapter: use :skip for excluded adapters (e.g. audit gets original)
          strategy = :allow if adapter_name && field_config[:exclude_adapters]&.include?(adapter_name)

          # rubocop:disable Lint/DuplicateBranch
          filtered[key] = case strategy
                          when :mask
                            "[FILTERED]"
                          when :hash
                            hash_value(value)
                          when :partial
                            partial_mask(value)
                          when :redact
                            nil
                          when :allow, :skip
                            value
                          else
                            value
                          end
          # rubocop:enable Lint/DuplicateBranch
        end

        filtered
      end
      # rubocop:enable Metrics/MethodLength

      # Apply pattern-based filtering to string values
      def apply_pattern_filtering(data, pii_config = nil, path = [])
        case data
        when Hash then apply_pattern_filtering_hash(data, pii_config, path)
        when Array then data.map { |v| apply_pattern_filtering(v, pii_config, path) }
        when String then filter_string_if_needed(data, path, pii_config)
        else data
        end
      end

      def apply_pattern_filtering_hash(data, pii_config, path)
        data.each_with_object({}) do |(k, v), acc|
          key_sym = k.is_a?(Symbol) ? k : k.to_sym
          acc[k] = apply_pattern_filtering(v, pii_config, path + [key_sym])
        end
      end

      def filter_string_if_needed(str, path, pii_config)
        path_under_allowed_key?(path, pii_config) ? str : filter_string_patterns(str)
      end

      # Check if any ancestor key in path is explicitly allowed
      def path_under_allowed_key?(path, pii_config)
        return false unless pii_config && pii_config[:fields]

        allowed_keys = pii_config[:fields].select { |_k, v| %i[allow skip].include?(v[:strategy]) }.keys
        path.any? { |p| allowed_keys.include?(p) }
      end

      # Filter PII patterns in string (VALUE_PATTERNS only, not PASSWORD_FIELDS)
      #
      # @param str [String] String to filter
      # @return [String] Filtered string
      def filter_string_patterns(str)
        result = str.dup

        E11y::PII::Patterns::VALUE_PATTERNS.each do |pattern|
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
      # When Rails is not loaded (e.g. unit tests), uses empty filter (no-op).
      #
      # @return [ActiveSupport::ParameterFilter] Parameter filter
      def parameter_filter
        return @parameter_filter if defined?(@parameter_filter) && !@parameter_filter.nil?

        filters = if defined?(Rails) && Rails.application
                    Rails.application.config.filter_parameters
                  else
                    []
                  end
        @parameter_filter = ActiveSupport::ParameterFilter.new(filters)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
