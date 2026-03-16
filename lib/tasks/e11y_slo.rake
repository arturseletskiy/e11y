# frozen_string_literal: true

namespace :e11y do
  namespace :slo do
    desc "Validate slo.yml configuration"
    task validate: :environment do
      require "e11y/slo/config_loader"
      require "e11y/slo/config_validator"

      config = E11y::SLO::ConfigLoader.load
      if config.nil?
        puts "⚠️  slo.yml not found (optional)"
        next
      end

      errors = E11y::SLO::ConfigValidator.validate(config)
      if errors.empty?
        require "e11y/linters/slo/explicit_declaration_linter"
        require "e11y/linters/slo/slo_status_from_linter"
        require "e11y/linters/slo/config_consistency_linter"

        E11y::Linters::SLO::ExplicitDeclarationLinter.validate!
        E11y::Linters::SLO::SloStatusFromLinter.validate!
        E11y::Linters::SLO::ConfigConsistencyLinter.validate!

        puts "✅ slo.yml is valid"
      else
        puts "❌ slo.yml validation failed:"
        errors.each { |e| puts "  #{e}" }
        exit 1
      end
    rescue E11y::Linters::LinterError => e
      puts "❌ SLO linter failed: #{e.message}"
      exit 1
    end

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
      out = defined?(Rails) && Rails.respond_to?(:root) ? Rails.root.join("config", "grafana", "e11y_slo_dashboard.json") : Pathname.new(File.join(Dir.pwd, "config", "grafana", "e11y_slo_dashboard.json"))
      FileUtils.mkdir_p(out.dirname)
      File.write(out, json)
      puts "✅ Dashboard written to #{out}"
    end
  end
end
