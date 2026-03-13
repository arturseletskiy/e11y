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
        # @param error [StandardError, nil] The error that caused the DLQ save (optional, for context)
        # @return [Boolean] true if event should be saved to DLQ
        # rubocop:disable Metrics/MethodLength
        # DLQ filter requires 4-priority decision tree with metrics tracking for each branch
        def should_save?(event_data, _error = nil)
          event_name = event_data[:event_name].to_s
          severity = event_data[:severity]

          # Priority 1: Always discard (highest priority)
          if matches_patterns?(event_name, @always_discard_patterns)
            increment_filter_metric("discarded", "always_discard_pattern")
            return false
          end

          # Priority 2: Always save
          if matches_patterns?(event_name, @always_save_patterns)
            increment_filter_metric("saved", "always_save_pattern")
            return true
          end

          # Priority 3: Severity-based
          if @save_severities.include?(severity)
            increment_filter_metric("saved", "severity")
            return true
          end

          # Priority 4: Default behavior
          if @default_behavior == :save
            increment_filter_metric("saved", "default")
            true
          else
            increment_filter_metric("discarded", "default")
            false
          end
        end
        # rubocop:enable Metrics/MethodLength

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

        # Increment consolidated DLQ filter decision metric.
        #
        # @param action [String] "saved" or "discarded"
        # @param reason [String] always_discard_pattern, always_save_pattern, severity, default
        def increment_filter_metric(action, reason)
          return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)

          E11y::Metrics.increment(:e11y_dlq_filter_decisions_total, { action: action, reason: reason })
        end
      end
    end
  end
end
