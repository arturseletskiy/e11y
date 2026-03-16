# frozen_string_literal: true

namespace :e11y do
  desc "List registered events (like rake routes). Filter: SEVERITY=error ADAPTER=logs GREP=order"
  task events: :environment do
    require "e11y/registry"

    begin
      Rails.application.eager_load! if defined?(Rails) && Rails.application.respond_to?(:eager_load!)
    rescue Zeitwerk::SetupRequired
      # Zeitwerk not ready (e.g. dummy app with eager_load=false); use already-loaded events
    end

    criteria = {}
    criteria[:severity] = ENV["SEVERITY"]&.to_sym if ENV["SEVERITY"]
    criteria[:adapter] = ENV["ADAPTER"]&.to_sym if ENV["ADAPTER"]
    grep = ENV.fetch("GREP", nil)

    classes = criteria.any? ? E11y::Registry.where(**criteria) : E11y::Registry.event_classes
    classes = classes.select { |c| (c.respond_to?(:event_name) ? c.event_name : c.name).to_s.include?(grep) } if grep

    # Column widths (rake routes style)
    name_width = [classes.map { |c| (c.respond_to?(:event_name) ? c.event_name : c.name).to_s.length }.max || 20, 24].max
    class_width = [classes.map { |c| c.name.to_s.length }.max || 30, 36].max
    schema_max = 40
    schema_width = [classes.map { |c| schema_str(c).length }.max || 20, schema_max].min

    header = "#{'Event Name'.ljust(name_width)} #{'Class'.ljust(class_width)} Ver  Sev   Adapters #{'Schema'.ljust(schema_width)} PII   Audit"
    sep_len = header.length

    puts header
    puts "-" * sep_len

    classes.each do |klass|
      name = (klass.respond_to?(:event_name) ? klass.event_name : klass.name).to_s
      version = klass.respond_to?(:version) ? "v#{klass.version}" : "—"
      severity = (klass.respond_to?(:severity) ? klass.severity : "—").to_s
      adapters = (klass.respond_to?(:adapters) && Array(klass.adapters).any? ? Array(klass.adapters).join(",") : "—").to_s
      schema = schema_str(klass)
      schema = "#{schema[0...(schema_max - 3)]}..." if schema.length > schema_max
      pii = pii_str(klass)
      audit = klass.respond_to?(:audit_event?) && klass.audit_event? ? "✓" : "—"
      puts "#{name.ljust(name_width)} #{klass.name.to_s.ljust(class_width)} #{version.ljust(4)} #{severity.ljust(5)} #{adapters.ljust(12)} #{schema.ljust(schema_width)} #{pii.ljust(6)} #{audit}"
    end

    puts "-" * sep_len
    puts "#{classes.size} events"
  end
end

# Helpers for e11y:events (rake routes style)
def schema_str(klass)
  return "—" unless klass.respond_to?(:compiled_schema)

  schema = klass.compiled_schema
  return "—" if schema.nil? || !schema.respond_to?(:key_map)

  schema.key_map.keys.map(&:name).join(", ")
rescue StandardError
  "—"
end

def pii_str(klass)
  return "—" unless klass.respond_to?(:pii_filtering_mode)

  klass.pii_filtering_mode.to_s.tr("_", " ")
rescue StandardError
  "—"
end
