# frozen_string_literal: true

module E11y
  module Middleware
    # Versioning Middleware (ADR-012, UC-020)
    #
    # Extracts version from event class name and adds `v:` field to payload.
    # Only adds `v:` if version > 1 (reduces noise for V1 events).
    #
    # **Features:**
    # - Extracts version from class name (e.g., `Events::OrderPaidV2` → `v: 2`)
    # - Normalizes event_name (removes version suffix for consistent queries)
    # - Only adds `v:` field if version > 1
    # - Opt-in (must be explicitly enabled)
    #
    # **ADR References:**
    # - ADR-012 §2 (Parallel Versions)
    # - ADR-012 §3 (Naming Convention)
    # - ADR-012 §4 (Version in Payload)
    # - ADR-015 §3 (Middleware Order - Versioning in :pre_processing zone)
    #
    # **Use Case:** UC-020 (Event Versioning)
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     # Enable versioning middleware (opt-in)
    #     config.pipeline.use E11y::Middleware::Versioning
    #   end
    #
    # @example V1 Event (no version in payload)
    #   class Events::OrderPaid < E11y::Event::Base
    #     # No version suffix → V1 (implicit)
    #   end
    #
    #   # Result payload:
    #   {
    #     event_name: "order.paid",  # Normalized (no version)
    #     # No `v:` field (V1 is implicit)
    #     payload: { ... }
    #   }
    #
    # @example V2 Event (version in payload)
    #   class Events::OrderPaidV2 < E11y::Event::Base
    #     # Version suffix → V2
    #   end
    #
    #   # Result payload:
    #   {
    #     event_name: "order.paid",  # Normalized (no version)
    #     v: 2,                       # Version extracted from class name
    #     payload: { ... }
    #   }
    #
    # @see ADR-012 for versioning architecture
    # @see UC-020 for use cases
    class Versioning < Base
      middleware_zone :pre_processing
      # Version extraction regex (matches V2, V3, etc. at end of class name)
      VERSION_REGEX = /V(\d+)$/

      # Lazy cache: class name -> normalized event_name (per class, immutable)
      NORMALIZED_CACHE = Concurrent::Map.new

      # Process event and add version field if needed
      #
      # @param event_data [Hash] Event payload
      # @return [Hash] Event data with version field (if > 1)
      def call(event_data)
        klass = event_data[:event_class]
        class_name = klass&.name

        version = event_data[:version].to_i
        version = extract_version(class_name) if version <= 1
        event_data[:v] = version if version > 1

        # event_data[:event_name] set by Base; fallback to klass.event_name for minimal event_data (tests)
        incoming = event_data[:event_name]
        incoming = klass.event_name if incoming.nil? && klass.respond_to?(:event_name)
        incoming = incoming.to_s
        # Custom uses dot notation ("order.paid"); default from Base uses "::"
        event_data[:event_name] = incoming != "" && !incoming.include?("::") ? incoming : normalized_for(klass)

        @app&.call(event_data) || event_data
      end

      private

      def normalized_for(klass)
        return unless klass

        name = klass.name
        return unless name

        NORMALIZED_CACHE.fetch(name) { NORMALIZED_CACHE[name] = normalize_event_name(name) }
      end

      def extract_version(class_name)
        return 1 unless class_name

        match = class_name.match(VERSION_REGEX)
        match ? match[1].to_i : 1
      end

      # Normalize event_name by removing version suffix
      #
      # This ensures consistent querying across versions:
      # - "Events::OrderPaid" → "order.paid"
      # - "Events::OrderPaidV2" → "order.paid" (same name!)
      #
      # **Rationale (ADR-012 §3.2):**
      # Query: `WHERE event_name = 'order.paid'` matches ALL versions
      #
      # @param class_name [String] Event class name
      # @return [String] Normalized event name (snake_case, no version)
      #
      # @example
      #   normalize_event_name("Events::OrderPaid")   => "order.paid"
      #   normalize_event_name("Events::OrderPaidV2") => "order.paid"
      #   normalize_event_name("Events::OrderPaidV3") => "order.paid"
      def normalize_event_name(class_name)
        return class_name unless class_name

        # Remove "Events::" namespace prefix
        name = class_name.sub(/^Events::/, "")

        # Remove version suffix (V2, V3, etc.)
        name = name.sub(VERSION_REGEX, "")

        # Convert nested namespaces to dots first
        name = name.gsub("::", ".")

        # Convert to snake_case
        name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # ABCWord → ABC_Word
            .gsub(/([a-z\d])([A-Z])/, '\1_\2') # wordWord → word_Word
            .downcase
            .tr("_", ".") # Convert underscores to dots for event names
      end
    end
  end
end
