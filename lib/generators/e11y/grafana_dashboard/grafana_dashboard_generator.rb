# frozen_string_literal: true

require "rails/generators"

module E11y
  module Generators
    # Generates a Grafana dashboard JSON for E11y metrics.
    #
    # Requires Yabeda/Prometheus integration.
    #
    # @example
    #   rails g e11y:grafana_dashboard
    #   # => creates config/grafana/e11y_dashboard.json
    class GrafanaDashboardGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a Grafana dashboard JSON for E11y metrics in config/grafana/."

      def create_dashboard
        empty_directory "config/grafana"
        template "e11y_dashboard.json", "config/grafana/e11y_dashboard.json"
      end

      def show_readme
        say "\n✅ Grafana dashboard created: config/grafana/e11y_dashboard.json", :green
        say "   Import it via Grafana → Dashboards → Import → Upload JSON file\n"
      end
    end
  end
end
