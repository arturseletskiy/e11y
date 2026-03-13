# frozen_string_literal: true

module E11y
  # Thread-safe auto-populating registry for discovering and inspecting all defined E11y event classes.
  #
  # Events are registered automatically when `event_name` is set on a subclass of `E11y::Event::Base`.
  # The registry is always-on (no configuration needed) and is safe for concurrent use.
  #
  # @example Discover all events
  #   E11y::Registry.all_events
  #   # => [Events::OrderCreated, Events::PaymentFailed, ...]
  #
  # @example Find an event class by name
  #   E11y::Registry.find("order.created")
  #   # => Events::OrderCreated
  #
  # @example Filter events by severity
  #   E11y::Registry.where(severity: :error)
  #   # => [Events::PaymentFailed, ...]
  #
  # @example Generate documentation
  #   E11y::Registry.to_documentation
  #   # => [{ name: "order.created", class: "Events::OrderCreated", ... }, ...]
  #
  # @see UC-022 Event Registry
  class Registry
    class << self
      # Singleton instance
      #
      # @return [Registry]
      def instance
        @instance ||= new
      end

      # Register an event class. Delegates to singleton instance.
      #
      # @param event_class [Class] Event class to register
      # @return [void]
      def register(event_class)
        instance.register(event_class)
      end

      # Find event class by name. Delegates to singleton instance.
      #
      # @param event_name [String] Event name
      # @param version [Integer, nil] Specific version (nil = latest)
      # @return [Class, nil] Event class or nil
      def find(event_name, version: nil)
        instance.find(event_name, version: version)
      end

      # Return all registered event classes. Delegates to singleton instance.
      #
      # @return [Array<Class>]
      def all_events
        instance.all_events
      end

      # Filter events by criteria. Delegates to singleton instance.
      #
      # @param criteria [Hash] Filter criteria (:severity, :version, :adapter)
      # @return [Array<Class>]
      def where(**criteria)
        instance.where(**criteria)
      end

      # Validate that an event is properly configured. Delegates to singleton instance.
      #
      # @param event_name [String]
      # @return [Boolean]
      def validate(event_name)
        instance.validate(event_name)
      end

      # Clear all registered events. Delegates to singleton instance.
      #
      # @return [void]
      def clear!
        instance.clear!
      end

      # Number of unique event names registered. Delegates to singleton instance.
      #
      # @return [Integer]
      def size
        instance.size
      end

      # Generate documentation hash for all events. Delegates to singleton instance.
      #
      # @return [Array<Hash>]
      def to_documentation
        instance.to_documentation
      end

      # Reset the singleton instance (primarily for test isolation).
      #
      # After calling this, the next call to `.instance` creates a fresh registry.
      # Note: previously registered events will NOT be re-registered unless their
      # class definitions are re-evaluated.
      #
      # @return [void]
      # @api private
      def reset!
        @instance = nil
      end
    end

    # Initialize a new Registry instance.
    #
    # Creates an empty, thread-safe registry backed by a Mutex-protected Hash.
    def initialize
      @registry = {}        # event_name (String) => Array<Class>
      @mutex = Mutex.new
    end

    # Register an event class.
    #
    # Safe to call multiple times with the same class — idempotent.
    # Silently ignores classes that do not respond to `event_name`
    # or return a blank name (e.g. intermediate abstract classes).
    #
    # @param event_class [Class] Event class to register
    # @return [void]
    def register(event_class)
      return unless event_class.respond_to?(:event_name)

      name = begin
        event_class.event_name
      rescue StandardError
        nil
      end

      return if name.nil? || name.empty? || name == "AnonymousEvent"

      @mutex.synchronize do
        @registry[name] ||= []
        @registry[name] << event_class unless @registry[name].include?(event_class)
      end
    end

    # Find event class by name.
    #
    # When multiple classes share the same event name (versioning), returns the
    # latest-registered one by default. Pass `version:` to find a specific version.
    #
    # @param event_name [String, Symbol] Event name to look up
    # @param version [Integer, nil] Specific version number (nil = latest)
    # @return [Class, nil] Matching event class or nil
    def find(event_name, version: nil)
      entries = @mutex.synchronize { @registry[event_name.to_s]&.dup }
      return nil if entries.nil? || entries.empty?

      if version
        entries.find { |klass| klass.respond_to?(:version) && klass.version == version }
      else
        entries.last # latest registered = latest version
      end
    end

    # Return all registered event classes as a flat array.
    #
    # The returned array is a copy — mutating it does not affect the registry.
    #
    # @return [Array<Class>]
    def all_events
      @mutex.synchronize { @registry.values.flatten.dup }
    end

    # Filter registered events by criteria.
    #
    # Supported criteria keys:
    # - `:severity` — matches `klass.default_severity` or `klass.severity`
    # - `:version`  — matches `klass.version`
    # - `:adapter`  — matches if `klass.adapters` includes the value
    #
    # Unknown criteria keys always produce no matches (conservative).
    #
    # @param criteria [Hash]
    # @return [Array<Class>]
    def where(**criteria)
      all_events.select do |klass|
        criteria.all? do |key, value|
          case key
          when :severity
            # Support both default_severity and severity readers
            reader = klass.respond_to?(:default_severity) ? :default_severity : :severity
            klass.respond_to?(reader) && klass.public_send(reader) == value
          when :version
            klass.respond_to?(:version) && klass.version == value
          when :adapter
            klass.respond_to?(:adapters) && Array(klass.adapters).include?(value)
          else
            false
          end
        end
      end
    end

    # Validate that a registered event has a compiled schema.
    #
    # Returns `false` for unknown events.
    # Returns `true` if the class is registered and has a non-nil `compiled_schema`.
    #
    # @param event_name [String]
    # @return [Boolean]
    def validate(event_name)
      klass = find(event_name)
      return false unless klass

      klass.respond_to?(:compiled_schema) && !klass.compiled_schema.nil?
    end

    # Remove all entries from the registry.
    #
    # Primarily used in tests to avoid cross-test pollution.
    #
    # @return [void]
    def clear!
      @mutex.synchronize { @registry.clear }
    end

    # Number of unique event names in the registry.
    #
    # Note: multiple versions of the same event name count as 1.
    #
    # @return [Integer]
    def size
      @mutex.synchronize { @registry.size }
    end

    # Generate a documentation-friendly hash for every registered event class.
    #
    # @return [Array<Hash>] Each entry contains `:name`, `:class`, `:version`,
    #   `:severity`, and `:schema_keys` (absent when not applicable).
    def to_documentation
      all_events.map do |klass|
        {
          name: klass.respond_to?(:event_name) ? klass.event_name : klass.name,
          class: klass.name,
          version: klass.respond_to?(:version) ? klass.version : nil,
          severity: klass.respond_to?(:severity) ? klass.severity : nil,
          schema_keys: extract_schema_keys(klass)
        }.compact
      end
    end

    private

    # Extract schema key names from an event class.
    #
    # Uses `compiled_schema.key_map` when available, falling back gracefully.
    #
    # @param klass [Class] Event class
    # @return [Array<String>, nil]
    def extract_schema_keys(klass)
      return nil unless klass.respond_to?(:compiled_schema)

      schema = klass.compiled_schema
      return nil unless schema&.respond_to?(:key_map)

      schema.key_map.keys.map(&:name)
    rescue StandardError
      nil
    end
  end
end
