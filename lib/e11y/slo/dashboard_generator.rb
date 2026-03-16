# frozen_string_literal: true

require "json"

module E11y
  module SLO
    class DashboardGenerator
      class << self
        def generate(config)
          return "{}" if config.nil? || config.empty?

          panels = []
          panels.concat(build_endpoint_panels(config["endpoints"]))
          panels.concat(build_app_wide_panels(config["app_wide"]))
          panels.concat(build_event_slo_panels(config["custom_slos"])) if config["custom_slos"]

          dashboard = {
            title: "E11y SLO Dashboard",
            panels: panels,
            schemaVersion: 38,
            version: 1
          }
          JSON.pretty_generate(dashboard)
        end

        private

        def build_endpoint_panels(endpoints)
          return [] if endpoints.to_a.empty?

          [{
            id: 1,
            title: "HTTP Availability (Per-Endpoint)",
            type: "timeseries",
            targets: [{
              expr: "sum(rate(e11y_slo_http_requests_total{status=~\"2..|3..\"}[30d])) by (controller, action) / sum(rate(e11y_slo_http_requests_total[30d])) by (controller, action)",
              legendFormat: '{{controller}}#{{action}}'
            }]
          }]
        end

        def build_event_slo_panels(custom_slos)
          custom_slos.map.with_index do |slo, i|
            name = slo["name"] || "event_slo_#{i}"
            {
              id: 10 + i,
              title: "Event SLO: #{name}",
              type: "timeseries",
              targets: [{
                expr: "sum(rate(e11y_slo_event_result_total{slo_name=\"#{name}\",slo_status=\"success\"}[30d])) / sum(rate(e11y_slo_event_result_total{slo_name=\"#{name}\"}[30d]))",
                legendFormat: "success_rate"
              }]
            }
          end
        end

        def build_app_wide_panels(app_wide)
          return [] if app_wide.nil?

          agg = app_wide["aggregated_slo"]
          return [] if agg.nil? || !agg["enabled"]

          components = agg["components"] || []
          return [] if components.empty?

          window = agg["window"] || "30d"

          expr = case agg["strategy"].to_s
                 when "min"
                   build_min_expr(components, window)
                 else
                   build_weighted_expr(components, window)
                 end

          [{
            id: 100,
            title: "App-Wide Aggregated SLO",
            type: "timeseries",
            targets: [{ expr: expr, legendFormat: "aggregated" }],
            fieldConfig: { defaults: { min: 0.99, max: 1.0 } }
          }]
        end

        def build_weighted_expr(components, window)
          parts = components.map do |c|
            weight = c["weight"] || 1.0 / components.size
            metric = (c["metric"] || "").gsub(/\[\d+d\]/, "[#{window}]")
            metric = metric.strip
            "(#{weight} * (#{metric}))"
          end
          parts.join(" + ")
        end

        def build_min_expr(components, window)
          parts = components.map do |c|
            metric = (c["metric"] || "").gsub(/\[\d+d\]/, "[#{window}]")
            metric.strip
          end
          "min(#{parts.join(", ")})"
        end
      end
    end
  end
end
