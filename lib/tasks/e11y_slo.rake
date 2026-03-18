# frozen_string_literal: true

namespace :e11y do
  namespace :slo do
    desc "Generate Grafana dashboard from slo.yml"
    task dashboard: :environment do
      require "e11y/slo/config_loader"
      require "e11y/slo/dashboard_generator"

      config = E11y::SLO::ConfigLoader.load
      if config.nil?
        puts "⚠️  slo.yml not found, generating empty dashboard"
        config = {}
      end

      json = E11y::SLO::DashboardGenerator.generate(config)
      out = if defined?(Rails) && Rails.respond_to?(:root)
              Rails.root.join("config", "grafana",
                              "e11y_slo_dashboard.json")
            else
              Pathname.new(File.join(Dir.pwd, "config",
                                     "grafana", "e11y_slo_dashboard.json"))
            end
      FileUtils.mkdir_p(out.dirname)
      File.write(out, json)
      puts "✅ Dashboard written to #{out}"
    end
  end
end
