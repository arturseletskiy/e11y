# frozen_string_literal: true

module E11y
  module Reliability
    module DLQ
      # DLQ Filter determines which failed events should be saved to DLQ.
      #
      # Uses Event DSL (use_dlq) when event class is registered.
      # Audit events (Presets::AuditEvent) have use_dlq true by default.
      #
      # Priority order:
      # 1. Event class use_dlq == false → discard
      # 2. Event class use_dlq == true → save
      # 3. Severity-based (save_severities)
      # 4. Default behavior
      #
      # @example Event DSL
      #   class Events::AuditLogin < E11y::Events::BaseAuditEvent
      #     # use_dlq true from preset
      #   end
      #
      #   class Events::DebugTrace < E11y::Event::Base
      #     use_dlq false
      #   end
      #
      # @see ADR-013 §4.3 (DLQ Filter)
      # @see UC-021 §3.2 (DLQ Filter Configuration)
      class Filter
        # @param save_severities [Array<Symbol>] Severities to always save (:error, :fatal)
        # @param default_behavior [Symbol] Default when no Event DSL rule (:save or :discard)
        def initialize(
          save_severities: %i[error fatal],
          default_behavior: :save
        )
          @save_severities = save_severities
          @default_behavior = default_behavior
        end

        # Check if event should be saved to DLQ.
        #
        # @param event_data [Hash] Event data
        # @param error [StandardError, nil] The error that caused the DLQ save (optional)
        # @return [Boolean] true if event should be saved to DLQ
        # rubocop:disable Metrics/MethodLength
        def should_save?(event_data, _error = nil)
          event_class = resolve_event_class(event_data[:event_name])
          severity = event_data[:severity]

          # Priority 1: Event DSL use_dlq == false
          if event_class.respond_to?(:use_dlq) && event_class.use_dlq == false
            increment_filter_metric("discarded", "use_dlq")
            return false
          end

          # Priority 2: Event DSL use_dlq == true
          if event_class.respond_to?(:use_dlq) && event_class.use_dlq == true
            increment_filter_metric("saved", "use_dlq")
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

        # @return [Hash] Filter configuration stats
        def stats
          {
            save_severities: @save_severities,
            default_behavior: @default_behavior
          }
        end

        private

        def resolve_event_class(event_name)
          return nil unless event_name
          return nil unless defined?(E11y::Registry) && E11y::Registry.respond_to?(:find)

          E11y::Registry.find(event_name.to_s)
        end

        def increment_filter_metric(action, reason)
          return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)

          E11y::Metrics.increment(:e11y_dlq_filter_decisions_total, { action: action, reason: reason })
        end
      end
    end
  end
end
