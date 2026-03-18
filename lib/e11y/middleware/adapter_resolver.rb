# frozen_string_literal: true

module E11y
  module Middleware
    # Resolves target adapter names for an event (shared by PIIFilter and Routing).
    #
    # @api private
    module AdapterResolver
      # Resolve target adapters for event_data (explicit or routing rules).
      #
      # @param event_data [Hash] Event data with :adapters, :audit_event, :retention_until, etc.
      # @return [Array<Symbol>] Target adapter names
      def self.resolve(event_data)
        if event_data[:adapters]&.any?
          Array(event_data[:adapters]).map(&:to_sym)
        else
          apply_routing_rules(event_data)
        end
      end

      def self.apply_routing_rules(event_data)
        matched_adapters = []
        rules = E11y.configuration.routing_rules || []

        rules.each do |rule|
          result = rule.call(event_data)
          matched_adapters.concat(Array(result)) if result
        rescue StandardError => e
          warn "[E11y] Routing rule error: #{e.message}"
        end

        if matched_adapters.any?
          matched_adapters.uniq
        else
          E11y.configuration.fallback_adapters || [:stdout]
        end
      end
    end
  end
end
