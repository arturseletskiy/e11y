# frozen_string_literal: true

module E11y
  module Reliability
    module DLQ
      # DLQ Filter determines which failed events should be saved to DLQ.
      #
      # Supports:
      # - Always save patterns (e.g., payment.*, audit.*)
      # - Always discard patterns (e.g., debug.*, test.*)
      # - Severity-based filtering (e.g., always save :error, :fatal)
      #
      # @example Configuration
      #   filter = Filter.new(
      #     always_save_patterns: [/^payment\./, /^audit\./],
      #     always_discard_patterns: [/^debug\./, /^test\./],
      #     save_severities: [:error, :fatal]
      #   )
      #
      #   filter.should_save?(event_data)  # => true/false
      #
      # @see ADR-013 §4.3 (DLQ Filter)
      # @see UC-021 §3.2 (DLQ Filter Configuration)
      class Filter
        # @param always_save_patterns [Array<Regexp>] Event patterns to always save
        # @param always_discard_patterns [Array<Regexp>] Event patterns to always discard
        # @param save_severities [Array<Symbol>] Severities to always save (:error, :fatal)
        # @param default_behavior [Symbol] Default behavior when no rule matches (:save or :discard)
        def initialize(
          always_save_patterns: [],
          always_discard_patterns: [],
          save_severities: %i[error fatal],
          default_behavior: :save
        )
          @always_save_patterns = always_save_patterns
          @always_discard_patterns = always_discard_patterns
          @save_severities = save_severities
          @default_behavior = default_behavior
        end

        # Check if event should be saved to DLQ.
        #
        # Priority order:
        # 1. Always discard patterns (highest priority)
        # 2. Always save patterns
        # 3. Severity-based rules
        # 4. Default behavior
        #
        # @param event_data [Hash] Event data
        # @return [Boolean] true if event should be saved to DLQ
        def should_save?(event_data)
          event_name = event_data[:event_name].to_s
          severity = event_data[:severity]

          # Priority 1: Always discard (highest priority)
          if matches_patterns?(event_name, @always_discard_patterns)
            increment_metric("e11y.dlq.filter.discarded", reason: "always_discard_pattern")
            return false
          end

          # Priority 2: Always save
          if matches_patterns?(event_name, @always_save_patterns)
            increment_metric("e11y.dlq.filter.saved", reason: "always_save_pattern")
            return true
          end

          # Priority 3: Severity-based
          if @save_severities.include?(severity)
            increment_metric("e11y.dlq.filter.saved", reason: "severity")
            return true
          end

          # Priority 4: Default behavior
          if @default_behavior == :save
            increment_metric("e11y.dlq.filter.saved", reason: "default")
            true
          else
            increment_metric("e11y.dlq.filter.discarded", reason: "default")
            false
          end
        end

        # Get filter statistics.
        #
        # @return [Hash] Filter configuration stats
        def stats
          {
            always_save_patterns: @always_save_patterns.map(&:inspect),
            always_discard_patterns: @always_discard_patterns.map(&:inspect),
            save_severities: @save_severities,
            default_behavior: @default_behavior
          }
        end

        private

        # Check if event name matches any of the patterns.
        #
        # @param event_name [String] Event name
        # @param patterns [Array<Regexp>] Patterns to match
        # @return [Boolean] true if event matches any pattern
        def matches_patterns?(event_name, patterns)
          patterns.any? { |pattern| pattern.match?(event_name) }
        end

        # Increment DLQ filter metric.
        #
        # @param metric_name [String] Metric name
        # @param tags [Hash] Additional tags
        def increment_metric(metric_name, tags = {})
          # TODO: Integrate with Yabeda metrics
          # E11y::Metrics.increment(metric_name, tags)
        end
      end
    end
  end
end
