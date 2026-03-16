# frozen_string_literal: true

namespace :e11y do
  namespace :slo do
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
        puts "✅ slo.yml is valid"
      else
        puts "❌ slo.yml validation failed:"
        errors.each { |e| puts "  #{e}" }
        exit 1
      end
    end
  end
end
