# frozen_string_literal: true

module E11y
  module SLO
    # Validates slo.yml schema: version, endpoints (controller/pattern), app_wide.aggregated_slo.
    class ConfigValidator
      class << self
        def validate(config)
          return ["Config is nil or empty"] if config.nil? || config.empty?

          errors = []
          errors.concat(validate_version(config))
          errors.concat(validate_endpoints(config["endpoints"]))
          errors.concat(validate_app_wide(config["app_wide"]))
          errors.concat(validate_e11y_self_monitoring(config["e11y_self_monitoring"]))
          errors
        end

        private

        def validate_version(config)
          return ["Missing required key: version"] unless config.key?("version")

          []
        end

        def validate_endpoints(endpoints)
          return [] if endpoints.nil? || endpoints.empty?

          errors = []
          endpoints.each_with_index do |ep, i|
            errors << "endpoints[#{i}]: missing controller or pattern" if ep["controller"].to_s.empty? && ep["pattern"].to_s.empty?
          end
          errors
        end

        def validate_app_wide(app_wide)
          return [] if app_wide.nil?

          agg = app_wide["aggregated_slo"]
          return [] if agg.nil? || !agg["enabled"]

          errors = []
          errors << "app_wide.aggregated_slo: strategy required when enabled" if agg["strategy"].to_s.empty?
          errors << "app_wide.aggregated_slo: components required" if agg["components"].to_a.empty?
          errors
        end

        def validate_e11y_self_monitoring(e11y_self_monitoring)
          return [] if e11y_self_monitoring.nil? || !e11y_self_monitoring["enabled"]

          # When enabled, targets structure is optional; no validation errors for now
          []
        end
      end
    end
  end
end
