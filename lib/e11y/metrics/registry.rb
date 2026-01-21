# frozen_string_literal: true

require "singleton"

module E11y
  module Metrics
    # Registry for metric configurations.
    #
    # Stores metric definitions and provides pattern-based matching.
    # This is a singleton class - use Registry.instance to access it.
    # All metrics (global, event-level, preset) are registered here for validation.
    #
    # @example Register metrics
    #   registry = E11y::Metrics::Registry.instance
    #   registry.register(
    #     type: :counter,
    #     pattern: 'order.*',
    #     name: :orders_total,
    #     tags: [:status, :currency],
    #     source: 'config/initializers/e11y.rb'
    #   )
    #
    # @example Find matching metrics
    #   metrics = registry.find_matching('order.paid')
    #   # => [{ type: :counter, name: :orders_total, ... }]
    # rubocop:disable Metrics/ClassLength
    # Registry is a cohesive singleton managing metric definitions and pattern matching
    class Registry
      include Singleton

      # Custom error for label conflicts
      class LabelConflictError < StandardError; end

      # Custom error for type conflicts
      class TypeConflictError < StandardError; end

      def initialize
        @metrics = []
        @mutex = Mutex.new
      end

      # Register a new metric configuration
      #
      # Validates for conflicts with existing metrics:
      # - Same metric name must have same type
      # - Same metric name must have same labels (tags)
      # - Same metric name must have same buckets (for histograms)
      #
      # @param config [Hash] Metric configuration
      # @option config [Symbol] :type Metric type (:counter, :histogram, :gauge)
      # @option config [String] :pattern Glob pattern for event names
      # @option config [Symbol] :name Metric name
      # @option config [Array<Symbol>] :tags Label names to extract
      # @option config [Proc, Symbol] :value Value extractor (for histogram/gauge)
      # @option config [Array<Numeric>] :buckets Histogram buckets
      # @option config [String] :source Source of the metric (for error messages)
      # @return [void]
      #
      # @raise [LabelConflictError] if metric already registered with different labels
      # @raise [TypeConflictError] if metric already registered with different type
      def register(config)
        validate_config!(config)

        @mutex.synchronize do
          # Check for conflicts with existing metrics (find within lock)
          existing = @metrics.find { |m| m[:name] == config[:name] }
          validate_no_conflicts!(existing, config) if existing

          @metrics << config.merge(
            pattern_regex: compile_pattern(config[:pattern])
          )
        end
      end

      # Find all metrics matching the event name
      # @param event_name [String] Event name to match
      # @return [Array<Hash>] Matching metric configurations
      def find_matching(event_name)
        @mutex.synchronize do
          @metrics.select do |metric|
            metric[:pattern_regex].match?(event_name)
          end
        end
      end

      # Find metric by name (for conflict detection)
      # @param name [Symbol] Metric name
      # @return [Hash, nil] Metric configuration or nil
      def find_by_name(name)
        @mutex.synchronize do
          @metrics.find { |m| m[:name] == name }
        end
      end

      # Get all registered metrics
      # @return [Array<Hash>] All metric configurations
      def all
        @mutex.synchronize { @metrics.dup }
      end

      # Clear all registered metrics
      # @return [void]
      def clear!
        @mutex.synchronize { @metrics.clear }
      end

      # Get count of registered metrics
      # @return [Integer] Number of registered metrics
      def size
        @mutex.synchronize { @metrics.size }
      end

      # Validate all registered metrics for conflicts
      #
      # This method is called at Rails boot time to catch configuration errors early.
      # It re-validates all metrics to ensure no conflicts exist.
      #
      # @raise [LabelConflictError] if metrics have conflicting labels
      # @raise [TypeConflictError] if metrics have conflicting types
      # @return [void]
      #
      # @example Manual validation
      #   E11y::Metrics::Registry.instance.validate_all!
      def validate_all!
        @mutex.synchronize do
          # Group metrics by name
          metrics_by_name = @metrics.group_by { |m| m[:name] }

          # Check each group for conflicts
          metrics_by_name.each_value do |metrics|
            next if metrics.size == 1 # No conflicts possible

            # Compare first metric with all others
            first = metrics.first
            metrics[1..].each do |metric|
              validate_no_conflicts!(first, metric)
            end
          end
        end
      end

      private

      # Validate metric configuration
      # @param config [Hash] Metric configuration
      # @raise [ArgumentError] if configuration is invalid
      # rubocop:disable Metrics/AbcSize
      def validate_config!(config)
        raise ArgumentError, "Metric type is required" unless config[:type]
        raise ArgumentError, "Invalid metric type: #{config[:type]}" unless %i[counter histogram
                                                                               gauge].include?(config[:type])
        raise ArgumentError, "Pattern is required" unless config[:pattern]
        raise ArgumentError, "Metric name is required" unless config[:name]

        return unless %i[histogram gauge].include?(config[:type]) && !config[:value]

        raise ArgumentError, "Value extractor is required for #{config[:type]} metrics"
      end
      # rubocop:enable Metrics/AbcSize

      # Validate that new metric doesn't conflict with existing one
      # @param existing [Hash] Existing metric configuration
      # @param new_config [Hash] New metric configuration
      # @raise [TypeConflictError] if types don't match
      # @raise [LabelConflictError] if labels don't match
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      # Conflict validation requires checking type and labels with detailed error messages
      def validate_no_conflicts!(existing, new_config)
        # Check 1: Type must match
        if existing[:type] != new_config[:type]
          raise TypeConflictError, <<~ERROR
            Metric "#{new_config[:name]}" type conflict!

            Existing: #{existing[:type]} (from #{existing[:source] || 'unknown'})
            New:      #{new_config[:type]} (from #{new_config[:source] || 'unknown'})

            Fix: Use the same type everywhere or rename the metric.
          ERROR
        end

        # Check 2: Labels (tags) must match
        existing_tags = (existing[:tags] || []).sort
        new_tags = (new_config[:tags] || []).sort

        if existing_tags != new_tags
          raise LabelConflictError, <<~ERROR
            Metric "#{new_config[:name]}" label conflict!

            Existing: #{existing_tags.inspect} (from #{existing[:source] || 'unknown'})
            New:      #{new_tags.inspect} (from #{new_config[:source] || 'unknown'})

            Fix: Use the same labels everywhere or rename the metric.

            Example:
              # Event 1
              counter :#{new_config[:name]}, tags: #{existing_tags.inspect}
            #{'  '}
              # Event 2 (must match!)
              counter :#{new_config[:name]}, tags: #{existing_tags.inspect}
          ERROR
        end

        # Check 3: For histograms, buckets should match (warn only)
        return unless new_config[:type] == :histogram

        existing_buckets = existing[:buckets]
        new_buckets = new_config[:buckets]

        return if existing_buckets == new_buckets

        warn <<~WARNING
          Metric "#{new_config[:name]}" has different buckets!
          Existing: #{existing_buckets.inspect}
          New:      #{new_buckets.inspect}
          Using existing buckets.
        WARNING
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # Compile glob pattern to regex
      # @param pattern [String] Glob pattern (e.g., "order.*", "user.*.created")
      # @return [Regexp] Compiled regex
      def compile_pattern(pattern)
        # Convert glob pattern to regex
        # - '*' matches any segment (e.g., "order.*" matches "order.paid", "order.created")
        # - '**' matches any number of segments (e.g., "order.**" matches "order.paid.usd")
        regex_pattern = pattern
                        .gsub(".", '\.')           # Escape dots
                        .gsub("**", "__DOUBLE__")  # Temporarily replace **
                        .gsub("*", "[^.]+")        # * matches single segment
                        .gsub("__DOUBLE__", ".*")  # ** matches multiple segments

        Regexp.new("\\A#{regex_pattern}\\z")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
