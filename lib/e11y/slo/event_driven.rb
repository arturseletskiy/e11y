# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SLO
    # Event-Driven SLO for business logic reliability (ADR-014).
    #
    # Provides DSL for Event classes to opt-in to SLO tracking, auto-calculate
    # `slo_status` from payload, and emit metrics for custom business SLO.
    #
    # **Key Features:**
    # - Explicit opt-in via `slo { enabled true }` in Event class
    # - Auto-calculation of `slo_status` from payload (e.g., status == 'completed' → 'success')
    # - Explicit override: `track(status: 'completed', slo_status: 'failure')`
    # - Metrics export: `event_result_total{slo_status="success|failure"}`
    # - Custom SLO configuration in `slo.yml` (optional)
    #
    # **ADR References:**
    # - ADR-014 §3 (Event SLO DSL)
    # - ADR-014 §4 (SLO Status Calculation)
    # - ADR-014 §6 (Metrics Export)
    #
    # **Use Case:** UC-014 (Event-Driven SLO)
    #
    # @example Event with SLO enabled
    #   module Events
    #     class PaymentProcessed < E11y::Event::Base
    #       schema do
    #         required(:payment_id).filled(:string)
    #         required(:status).filled(:string)
    #         optional(:slo_status).filled(:string)  # Explicit override
    #       end
    #
    #       slo do
    #         enabled true
    #         slo_status_from do |payload|
    #           return payload[:slo_status] if payload[:slo_status]
    #           case payload[:status]
    #           when 'completed' then 'success'
    #           when 'failed' then 'failure'
    #           else nil  # Not counted in SLO
    #           end
    #         end
    #       end
    #     end
    #   end
    #
    # @example Tracking with auto-calculated slo_status
    #   Events::PaymentProcessed.track(
    #     payment_id: 'p123',
    #     status: 'completed'  # → slo_status = 'success'
    #   )
    #
    # @example Tracking with explicit override
    #   Events::PaymentProcessed.track(
    #     payment_id: 'p456',
    #     status: 'completed',
    #     slo_status: 'failure'  # Explicit override (e.g., fraud detected)
    #   )
    #
    # @see ADR-014 for complete architecture
    module EventDriven
      # SLO configuration for an Event class.
      class SLOConfig
        attr_reader :slo_status_proc, :contributes_to_value, :group_by_field

        def initialize
          @enabled = false
          @slo_status_proc = nil
          @contributes_to_value = nil
          @group_by_field = nil
        end

        # DSL method: Enable or disable SLO tracking.
        #
        # @param value [Boolean] true to enable, false to disable
        def enabled(value = nil)
          return @enabled if value.nil?

          @enabled = value
        end

        # Check if SLO is enabled.
        #
        # @return [Boolean]
        def enabled?
          @enabled
        end

        # DSL method: Define how to calculate slo_status from payload.
        #
        # @yieldparam payload [Hash] Event payload
        # @yieldreturn [String, nil] 'success', 'failure', or nil (not counted)
        def slo_status_from(&block)
          @slo_status_proc = block
        end

        # DSL method: Define which custom SLO this event contributes to.
        #
        # @param slo_name [String] Name of custom SLO (from slo.yml)
        def contributes_to(slo_name = nil)
          return @contributes_to_value if slo_name.nil?

          @contributes_to_value = slo_name
        end

        # DSL method: Group SLO metrics by a specific field.
        #
        # @param field [Symbol] Field name to group by (e.g., :payment_method)
        def group_by(field = nil)
          return @group_by_field if field.nil?

          @group_by_field = field
        end
      end

      # DSL methods for Event classes (extend with this module).
      module DSL
        # DSL method: Configure SLO for this Event class.
        #
        # @yieldparam config [SLOConfig] SLO configuration object
        # @return [void]
        #
        # @example Enable SLO
        #   slo do
        #     enabled true
        #     slo_status_from { |payload| payload[:status] == 'success' ? 'success' : 'failure' }
        #   end
        #
        # @example Disable SLO (explicit)
        #   slo do
        #     enabled false
        #   end
        def slo(&)
          @slo_config ||= SLOConfig.new
          @slo_config.instance_eval(&) if block_given?
          @slo_config
        end

        # Get SLO configuration for this Event class.
        #
        # @return [SLOConfig, nil] SLO config or nil if not defined
        def slo_config
          @slo_config
        end

        def slo_enabled?
          slo_config&.enabled? == true
        end

        def slo_disabled?
          slo_config ? !slo_config.enabled? : false
        end
      end
    end
  end
end
