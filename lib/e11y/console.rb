# frozen_string_literal: true

module E11y
  # Console helpers for Rails console
  #
  # Provides convenient methods for debugging and introspection in Rails console.
  #
  # @example Usage in Rails console
  #   E11y.stats          # Show E11y statistics
  #   E11y.test_event     # Track a test event
  #   E11y.events         # List all registered events
  #   E11y.adapters       # List all adapters
  #   E11y.reset!         # Clear buffers
  #
  # @see ADR-008 §9 (Console & Development)
  module Console
    # Enable console helpers
    #
    # Called automatically by E11y::Railtie when Rails console starts.
    #
    # @return [void]
    def self.enable!
      define_helper_methods
      configure_for_console
    end

    # Define helper methods on E11y module
    # @return [void]
    def self.define_helper_methods
      E11y.singleton_class.class_eval do
        # Show E11y statistics
        # @return [Hash] Statistics hash
        def stats
          {
            enabled: E11y.config.enabled,
            environment: E11y.config.environment,
            service_name: E11y.config.service_name,
            adapters: E11y::Adapters::Registry.all.map do |a|
              {
                name: a.name,
                class: a.class.name,
                healthy: a.healthy?
              }
            end,
            buffer: {
              size: buffer_size,
              max_size: E11y.config.buffer&.max_size
            }
          }
        end

        # Track a test event
        # @return [void]
        def test_event
          # TODO: Implement test event tracking
          # For now, just print a message
          puts "✅ E11y test event would be tracked here"
          puts "   (Waiting for Events::Console::Test implementation)"
        end

        # List all registered event classes
        # @return [Array<String>] Event class names
        def events
          # TODO: Implement event registry
          puts "📋 E11y events list"
          puts "   (Waiting for Event registry implementation)"
          []
        end

        # List all registered adapters
        # @return [Array<Hash>] Adapter details
        def adapters
          E11y::Adapters::Registry.all.map do |adapter|
            {
              name: adapter.name,
              class: adapter.class.name,
              healthy: adapter.healthy?,
              capabilities: adapter.capabilities
            }
          end
        end

        # Reset buffers (clear all buffered events)
        # @return [void]
        def reset!
          # TODO: Implement buffer clearing
          puts "✅ E11y buffers would be cleared here"
          puts "   (Waiting for Buffer#clear! implementation)"
        end

        private

        # Get current buffer size
        # @return [Integer] Number of buffered events
        def buffer_size
          # TODO: Implement buffer size tracking
          0
        end
      end
    end

    # Configure E11y for console-friendly output
    # @return [void]
    def self.configure_for_console
      E11y.configure do |config|
        # Console-friendly output
        config.adapters&.clear

        # Use stdout adapter with pretty printing
        config.adapters&.register :stdout, E11y::Adapters::Stdout.new(
          colorize: true
        )

        # Show all severities
        # TODO: Implement severity_threshold config
        # config.severity_threshold = :debug
      end
    rescue StandardError => e
      warn "[E11y] Failed to configure console: #{e.message}"
    end
  end
end
