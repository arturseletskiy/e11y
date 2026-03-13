# frozen_string_literal: true

require "rails/generators"

module E11y
  module Generators
    # Generates Prometheus alerting rules for E11y metrics.
    #
    # @example
    #   rails g e11y:prometheus_alerts
    #   # => creates config/prometheus/e11y_alerts.yml
    class PrometheusAlertsGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates Prometheus alerting rules for E11y in config/prometheus/."

      def create_alerts
        empty_directory "config/prometheus"
        template "e11y_alerts.yml", "config/prometheus/e11y_alerts.yml"
      end

      def show_readme
        say "\n✅ Prometheus alerts created: config/prometheus/e11y_alerts.yml", :green
        say "   Load via prometheus.yml rule_files section:\n"
        say "     rule_files:\n       - config/prometheus/e11y_alerts.yml\n"
      end
    end
  end
end
