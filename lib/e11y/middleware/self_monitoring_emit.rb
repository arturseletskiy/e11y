# frozen_string_literal: true

require "e11y/middleware/base"
require "e11y/slo/config_loader"

module E11y
  module Middleware
    # SelfMonitoringEmit middleware — emits e11y_events_tracked_total at pipeline end.
    #
    # When e11y_self_monitoring.enabled is true in slo.yml, increments the counter
    # for each event that reaches the end of the pipeline (after EventSlo).
    #
    # **Middleware Zone:** `:post_processing` (last in pipeline)
    #
    # @example slo.yml
    #   e11y_self_monitoring:
    #     enabled: true
    #     targets:
    #       reliability: 0.999
    #
    # @see docs/plans/2026-03-13-slo-linters-self-monitoring-plan.md
    class SelfMonitoringEmit < Base
      middleware_zone :post_processing

      # Process event and optionally emit self-monitoring metric.
      #
      # @param event_data [Hash, nil] Event payload (nil passes through)
      # @return [Hash, nil] Unchanged event_data (passthrough)
      def call(event_data)
        if event_data && E11y::SLO::ConfigLoader.self_monitoring_enabled?
          event_name = event_data[:event_name].to_s.presence || "unknown"
          E11y::Metrics.increment(:e11y_events_tracked_total, result: "success", event_name: event_name)
        end

        @app&.call(event_data) || event_data
      end
    end
  end
end
