# frozen_string_literal: true

namespace :e11y do
  namespace :docs do
    desc "Generate event docs (Markdown). Filter: SEVERITY=error ADAPTER=logs GREP=order"
    task generate: :environment do
      require "e11y/documentation/generator"

      begin
        Rails.application.eager_load! if defined?(Rails) && Rails.application.respond_to?(:eager_load!)
      rescue Zeitwerk::SetupRequired
        # Zeitwerk not ready (e.g. dummy app with eager_load=false); use already-loaded events
      end

      criteria = {}
      criteria[:severity] = ENV["SEVERITY"]&.to_sym if ENV["SEVERITY"]
      criteria[:adapter] = ENV["ADAPTER"]&.to_sym if ENV["ADAPTER"]
      grep = ENV.fetch("GREP", nil)

      out = if defined?(Rails) && Rails.respond_to?(:root)
              Rails.root.join("docs", "events")
            else
              Pathname.new(File.join(Dir.pwd, "docs", "events"))
            end

      E11y::Documentation::Generator.generate(out.to_s, criteria: criteria, grep: grep)
      puts "✅ Documentation generated in #{out}"
    end
  end
end
