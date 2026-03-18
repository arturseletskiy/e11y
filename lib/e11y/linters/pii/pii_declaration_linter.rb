# frozen_string_literal: true

require "e11y/linters/base"
require "e11y/registry"

module E11y
  module Linters
    module PII
      # Linter for explicit PII declaration on Event classes.
      #
      # When an event declares `contains_pii true`, every schema field must have
      # an explicit PII strategy in the pii_filtering block.
      #
      # @see ADR-006 §3.0.5 PII Declaration Linter
      # @see UC-007 PII Filtering
      class PiiDeclarationLinter
        VALID_STRATEGIES = %i[allow skip mask hash redact partial truncate encrypt].freeze

        class << self
          # Validate all registered event classes.
          #
          # @raise [E11y::Linters::PiiDeclarationError] when any event with contains_pii true has missing/invalid declarations
          def validate_all!
            errors = []

            E11y::Registry.event_classes.each do |event_class|
              validate!(event_class)
            rescue PiiDeclarationError => e
              errors << e.message
            end

            raise PiiDeclarationError, errors.join("\n\n") if errors.any?
          end

          # Validate a single event class.
          #
          # @param event_class [Class] Event class to validate
          # @raise [E11y::Linters::PiiDeclarationError] when validation fails
          def validate!(event_class)
            return unless event_class.contains_pii == true

            schema_fields = extract_schema_keys(event_class)
            return if schema_fields.nil? || schema_fields.empty?

            pii_config = event_class.pii_filtering_config
            declared_fields = pii_config&.dig(:fields)&.keys&.map(&:to_s) || []

            missing = schema_fields.map(&:to_s) - declared_fields
            raise PiiDeclarationError, build_missing_message(event_class, missing) if missing.any?

            # Validate each declared field has valid strategy
            pii_config[:fields].each do |field, config|
              validate_field_config!(event_class, field, config)
            end
          end

          private

          def extract_schema_keys(klass)
            return nil unless klass.respond_to?(:compiled_schema)

            schema = klass.compiled_schema
            return nil unless schema.respond_to?(:key_map)

            schema.key_map.keys.map(&:name)
          rescue StandardError
            nil
          end

          def build_missing_message(event_class, missing_fields)
            fields_snippet = missing_fields.map do |f|
              "    field :#{f} do\n      strategy :mask  # or :hash, :allow, :redact\n    end"
            end.join("\n  ")

            <<~ERROR
              PII Declaration Error: #{event_class.name}

              Event declared `contains_pii true` but missing field declarations:

              Missing fields: #{missing_fields.map { |x| ":#{x}" }.join(', ')}

              Fix: Add explicit PII strategy for each field in pii_filtering block:

              class #{event_class.name} < E11y::Event::Base
                contains_pii true

                pii_filtering do
                  #{fields_snippet}
                end
              end

              Available strategies: #{VALID_STRATEGIES.map { |s| ":#{s}" }.join(', ')}
            ERROR
          end

          def validate_field_config!(event_class, field, config)
            strategy = config[:strategy]
            unless VALID_STRATEGIES.include?(strategy)
              raise PiiDeclarationError, <<~ERROR
                Invalid PII strategy for #{event_class.name}##{field}

                Strategy: #{strategy.inspect}
                Valid strategies: #{VALID_STRATEGIES.map { |s| ":#{s}" }.join(', ')}
              ERROR
            end

            return unless config.key?(:exclude_adapters)

            return if config[:exclude_adapters].is_a?(Array)

            raise PiiDeclarationError, "exclude_adapters must be an Array for #{event_class.name}##{field}"
          end
        end
      end

      # Raised when PII declaration validation fails.
      class PiiDeclarationError < LinterError; end
    end
  end
end
