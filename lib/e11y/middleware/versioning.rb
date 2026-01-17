# frozen_string_literal: true

module E11y
  module Middleware
    # Versioning middleware normalizes event names for adapters.
    #
    # **⚠️ CRITICAL: This middleware MUST be LAST (before Routing)!**
    #
    # All business logic (Validation, PII Filtering, Rate Limiting, Sampling)
    # MUST use the ORIGINAL class name (e.g., Events::OrderPaidV2), because
    # schemas and rules are version-specific.
    #
    # Versioning is a **cosmetic normalization** for external systems (adapters),
    # making querying easier by consolidating versions under a single event name.
    #
    # @see ADR-015 §2 Decision: Versioning MUST be LAST
    # @see ADR-015 §3.1 Pipeline Flow (lines 108-117)
    # @see ADR-015 §4 Wrong Order Example (what breaks if too early)
    # @see ADR-012 Event Evolution & Versioning (full design)
    #
    # @example V2 event normalization
    #   # Input (from Validation middleware):
    #   {
    #     event_name: 'Events::OrderPaidV2',
    #     payload: { order_id: 123, amount: 99.99, currency: 'USD' }
    #   }
    #
    #   # Output (to Routing middleware):
    #   {
    #     event_name: 'Events::OrderPaid',  # ← Normalized!
    #     payload: {
    #       order_id: 123,
    #       amount: 99.99,
    #       currency: 'USD',
    #       v: 2                              # ← Version explicit
    #     }
    #   }
    #
    # @example V1 event (no version suffix)
    #   # Input:
    #   { event_name: 'Events::OrderPaid', payload: { order_id: 123 } }
    #
    #   # Output (no `v` field added for V1):
    #   { event_name: 'Events::OrderPaid', payload: { order_id: 123 } }
    #
    # @example Querying in Loki (after normalization)
    #   # All versions: {event_name="Events::OrderPaid"}
    #   # Only V2: {event_name="Events::OrderPaid", v="2"}
    #   # Only V1: {event_name="Events::OrderPaid"} |= "" != "v"
    class Versioning < Base
      middleware_zone :post_processing

      # Normalizes event name and adds version to payload.
      #
      # @param event_data [Hash] The event data to normalize
      # @option event_data [String] :event_name Event class name (required)
      # @option event_data [Hash] :payload Event payload (required)
      # @return [Hash, nil] Normalized event data, or nil if dropped
      def call(event_data)
        # Skip if no event_name or payload
        return @app.call(event_data) unless event_data[:event_name] && event_data[:payload]

        event_name = event_data[:event_name]
        payload = event_data[:payload]

        # Extract version from event name (e.g., "Events::OrderPaidV2" → 2)
        version = extract_version(event_name)

        # Normalize event name (remove version suffix)
        normalized_name = normalize_event_name(event_name, version)

        # Add version to payload (only if version > 1)
        payload[:v] = version if version > 1 && !payload.key?(:v)

        # Update event_name in event_data
        event_data[:event_name] = normalized_name

        # Increment metrics
        increment_metric("e11y.middleware.versioning.normalized", version: version)

        @app.call(event_data)
      end

      private

      # Extract version number from event class name.
      #
      # @param event_name [String] Event class name (e.g., "Events::OrderPaidV2")
      # @return [Integer] Version number (1 if no suffix, N if VN suffix)
      #
      # @example
      #   extract_version("Events::OrderPaidV2") # => 2
      #   extract_version("Events::OrderPaid")   # => 1
      #   extract_version("Events::UserV10")     # => 10
      def extract_version(event_name)
        match = event_name.match(/V(\d+)$/)
        match ? match[1].to_i : 1 # Default to version 1 if no suffix
      end

      # Normalize event name by removing version suffix.
      #
      # @param event_name [String] Event class name
      # @param version [Integer] Extracted version number
      # @return [String] Normalized event name
      #
      # @example
      #   normalize_event_name("Events::OrderPaidV2", 2) # => "Events::OrderPaid"
      #   normalize_event_name("Events::OrderPaid", 1)   # => "Events::OrderPaid"
      def normalize_event_name(event_name, version)
        return event_name if version == 1 # Already normalized (no suffix)

        event_name.sub(/V#{version}$/, "") # Remove "V2", "V3", etc.
      end

      # Placeholder for metrics instrumentation.
      #
      # @param metric_name [String] Metric name
      # @param tags [Hash] Metric tags (e.g., version)
      # @return [void]
      def increment_metric(_metric_name, **_tags)
        # TODO: Integrate with Yabeda/Prometheus in Phase 2
        # Yabeda.e11y.middleware_versioning_normalized.increment(version: version)
      end
    end
  end
end
