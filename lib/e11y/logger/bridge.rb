# frozen_string_literal: true

require "delegate"

module E11y
  module Logger
    # Rails.logger Bridge (SimpleDelegator wrapper)
    #
    # Transparent wrapper around Rails.logger that:
    # 1. Delegates all calls to the original logger (preserves Rails behavior)
    # 2. Optionally tracks log calls as E11y events (when enabled)
    #
    # **Why SimpleDelegator instead of full replacement:**
    # - ✅ Simpler: No need to reimplement entire Logger API
    # - ✅ Safer: Preserves all Rails.logger behavior
    # - ✅ Flexible: Can be enabled/disabled without breaking anything
    # - ✅ Rails Way: Extends functionality without replacing core components
    #
    # @example Basic usage
    #   # Automatically enabled by E11y::Railtie if config.logger_bridge.enabled = true
    #   Rails.logger = E11y::Logger::Bridge.new(Rails.logger)
    #
    # @example Manual setup
    #   E11y.configure do |config|
    #     config.logger_bridge.enabled = true
    #     config.logger_bridge.track_to_e11y = true  # Send logs to E11y events (optional)
    #   end
    #
    # @see ADR-008 §7 (Rails.logger Migration)
    # @see UC-016 (Rails Logger Migration)
    class Bridge < SimpleDelegator
      # Setup Rails.logger bridge
      #
      # Wraps Rails.logger with E11y::Logger::Bridge.
      #
      # @return [void]
      def self.setup!
        return unless E11y.config.logger_bridge&.enabled
        return unless defined?(Rails)

        # Wrap Rails.logger (preserves original behavior)
        Rails.logger = Bridge.new(Rails.logger)
      end

      # Initialize bridge wrapper
      # @param original_logger [Logger] Original Rails logger
      def initialize(original_logger)
        super
        @severity_mapping = {
          ::Logger::DEBUG => :debug,
          ::Logger::INFO => :info,
          ::Logger::WARN => :warn,
          ::Logger::ERROR => :error,
          ::Logger::FATAL => :fatal,
          ::Logger::UNKNOWN => :warn
        }
      end

      # Intercept logger methods to optionally track to E11y
      # All calls are delegated to the original logger via SimpleDelegator

      # Log debug message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def debug(message = nil, &)
        track_to_e11y(:debug, message, &) if should_track_severity?(:debug)
        super # Delegate to original logger
      end

      # Log info message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def info(message = nil, &)
        track_to_e11y(:info, message, &) if should_track_severity?(:info)
        super # Delegate to original logger
      end

      # Log warn message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def warn(message = nil, &)
        track_to_e11y(:warn, message, &) if should_track_severity?(:warn)
        super # Delegate to original logger
      end

      # Log error message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def error(message = nil, &)
        track_to_e11y(:error, message, &) if should_track_severity?(:error)
        super # Delegate to original logger
      end

      # Log fatal message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def fatal(message = nil, &)
        track_to_e11y(:fatal, message, &) if should_track_severity?(:fatal)
        super # Delegate to original logger
      end

      # Generic log method
      # @param severity [Integer] Logger severity constant
      # @param message [String, nil] Log message
      # @param progname [String, nil] Program name
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def add(severity, message = nil, progname = nil, &)
        e11y_severity = @severity_mapping[severity] || :info
        track_to_e11y(e11y_severity, message || progname, &) if should_track_severity?(e11y_severity)
        super # Delegate to original logger
      end

      alias log add

      private

      # Check if E11y tracking is enabled for specific severity
      # Supports both boolean and per-severity Hash configuration
      #
      # @param severity [Symbol] E11y severity (:debug, :info, :warn, :error, :fatal)
      # @return [Boolean]
      #
      # @example Boolean config (all or nothing)
      #   config.logger_bridge.track_to_e11y = true  # Track all
      #   config.logger_bridge.track_to_e11y = false # Track none
      #
      # @example Per-severity config (granular control)
      #   config.logger_bridge.track_to_e11y = {
      #     debug: false,
      #     info: true,
      #     warn: true,
      #     error: true,
      #     fatal: true
      #   }
      # rubocop:disable Lint/DuplicateBranch
      # Unknown config types intentionally fallback to false (same as FalseClass)
      def should_track_severity?(severity)
        config = E11y.config.logger_bridge&.track_to_e11y
        return false unless config

        case config
        when TrueClass
          true # Track all severities
        when FalseClass
          false # Track none
        when Hash
          config[severity] || false # Check per-severity config
        else
          false # Unknown config type
        end
      end
      # rubocop:enable Lint/DuplicateBranch

      # Track log message as E11y event
      # @param severity [Symbol] E11y severity
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [void]
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Logger tracking requires message extraction, validation, event class lookup, and error handling
      def track_to_e11y(severity, message = nil, &block)
        # Extract message
        msg = message || (block_given? ? block.call : nil)
        return if msg.nil? || (msg.respond_to?(:empty?) && msg.empty?)

        # Track to E11y using severity-specific class
        require "e11y/events/rails/log"
        event_class = event_class_for_severity(severity)
        event_class.track(
          message: msg.to_s,
          caller_location: extract_caller_location
        )
      rescue StandardError => e
        # Silently ignore E11y tracking errors (don't break logging!)
        # In development/test, you might want to log this
        warn "E11y logger tracking failed: #{e.message}" if defined?(Rails) && Rails.env.development?
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Get event class for severity
      # @param severity [Symbol] E11y severity
      # @return [Class] Event class
      # rubocop:disable Lint/DuplicateBranch
      # Unknown severities intentionally fallback to Info (same as :info)
      def event_class_for_severity(severity)
        case severity
        when :debug then E11y::Events::Rails::Log::Debug
        when :info then E11y::Events::Rails::Log::Info
        when :warn then E11y::Events::Rails::Log::Warn
        when :error then E11y::Events::Rails::Log::Error
        when :fatal then E11y::Events::Rails::Log::Fatal
        else E11y::Events::Rails::Log::Info # Fallback
        end
      end
      # rubocop:enable Lint/DuplicateBranch

      # Extract caller location (first caller outside E11y)
      # @return [String, nil] Caller location string
      def extract_caller_location
        loc = caller_locations.find { |l| !l.path.include?("e11y") }
        return nil unless loc

        "#{loc.path}:#{loc.lineno}:in `#{loc.label}'"
      end
    end
  end
end
