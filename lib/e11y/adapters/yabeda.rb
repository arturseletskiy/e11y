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
    class Yabeda < Base
      # Initialize Yabeda adapter
      #
      # @param config [Hash] Configuration options
      # @option config [Integer] :cardinality_limit (1000) Max unique values per label per metric
      # @option config [Array<Symbol>] :forbidden_labels ([]) Additional labels to denylist
      # @option config [Boolean] :auto_register (true) Automatically register metrics from Registry
      def initialize(config = {})
        super

        @cardinality_protection = E11y::Metrics::CardinalityProtection.new(
          cardinality_limit: config.fetch(:cardinality_limit, 1000),
          forbidden_labels: config.fetch(:forbidden_labels, [])
        )

        # Auto-register metrics from Registry
        register_metrics_from_registry! if config.fetch(:auto_register, true)
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
        E11y.logger.warn("Failed to increment Yabeda metric #{name}: #{e.message}", error: e.class.name)
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
        ::Yabeda.e11y.send(name).observe(value, safe_labels)
      rescue StandardError => e
        E11y.logger.warn("Failed to observe Yabeda histogram #{name}: #{e.message}", error: e.class.name)
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
        ::Yabeda.e11y.send(name).set(value, safe_labels)
      rescue StandardError => e
        E11y.logger.warn("Failed to set Yabeda gauge #{name}: #{e.message}", error: e.class.name)
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
      def register_yabeda_metric(metric_config)
        metric_name = metric_config[:name]
        metric_type = metric_config[:type]
        tags = metric_config[:tags] || []

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

      # Register a metric if it doesn't exist yet (for direct metric calls).
      #
      # @param name [Symbol] Metric name
      # @param type [Symbol] Metric type (:counter, :histogram, :gauge)
      # @param tags [Array<Symbol>] Metric tags (labels)
      # @param buckets [Array<Numeric>, nil] Optional histogram buckets
      # @return [void]
      # @api private
      def register_metric_if_needed(name, type, tags, buckets: nil)
        # Check if metric already exists
        return if ::Yabeda.metrics.key?(:"e11y_#{name}")

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
      rescue StandardError => e
        # Metric might already be registered - that's OK
        E11y.logger.debug("Could not register Yabeda metric #{name}: #{e.message}")
      end

      # Update a single metric based on event data
      #
      # @param metric_config [Hash] Metric configuration
      # @param event_data [Hash] Event data
      # @return [void]
      def update_metric(metric_config, event_data)
        metric_name = metric_config[:name]
        labels = extract_labels(metric_config, event_data)

        # Apply cardinality protection
        safe_labels = @cardinality_protection.filter(labels, metric_name)

        # Extract value for histogram/gauge
        value = extract_value(metric_config, event_data) if %i[histogram gauge].include?(metric_config[:type])

        # Update Yabeda metric
        case metric_config[:type]
        when :counter
          ::Yabeda.e11y.send(metric_name).increment(safe_labels)
        when :histogram
          ::Yabeda.e11y.send(metric_name).observe(value, safe_labels)
        when :gauge
          ::Yabeda.e11y.send(metric_name).set(value, safe_labels)
        end
      rescue StandardError => e
        warn "E11y Yabeda: Error updating metric #{metric_name}: #{e.message}"
      end

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
  end
end
