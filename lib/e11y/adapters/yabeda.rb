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
    # @see UC-003 Event Metrics
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
        register_middleware_metrics!
        register_self_monitoring_metrics!

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
      # @return [Boolean] true if Yabeda is available, configured, and e11y group exists
      def healthy?
        return false unless defined?(::Yabeda)
        return false unless ::Yabeda.respond_to?(:e11y)

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

        # Update Yabeda metric (guard against nil when metric wasn't registered, e.g. after configure!)
        metric = ::Yabeda.e11y.send(name)
        return unless metric

        metric.increment(safe_labels, by: value)
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

        # Update Yabeda metric (guard against nil when metric wasn't registered)
        metric = ::Yabeda.e11y.send(name)
        return unless metric

        metric.measure(safe_labels, value)
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

        # Update Yabeda metric (guard against nil when metric wasn't registered)
        metric = ::Yabeda.e11y.send(name)
        return unless metric

        metric.set(safe_labels, value)
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
        raise ArgumentError, "cardinality_limit must be an Integer" if @config[:cardinality_limit] && !@config[:cardinality_limit].is_a?(Integer)

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

      # Pre-register middleware self-monitoring metrics.
      #
      # These metrics are used by TraceContext, Validation, and Routing middleware.
      # Must be registered before Yabeda.configure! is called (e.g. in app initializers).
      # Called during adapter initialization so they're available when events flow.
      # Names use underscores (Prometheus requires /[a-zA-Z_:][a-zA-Z0-9_:]*/, no dots).
      #
      # @return [void]
      def register_middleware_metrics!
        return unless defined?(::Yabeda)

        middleware_metrics = [
          { name: :e11y_middleware_trace_context_processed, tags: [] },
          { name: :e11y_middleware_validation_total, tags: [:result] },
          { name: :e11y_middleware_routing_routed, tags: %i[adapters_count routing_type] }
        ]

        cardinality_metrics = [
          { name: :e11y_cardinality_overflow_total, tags: %i[metric action strategy] },
          { name: :e11y_cardinality_current, type: :gauge, tags: [:metric] }
        ]

        (middleware_metrics + cardinality_metrics).each do |m|
          type = m[:type] || :counter
          register_metric_if_needed(m[:name], type, m[:tags])
        end
      rescue StandardError => e
        E11y.logger.debug("Could not register middleware metrics: #{e.message}")
      end

      # Pre-register self-monitoring metrics (request buffer, retry, circuit breaker, DLQ, etc.).
      # Must be registered before Yabeda.configure! so they exist when reliability layer runs.
      #
      # @return [void]
      # rubocop:disable Metrics/MethodLength -- metric list is inherently long
      def register_self_monitoring_metrics!
        return unless defined?(::Yabeda)

        metrics = [
          # Request buffer (consolidated)
          { name: :e11y_request_buffer_total, tags: [:event] },
          # Retry handler
          { name: :e11y_retry_success, tags: %i[adapter attempts] },
          { name: :e11y_retry_recovered, tags: %i[adapter attempts] },
          { name: :e11y_retry_permanent_failure, tags: %i[adapter error attempt] },
          { name: :e11y_retry_exhausted, tags: %i[adapter error attempts] },
          { name: :e11y_retry_attempt, tags: %i[adapter error attempt] },
          # Circuit breaker (consolidated: transitions counter + state gauge)
          { name: :e11y_circuit_breaker_transitions_total, tags: %i[adapter event] },
          { name: :e11y_circuit_breaker_state, type: :gauge, tags: [:adapter] },
          # Adapter performance & reliability
          { name: :e11y_adapter_send_duration_seconds, type: :histogram, tags: [:adapter], buckets: [0.001, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0] },
          { name: :e11y_adapter_writes_total, tags: %i[adapter status error_class] },
          # DLQ
          { name: :e11y_dlq_filter_decisions_total, tags: %i[action reason] },
          { name: :e11y_dlq_saved_total, tags: [:event_name] },
          { name: :e11y_dlq_parse_error_total, tags: [:error] },
          { name: :e11y_dlq_replayed_total, tags: [:event_name] },
          { name: :e11y_dlq_replay_failed_total, tags: [:error] },
          # Retry rate limiter (consolidated)
          { name: :e11y_retry_rate_limiter_total, tags: %i[adapter event delay_sec] },
          # Buffer (ring, adaptive) — consolidated
          { name: :e11y_buffer_overflow_total, tags: [:event] },
          # Rate limiting / sampling
          { name: :e11y_events_dropped_total, tags: %i[reason event_type] },
          # SLO tracking (Request middleware triggers on every HTTP request when enabled)
          { name: :slo_http_requests_total, tags: %i[controller action status] },
          { name: :slo_http_request_duration_seconds, type: :histogram, tags: %i[controller action],
            buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0] },
          { name: :slo_background_jobs_total, tags: %i[job_class status queue] },
          { name: :slo_background_job_duration_seconds, type: :histogram, tags: %i[job_class queue],
            buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0] }
        ]

        metrics.each do |m|
          type = m[:type] || :counter
          buckets = m[:buckets]
          register_metric_if_needed(m[:name], type, m[:tags], buckets: buckets)
        end
      rescue StandardError => e
        E11y.logger.debug("Could not register self-monitoring metrics: #{e.message}")
      end
      # rubocop:enable Metrics/MethodLength

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
        ::Yabeda.configure do |config = nil|
          next unless config.respond_to?(:group)

          config.group :e11y do
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
      # Metric registration requires case/when for different metric types
      def register_metric_if_needed(name, type, tags, buckets: nil)
        # Check if metric already exists (Yabeda stores metric keys as strings)
        return if ::Yabeda.metrics.key?("e11y_#{name}")

        ::Yabeda.configure do |config = nil|
          next unless config.respond_to?(:group)

          config.group :e11y do
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

      # Update a single metric based on event data
      #
      # @param metric_config [Hash] Metric configuration
      # @param event_data [Hash] Event data
      # @return [void]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Metric update requires multiple steps for label extraction and value handling
      def update_metric(metric_config, event_data) # rubocop:todo Metrics/MethodLength
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

        # Update Yabeda metric (skip if e11y group not registered, e.g. Yabeda not configured)
        return unless ::Yabeda.respond_to?(:e11y)

        metric = ::Yabeda.e11y.send(metric_name)
        return unless metric

        case metric_config[:type]
        when :counter
          metric.increment(final_labels)
        when :histogram
          metric.measure(final_labels, value)
        when :gauge
          metric.set(final_labels, value)
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
