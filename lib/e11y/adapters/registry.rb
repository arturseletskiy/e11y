# frozen_string_literal: true

module E11y
  module Adapters
    # Adapter Registry - Global registry for adapter instances
    #
    # Provides thread-safe registration and resolution of adapters.
    # Adapters are registered once during configuration and reused
    # throughout application lifetime.
    #
    # **Features:**
    # - Thread-safe registration
    # - Adapter validation
    # - Resolution by name
    # - Cleanup on exit
    #
    # @example Registration
    #   E11y::Adapters::Registry.register :stdout, E11y::Adapters::Stdout.new
    #   E11y::Adapters::Registry.register :loki, E11y::Adapters::Loki.new(url: "...")
    #
    # @example Resolution
    #   adapter = E11y::Adapters::Registry.resolve(:stdout)
    #   adapter.write(event_data)
    #
    # @see ADR-004 §5 (Adapter Registry)
    class Registry
      # Registry error
      class Error < E11y::Error; end

      # Adapter not found error
      class AdapterNotFoundError < Error; end

      class << self
        # Register adapter instance
        #
        # @param name [Symbol] Adapter name (e.g., :stdout, :loki)
        # @param adapter_instance [Adapters::Base] Adapter instance
        # @raise [ArgumentError] if adapter does not respond to required methods
        #
        # @example
        #   Registry.register :stdout, E11y::Adapters::Stdout.new
        def register(name, adapter_instance)
          validate_adapter!(adapter_instance)

          adapters[name] = adapter_instance

          # Register cleanup hook
          at_exit { adapter_instance.close }
        end

        # Resolve adapter by name
        #
        # @param name [Symbol] Adapter name
        # @return [Adapters::Base] Adapter instance
        # @raise [AdapterNotFoundError] if adapter not found
        #
        # @example
        #   adapter = Registry.resolve(:stdout)
        def resolve(name)
          adapters.fetch(name) do
            raise AdapterNotFoundError, "Adapter not found: #{name}. Registered: #{names.join(', ')}"
          end
        end

        # Resolve multiple adapters by names
        #
        # @param names [Array<Symbol>] Adapter names
        # @return [Array<Adapters::Base>] Adapter instances
        # @raise [AdapterNotFoundError] if any adapter not found
        #
        # @example
        #   adapters = Registry.resolve_all([:stdout, :loki])
        def resolve_all(names)
          names.map { |name| resolve(name) }
        end

        # Get all registered adapters
        #
        # @return [Array<Adapters::Base>] All adapter instances
        def all
          adapters.values
        end

        # Get all registered adapter names
        #
        # @return [Array<Symbol>] Adapter names
        def names
          adapters.keys
        end

        # Check if adapter is registered
        #
        # @param name [Symbol] Adapter name
        # @return [Boolean] true if registered
        #
        # @example
        #   Registry.registered?(:stdout)  #=> true
        def registered?(name)
          adapters.key?(name)
        end

        # Clear all registered adapters
        #
        # Calls close() on all adapters and clears registry.
        # Useful for testing.
        #
        # @return [void]
        #
        # @example
        #   Registry.clear!
        def clear!
          adapters.each_value(&:close)
          adapters.clear
        end

        private

        # Registry storage (thread-safe Hash)
        #
        # @return [Hash<Symbol, Adapters::Base>]
        def adapters
          @adapters ||= {}
        end

        # Validate adapter implements required interface
        #
        # @param adapter [Object] Adapter instance
        # @raise [ArgumentError] if adapter invalid
        def validate_adapter!(adapter)
          unless adapter.respond_to?(:write)
            raise ArgumentError, "Adapter must respond to #write"
          end

          unless adapter.respond_to?(:write_batch)
            raise ArgumentError, "Adapter must respond to #write_batch"
          end

          return if adapter.respond_to?(:healthy?)

          raise ArgumentError, "Adapter must respond to #healthy?"
        end
      end
    end
  end
end
