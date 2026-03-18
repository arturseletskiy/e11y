# frozen_string_literal: true

require "e11y/linters/base"
require "e11y/registry"

module E11y
  module Linters
    module SLO
      # Linter for explicit SLO declaration on Event classes.
      #
      # Ensures every registered event class has either `slo do ... end` or
      # `slo false` — i.e. slo_enabled? or slo_disabled? must be true.
      class ExplicitDeclarationLinter
        class << self
          # Validate all registered event classes have explicit SLO declaration.
          #
          # @raise [E11y::Linters::LinterError] when any event has neither slo_enabled? nor slo_disabled?
          def validate!
            errors = []

            E11y::Registry.event_classes.each do |event_class|
              next if event_class.slo_enabled? || event_class.slo_disabled?

              name = event_class.respond_to?(:event_name) ? event_class.event_name : event_class.name
              errors << "Event #{name} missing explicit SLO declaration! Add `slo do ... end` or `slo false`"
            end

            return if errors.empty?

            raise LinterError, errors.join("\n")
          end
        end
      end
    end
  end
end
