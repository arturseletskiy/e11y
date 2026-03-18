# frozen_string_literal: true

require "e11y/linters/base"
require "e11y/registry"

module E11y
  module Linters
    module SLO
      # Linter for SLO-enabled events: requires slo_status_from and contributes_to.
      #
      # When an event has slo_enabled?, it must define:
      # - slo_status_from (slo_config.slo_status_proc) — how to compute slo_status from payload
      # - contributes_to (slo_config.contributes_to_value) — which custom SLO this event feeds
      class SloStatusFromLinter
        class << self
          # Validate all SLO-enabled event classes have slo_status_from and contributes_to.
          #
          # @raise [E11y::Linters::LinterError] when any slo-enabled event is missing either
          def validate!
            errors = []

            E11y::Registry.event_classes.each do |event_class|
              next unless event_class.slo_enabled?

              config = event_class.slo_config
              name = event_class.respond_to?(:event_name) ? event_class.event_name : event_class.name

              errors << "Event #{name} has slo enabled but missing slo_status_from" unless config&.slo_status_proc

              errors << "Event #{name} has slo enabled but missing contributes_to" unless config&.contributes_to_value
            end

            return if errors.empty?

            raise LinterError, errors.join("\n")
          end
        end
      end
    end
  end
end
