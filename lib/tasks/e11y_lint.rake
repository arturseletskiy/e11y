# frozen_string_literal: true

namespace :e11y do
  desc "Validate slo.yml, SLO linters, and PII declarations (all-in-one)"
  task lint: :environment do
    all_ok = true

    # 1. SLO config validation + SLO linters
    begin
      require "e11y/slo/config_loader"
      require "e11y/slo/config_validator"

      config = E11y::SLO::ConfigLoader.load
      if config.nil?
        puts "⚠️  slo.yml not found (optional, skipping SLO checks)"
      else
        errors = E11y::SLO::ConfigValidator.validate(config)
        if errors.any?
          puts "❌ slo.yml validation failed:"
          errors.each { |e| puts "  #{e}" }
          all_ok = false
        else
          require "e11y/linters/slo/explicit_declaration_linter"
          require "e11y/linters/slo/slo_status_from_linter"
          require "e11y/linters/slo/config_consistency_linter"

          E11y::Linters::SLO::ExplicitDeclarationLinter.validate!
          E11y::Linters::SLO::SloStatusFromLinter.validate!
          E11y::Linters::SLO::ConfigConsistencyLinter.validate!
          puts "✅ SLO config and linters OK"
        end
      end
    rescue E11y::Linters::LinterError => e
      puts "❌ SLO linter failed: #{e.message}"
      all_ok = false
    end

    # 2. PII linter
    begin
      require "e11y/linters/pii/pii_declaration_linter"

      E11y::Linters::PII::PiiDeclarationLinter.validate_all!
      puts "✅ PII declarations OK"
    rescue E11y::Linters::PII::PiiDeclarationError => e
      puts "❌ PII linter failed:\n\n#{e.message}"
      all_ok = false
    end

    # 3. Schema check (each event has compiled_schema)
    begin
      require "e11y/registry"
      begin
        Rails.application.eager_load! if defined?(Rails) && Rails.application.respond_to?(:eager_load!)
      rescue Zeitwerk::SetupRequired
        # Zeitwerk not ready (e.g. dummy app with eager_load=false); use already-loaded events
      end
      schema_errors = []
      E11y::Registry.event_classes.each do |klass|
        next if klass.respond_to?(:compiled_schema) && klass.compiled_schema
        name = klass.respond_to?(:event_name) ? klass.event_name : klass.name
        schema_errors << "#{klass.name} (#{name}): missing schema"
      end
      if schema_errors.any?
        puts "❌ Schema check failed:"
        schema_errors.each { |e| puts "  #{e}" }
        all_ok = false
      else
        puts "✅ Schema check OK"
      end
    rescue => e
      puts "❌ Schema check failed: #{e.message}"
      all_ok = false
    end

    exit 1 unless all_ok
  end
end

# Backwards compatibility: old tasks invoke e11y:lint
task "e11y:slo:validate" do
  Rake::Task["e11y:lint"].invoke
end

namespace :e11y do
  namespace :lint do
    task pii: :environment do
      Rake::Task["e11y:lint"].invoke
    end
  end
end
