# frozen_string_literal: true

require "e11y/adapters/base"
require "e11y/metrics/cardinality_protection"
require "e11y/metrics/registry"

# Check if Yabeda is available
begin
  require "yabeda"
rescue LoadError
  raise LoadError, <<~ERROR
    Yabeda not available!

    To use E11y::Adapters::Yabeda, add to your Gemfile:

      gem 'yabeda'
      gem 'yabeda-prometheus'  # For Prometheus exporter

    Then run: bundle install
  ERROR
end

module E11y
  module Adapters
    # Yabeda adapter for E11y metrics.
    #
    # This adapter integrates with Yabeda to expose metrics to Prometheus.
    # It includes built-in cardinality protection to prevent metric explosions.
    #
    # Features:
    # - Automatic metric registration from E11y::Metrics::Registry
    # - 3-layer cardinality protection (denylist, per-metric limits, monitoring)
    # - Counter, Histogram, and Gauge support
    # - Thread-safe metric updates
    #
    # @example Basic usage
    #   adapter = E11y::Adapters::Yabeda.new(
    #     cardinality_limit: 1000,
    #     forbidden_labels: [:custom_id]
    #   )
    #
    #   # Metrics are automatically registered from Registry
    #   # Events automatically update metrics via middleware
    #
    # @see ADR-002 Metrics & Yabeda Integration
    # @see UC-003 Pattern-Based Metrics
    # rubocop:disable Metrics/ClassLength
    # Yabeda adapter contains metrics registration and update logic as cohesive unit
    class Yabeda < Base
      # Initialize Yabeda adapter
      #
      # @param config [Hash] Configuration options
      # @option config [Integer] :cardinality_limit (1000) Max unique values per label per metric
      # @option config [Array<Symbol>] :forbidden_labels ([]) Additional labels to denylist
      # @option config [Symbol] :overflow_strategy (:drop) Strategy on overflow - :drop, :alert, or :relabel
      # @option config [Boolean] :auto_register (true) Automatically register metrics from Registry
      def initialize(config = {})
        super

        @cardinality_protection = E11y::Metrics::CardinalityProtection.new(
          cardinality_limit: config.fetch(:cardinality_limit, 1000),
          additional_denylist: config.fetch(:forbidden_labels, []),
          overflow_strategy: config.fetch(:overflow_strategy, :drop)
        )

        # Auto-register metrics from Registry
        return unless config.fetch(:auto_register, true)

        register_metrics_from_registry!

        # Apply configuration in non-Rails environments (Rails does this automatically)
        # In tests, Yabeda.configure! should be called explicitly in before blocks
        apply_yabeda_configuration!
      end

      # Write a single event to Yabeda
      #
      # Extracts metrics from event data and updates corresponding Yabeda metrics.
      # Applies cardinality protection to prevent label explosions.
      #
      # @param event_data [Hash] Event data
      # @return [Boolean] true if successful
      def write(event_data)
        event_name = event_data[:event_name].to_s
        matching_metrics = E11y::Metrics::Registry.instance.find_matching(event_name)

        matching_metrics.each do |metric_config|
          update_metric(metric_config, event_data)
        end

        true
      rescue StandardError => e
        warn "E11y Yabeda adapter error: #{e.message}"
        false
      end

      # Write a batch of events
      #
      # @param events [Array<Hash>] Array of event data hashes
      # @return [Boolean] true if successful
      def write_batch(events)
        events.each { |event| write(event) }
        true
      rescue StandardError => e
        warn "E11y Yabeda adapter batch error: #{e.message}"
        false
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] true if Yabeda is available and configured
      def healthy?
        return false unless defined?(::Yabeda)

        ::Yabeda.configured?
      rescue StandardError
        false
      end

      # Close adapter (no-op for Yabeda)
      #
      # @return [void]
      def close
        # Yabeda doesn't need explicit cleanup
      end

      # Get adapter capabilities
      #
      # @return [Hash] Capabilities hash
      def capabilities
        {
          batch: true,
          async: false,
          filtering: false,
          metrics: true
        }
      end

      # Track a counter metric (for E11y::Metrics facade).
      #
      # @param name [Symbol] Metric name
      # @param labels [Hash] Metric labels
      # @param value [Integer] Increment value (default: 1)
      # @return [void]
      def increment(name, labels = {}, value: 1)
        return unless healthy?

        # Apply cardinality protection
        safe_labels = @cardinality_protection.filter(labels, name)

        # Register metric if not exists
        register_metric_if_needed(name, :counter, safe_labels.keys)

        # Update Yabeda metric
        ::Yabeda.e11y.send(name).increment(safe_labels, by: value)
      rescue StandardError => e
        E11y.logger.warn("Failed to increment Yabeda metric #{name}: #{e.message}")
      end

      # Track a histogram metric (for E11y::Metrics facade).
      #
      # @param name [Symbol] Metric name
      # @param value [Numeric] Observed value
      # @param labels [Hash] Metric labels
      # @param buckets [Array<Numeric>, nil] Optional histogram buckets
      # @return [void]
      def histogram(name, value, labels = {}, buckets: nil)
        return unless healthy?

        # Apply cardinality protection
        safe_labels = @cardinality_protection.filter(labels, name)

        # Register metric if not exists
        register_metric_if_needed(name, :histogram, safe_labels.keys, buckets: buckets)

        # Update Yabeda metric
        ::Yabeda.e11y.send(name).measure(safe_labels, value)
      rescue StandardError => e
        E11y.logger.warn("Failed to observe Yabeda histogram #{name}: #{e.message}")
      end

      # Track a gauge metric (for E11y::Metrics facade).
      #
      # @param name [Symbol] Metric name
      # @param value [Numeric] Current value
      # @param labels [Hash] Metric labels
      # @return [void]
      def gauge(name, value, labels = {})
        return unless healthy?

        # Apply cardinality protection
        safe_labels = @cardinality_protection.filter(labels, name)

        # Register metric if not exists
        register_metric_if_needed(name, :gauge, safe_labels.keys)

        # Update Yabeda metric
        ::Yabeda.e11y.send(name).set(safe_labels, value)
      rescue StandardError => e
        E11y.logger.warn("Failed to set Yabeda gauge #{name}: #{e.message}")
      end

      # Validate configuration
      #
      # @raise [ArgumentError] if configuration is invalid
      # @return [void]
      def validate_config!
        super

        # Validate cardinality_limit
        if @config[:cardinality_limit] && !@config[:cardinality_limit].is_a?(Integer)
          raise ArgumentError, "cardinality_limit must be an Integer"
        end

        # Validate forbidden_labels
        return unless @config[:forbidden_labels] && !@config[:forbidden_labels].is_a?(Array)

        raise ArgumentError, "forbidden_labels must be an Array"
      end

      # Format event for Yabeda (no-op, metrics are updated directly)
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Original event data
      def format_event(event_data)
        event_data
      end

      # Get current cardinality statistics
      #
      # @return [Hash] Cardinality statistics per metric:label
      def cardinality_stats
        @cardinality_protection.cardinalities
      end

      # Reset cardinality tracking (for testing)
      #
      # @return [void]
      def reset_cardinality!
        @cardinality_protection.reset!
      end

      private

      # Apply Yabeda configuration (smart detection of environment)
      #
      # In Rails environments, configuration is applied automatically via Railtie.
      # In non-Rails environments (e.g., Sinatra, standalone Ruby), we apply it here.
      # In test environments, configuration should be applied explicitly in test setup.
      #
      # @return [void]
      # @api private
      def apply_yabeda_configuration!
        # Don't auto-apply in Rails - Rails will call configure! via Railtie
        return if defined?(::Rails)

        # Don't auto-apply if already configured
        return if ::Yabeda.configured?

        # Apply configuration (non-Rails environments only)
        ::Yabeda.configure!
      rescue StandardError => e
        E11y.logger.debug("Could not apply Yabeda configuration: #{e.message}")
      end

      # Register metrics from Registry into Yabeda
      #
      # This is called during initialization if auto_register is true.
      # It creates Yabeda metric definitions for all metrics in the Registry.
      #
      # @return [void]
      def register_metrics_from_registry!
        return unless defined?(::Yabeda)

        registry = E11y::Metrics::Registry.instance
        registry.all.each do |metric_config|
          register_yabeda_metric(metric_config)
        end
      end

      # Register a single metric in Yabeda
      #
      # @param metric_config [Hash] Metric configuration from Registry
      # @return [void]
      # rubocop:disable Metrics/MethodLength
      # Metric registration requires case/when for different metric types
      def register_yabeda_metric(metric_config)
        metric_name = metric_config[:name]
        metric_type = metric_config[:type]
        tags = metric_config[:tags] || []

        # Skip if metric already exists (prevents re-registration errors)
        return if ::Yabeda.metrics.key?("e11y_#{metric_name}")

        # Define metric in Yabeda group
        ::Yabeda.configure do
          group :e11y do
            case metric_type
            when :counter
              counter metric_name, tags: tags, comment: "E11y metric: #{metric_name}"
            when :histogram
              histogram metric_name,
                        tags: tags,
                        buckets: metric_config[:buckets] || [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10],
                        comment: "E11y metric: #{metric_name}"
            when :gauge
              gauge metric_name, tags: tags, comment: "E11y metric: #{metric_name}"
            end
          end
        end
      rescue StandardError => e
        # Metric might already be registered - that's OK
        warn "E11y Yabeda: Could not register metric #{metric_name}: #{e.message}"
      end
      # rubocop:enable Metrics/MethodLength

      # Register a metric if it doesn't exist yet (for direct metric calls).
      #
      # @param name [Symbol] Metric name
      # @param type [Symbol] Metric type (:counter, :histogram, :gauge)
      # @param tags [Array<Symbol>] Metric tags (labels)
      # @param buckets [Array<Numeric>, nil] Optional histogram buckets
      # @return [void]
      # @api private
      # rubocop:disable Metrics/MethodLength
      # Metric registration requires case/when for different metric types
      def register_metric_if_needed(name, type, tags, buckets: nil)
        # Check if metric already exists (Yabeda stores metric keys as strings)
        return if ::Yabeda.metrics.key?("e11y_#{name}")

        ::Yabeda.configure do
          group :e11y do
            case type
            when :counter
              counter name, tags: tags, comment: "E11y self-monitoring: #{name}"
            when :histogram
              histogram name,
                        tags: tags,
                        buckets: buckets || [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10],
                        comment: "E11y self-monitoring: #{name}"
            when :gauge
              gauge name, tags: tags, comment: "E11y self-monitoring: #{name}"
            end
          end
        end

        # Apply configuration for runtime-registered metrics (non-Rails environments)
        apply_yabeda_configuration!
      rescue StandardError => e
        # Metric might already be registered - that's OK
        E11y.logger.warn("Could not register Yabeda metric #{name}: #{e.message}")
      end
      # rubocop:enable Metrics/MethodLength

      # Update a single metric based on event data
      #
      # @param metric_config [Hash] Metric configuration
      # @param event_data [Hash] Event data
      # @return [void]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Metric update requires multiple steps for label extraction and value handling
      def update_metric(metric_config, event_data)
        metric_name = metric_config[:name]
        labels = extract_labels(metric_config, event_data)

        # Apply cardinality protection (normalize metric_name to string for consistent tracking)
        safe_labels = @cardinality_protection.filter(labels, metric_name.to_s)

        # Extract value for histogram/gauge
        value = extract_value(metric_config, event_data) if %i[histogram gauge].include?(metric_config[:type])

        # Get original tags from metric config - these are the tags the metric was registered with
        original_tags = metric_config.fetch(:tags, [])

        # Lazy registration: register metric if it doesn't exist in Yabeda yet
        # CRITICAL: Use ORIGINAL tags from metric config, not filtered safe_labels.keys
        # Prometheus requires all tags declared at registration time
        register_metric_if_needed(
          metric_name,
          metric_config[:type],
          original_tags,
          buckets: metric_config[:buckets]
        )

        # Ensure all required tags are present in safe_labels
        # If cardinality protection dropped a tag, add placeholder value
        # Prometheus requires all tags declared at registration to be present in every update
        final_labels = original_tags.each_with_object({}) do |tag, acc|
          acc[tag] = safe_labels.key?(tag) ? safe_labels[tag] : "[DROPPED]"
        end

        # Update Yabeda metric with all required labels
        case metric_config[:type]
        when :counter
          ::Yabeda.e11y.send(metric_name).increment(final_labels)
        when :histogram
          ::Yabeda.e11y.send(metric_name).measure(final_labels, value)
        when :gauge
          ::Yabeda.e11y.send(metric_name).set(final_labels, value)
        end
      rescue StandardError => e
        warn "E11y Yabeda: Error updating metric #{metric_name}: #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # Extract labels from event data
      #
      # @param metric_config [Hash] Metric configuration
      # @param event_data [Hash] Event data
      # @return [Hash] Extracted labels
      def extract_labels(metric_config, event_data)
        metric_config.fetch(:tags, []).each_with_object({}) do |tag, acc|
          value = event_data[tag] || event_data.dig(:payload, tag)
          acc[tag] = value.to_s if value
        end
      end

      # Extract value for histogram or gauge metrics
      #
      # @param metric_config [Hash] Metric configuration
      # @param event_data [Hash] Event data
      # @return [Numeric] The extracted value
      def extract_value(metric_config, event_data)
        value_extractor = metric_config[:value]
        case value_extractor
        when Symbol
          event_data[value_extractor] || event_data.dig(:payload, value_extractor)
        when Proc
          value_extractor.call(event_data)
        else
          1 # Default fallback
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
