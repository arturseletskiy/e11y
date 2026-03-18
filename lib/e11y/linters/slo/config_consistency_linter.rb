# frozen_string_literal: true

require "e11y/linters/base"
require "e11y/slo/config_loader"

module E11y
  module Linters
    module SLO
      # Linter for slo.yml custom_slos consistency with Event class definitions.
      #
      # Ensures every event referenced in slo.yml custom_slos:
      # - Exists (constantize succeeds)
      # - Has slo enabled (slo_enabled?)
      # - Has contributes_to matching the slo_name in config
      class ConfigConsistencyLinter
        class << self
          # Validate slo.yml custom_slos against Event class definitions.
          #
          # @param search_paths [Array<String>, nil] Optional search paths for ConfigLoader.
          #   When nil, ConfigLoader uses default paths.
          # @raise [E11y::Linters::LinterError] when any event fails validation
          def validate!(search_paths: nil)
            config = if search_paths
                       E11y::SLO::ConfigLoader.load(search_paths: search_paths)
                     else
                       E11y::SLO::ConfigLoader.load
                     end

            return if config.nil?
            return if config["custom_slos"].nil? || config["custom_slos"].empty?

            errors = []

            config["custom_slos"].each do |slo|
              slo_name = slo["name"]
              events = slo["events"] || []

              events.each do |event_class_name|
                error = validate_event(slo_name, event_class_name)
                errors << error if error
              end
            end

            return if errors.empty?

            raise LinterError, errors.join("\n")
          end

          private

          def validate_event(slo_name, event_class_name)
            event_class = constantize_event(event_class_name)
            return "Event class '#{event_class_name}' does not exist (constantize failed)" if event_class.nil?

            unless event_class.respond_to?(:slo_enabled?) && event_class.slo_enabled?
              return "Event #{event_class_name} is referenced in slo.yml (SLO '#{slo_name}') but has slo disabled"
            end

            contributes_to = event_class.slo_config&.contributes_to_value
            unless contributes_to == slo_name
              return "Event #{event_class_name} contributes_to '#{contributes_to}' but slo.yml defines SLO '#{slo_name}'"
            end

            nil
          end

          def constantize_event(event_class_name)
            Object.const_get(event_class_name)
          rescue NameError
            nil
          end
        end
      end
    end
  end
end
