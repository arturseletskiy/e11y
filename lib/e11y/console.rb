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
      E11y.extend(ConsoleHelpers)
    end

    # Console helper methods module
    module ConsoleHelpers
      # Show E11y statistics
      def stats
        {
          enabled: config.enabled,
          environment: config.environment,
          service_name: config.service_name,
          adapters: adapters_info,
          buffer: buffer_info
        }
      end

      # Track a test event
      def test_event
        puts "✅ E11y test event would be tracked here"
        puts "   (Waiting for Events::Console::Test implementation)"
      end

      # List all registered event classes
      def events
        Registry.event_classes.map { |e| e.respond_to?(:event_name) ? e.event_name : e.name }
      end

      # List all registered adapters
      def adapters
        Adapters::Registry.all.map do |adapter|
          {
            name: adapter.name,
            class: adapter.class.name,
            healthy: adapter.healthy?,
            capabilities: adapter.capabilities
          }
        end
      end

      # Reset buffers
      def reset!
        puts "✅ E11y buffers would be cleared here"
        puts "   (Waiting for Buffer#clear! implementation)"
      end

      private

      def adapters_info
        Adapters::Registry.all.map do |a|
          { name: a.name, class: a.class.name, healthy: a.healthy? }
        end
      end

      def buffer_info
        { size: buffer_size }
      end

      def buffer_size
        0 # TODO: Implement buffer size tracking
      end
    end

    # Configure E11y for console-friendly output
    # @return [void]
    def self.configure_for_console
      E11y.configure do |config|
        config.adapters.clear
        config.adapters[:stdout] = E11y::Adapters::Stdout.new(colorize: true, format: :rich)

        # Show all severities
        # TODO: Implement severity_threshold config
        # config.severity_threshold = :debug
      end
    rescue StandardError => e
      warn "[E11y] Failed to configure console: #{e.message}"
    end
  end
end
