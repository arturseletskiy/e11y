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

    puts "#{'Event Name'.ljust(name_width)} #{'Class'.ljust(class_width)} Severity  Adapters"
    puts "-" * (name_width + class_width + 20)

    classes.each do |klass|
      name = (klass.respond_to?(:event_name) ? klass.event_name : klass.name).to_s
      severity = (klass.respond_to?(:severity) ? klass.severity : "—").to_s
      adapters = (klass.respond_to?(:adapters) ? Array(klass.adapters).join(", ") : "—").to_s
      puts "#{name.ljust(name_width)} #{klass.name.to_s.ljust(class_width)} #{severity.ljust(8)} #{adapters}"
    end

    puts "-" * (name_width + class_width + 20)
    puts "#{classes.size} events"
  end
end
