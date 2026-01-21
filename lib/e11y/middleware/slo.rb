# frozen_string_literal: true

require "e11y/middleware/base"
require "e11y/slo/event_driven"

module E11y
  module Middleware
    # SLO Middleware for Event-Driven SLO tracking (ADR-014).
    #
    # Automatically processes events with SLO configuration enabled,
    # computes `slo_status` from payload, and emits metrics.
    #
    # **Features:**
    # - Auto-detects events with `slo { enabled true }`
    # - Calls `slo_status_from` proc to compute 'success'/'failure'
    # - Emits `slo_event_result_total{slo_status}` metric to Yabeda
    # - Never fails event tracking (graceful error handling)
    #
    # **Middleware Zone:** `:post_processing` (after routing, before adapters)
    #
    # **ADR References:**
    # - ADR-014 §3 (Event SLO DSL)
    # - ADR-014 §4 (SLO Status Calculation)
    # - ADR-014 §6 (Metrics Export)
    # - ADR-015 §3 (Middleware Order)
    #
    # **Use Case:** UC-014 (Event-Driven SLO)
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     # Enable SLO middleware (auto-enabled if any Events have slo { enabled true })
    #     config.pipeline.use E11y::Middleware::SLO, zone: :post_processing
    #   end
    #
    # @example Event with SLO
    #   module Events
    #     class PaymentProcessed < E11y::Event::Base
    #       schema do
    #         required(:payment_id).filled(:string)
    #         required(:status).filled(:string)
    #       end
    #
    #       slo do
    #         enabled true
    #         slo_status_from do |payload|
    #           case payload[:status]
    #           when 'completed' then 'success'
    #           when 'failed' then 'failure'
    #           else nil  # Not counted
    #           end
    #         end
    #       end
    #     end
    #   end
    #
    #   # Tracking will automatically emit SLO metric:
    #   Events::PaymentProcessed.track(payment_id: 'p123', status: 'completed')
    #   # → Emits: slo_event_result_total{event_name="payment.processed", slo_status="success"} +1
    #
    # @see ADR-014 for complete Event-Driven SLO architecture
    class SLO < Base
      middleware_zone :post_processing

      # Process event and emit SLO metric if SLO is enabled.
      #
      # @param event_data [Hash] Event payload
      # @return [Hash] Unchanged event_data (passthrough)
      def call(event_data)
        # Skip if SLO not enabled for this event
        event_class = resolve_event_class(event_data)
        return event_data unless event_class.respond_to?(:slo_config)
        return event_data unless event_class.slo_config&.enabled

        # Compute slo_status from payload
        slo_status = compute_slo_status(event_class, event_data[:payload])
        return event_data unless slo_status

        # Emit SLO metric
        emit_slo_metric(event_class, slo_status, event_data[:payload])

        event_data # Passthrough (never modify event_data)
      rescue StandardError => e
        # Never fail event tracking due to SLO processing
        E11y.logger.error(
          "[E11y::Middleware::SLO] SLO processing failed for #{event_data[:event_name]}: #{e.message}"
        )
        event_data
      end

      private

      # Resolve Event class from event_name.
      #
      # @param event_data [Hash] Event payload
      # @return [Class, nil] Event class or nil if not found
      def resolve_event_class(event_data)
        event_name = event_data[:event_name]
        return nil unless event_name

        # Convert event_name to class name (e.g., "payment.processed" → "Events::PaymentProcessed")
        # This assumes Rails autoloading or explicit requires
        class_name = event_name.to_s.split(".").map(&:capitalize).join
        "Events::#{class_name}".constantize
      rescue NameError
        # Event class not found (may be from external source)
        nil
      end

      # Compute slo_status using event's slo_status_from proc.
      #
      # @param event_class [Class] Event class
      # @param payload [Hash] Event payload
      # @return [String, nil] 'success', 'failure', or nil
      def compute_slo_status(event_class, payload)
        return nil unless event_class.slo_config.slo_status_proc

        event_class.slo_config.slo_status_proc.call(payload)
      rescue StandardError => e
        E11y.logger.error(
          "[E11y::Middleware::SLO] Failed to compute slo_status for #{event_class.name}: #{e.message}"
        )
        nil
      end

      # Emit SLO metric to Yabeda/Prometheus.
      #
      # @param event_class [Class] Event class
      # @param slo_status [String] 'success' or 'failure'
      # @param payload [Hash] Event payload
      # @return [void]
      def emit_slo_metric(event_class, slo_status, payload)
        labels = build_slo_labels(event_class, slo_status, payload)

        E11y::Metrics.increment(:slo_event_result_total, labels)
      rescue StandardError => e
        E11y.logger.error(
          "[E11y::Middleware::SLO] Failed to emit SLO metric for #{event_class.name}: #{e.message}"
        )
      end

      # Build metric labels for SLO.
      #
      # @param event_class [Class] Event class
      # @param slo_status [String] 'success' or 'failure'
      # @param payload [Hash] Event payload
      # @return [Hash] Metric labels
      def build_slo_labels(event_class, slo_status, payload)
        labels = {
          event_name: event_class.event_name,
          slo_status: slo_status
        }

        # Add custom SLO name if configured
        labels[:slo_name] = event_class.slo_config.contributes_to if event_class.slo_config.contributes_to

        # Add group_by field if configured
        if event_class.slo_config.group_by_field
          field = event_class.slo_config.group_by_field
          labels[:group_by] = payload[field].to_s if payload[field]
        end

        labels
      end
    end
  end
end
