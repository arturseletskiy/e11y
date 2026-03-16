# frozen_string_literal: true

require "delegate"
require "set"

module E11y
  module Logger
    # Rails.logger Bridge (SimpleDelegator wrapper)
    #
    # Transparent wrapper around Rails.logger that:
    # 1. Delegates all calls to the original logger (preserves Rails behavior)
    # 2. Tracks log calls as E11y events (when logger_bridge_enabled = true)
    #
    # **Why SimpleDelegator instead of full replacement:**
    # - ✅ Simpler: No need to reimplement entire Logger API
    # - ✅ Safer: Preserves all Rails.logger behavior
    # - ✅ Flexible: Can be enabled/disabled without breaking anything
    # - ✅ Rails Way: Extends functionality without replacing core components
    #
    # @example Basic usage
    #   # Automatically enabled by E11y::Railtie if config.logger_bridge_enabled = true
    #   Rails.logger = E11y::Logger::Bridge.new(Rails.logger)
    #
    # @example Manual setup
    #   E11y.configure do |config|
    #     config.logger_bridge_enabled = true  # Wrap Rails.logger and send logs to E11y
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
        return unless E11y.config.logger_bridge_enabled
        return unless defined?(::Rails)

        # Wrap Rails.logger (preserves original behavior)
        ::Rails.logger = Bridge.new(::Rails.logger)
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
        @track_severities_set = build_track_severities_set(E11y.config.logger_bridge_track_severities)
        @ignore_patterns = build_compiled_patterns(E11y.config.logger_bridge_ignore_patterns)
      end

      # Intercept logger methods to track to E11y
      # All calls are delegated to the original logger via SimpleDelegator

      # Log debug message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def debug(message = nil, &)
        track_to_e11y(:debug, message, &)
        super # Delegate to original logger
      end

      # Log info message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def info(message = nil, &)
        track_to_e11y(:info, message, &)
        super # Delegate to original logger
      end

      # Log warn message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def warn(message = nil, &)
        track_to_e11y(:warn, message, &)
        super # Delegate to original logger
      end

      # Log error message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def error(message = nil, &)
        track_to_e11y(:error, message, &)
        super # Delegate to original logger
      end

      # Log fatal message
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [true] Always returns true (Logger API)
      def fatal(message = nil, &)
        track_to_e11y(:fatal, message, &)
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
        track_to_e11y(e11y_severity, message || progname, &)
        super # Delegate to original logger
      end

      alias log add

      private

      # Track log message as E11y event
      # @param severity [Symbol] E11y severity
      # @param message [String, nil] Log message
      # @yield Block that returns log message
      # @return [void]
      # Logger tracking requires message extraction, validation, event class lookup, and error handling
      def track_to_e11y(severity, message = nil)
        # Extract message
        msg = message || (block_given? ? yield : nil)
        return if msg.nil? || (msg.respond_to?(:empty?) && msg.empty?)

        msg_str = msg.to_s

        return if @track_severities_set && !@track_severities_set.include?(severity)
        return if @ignore_patterns.any? { |re| re.match?(msg_str) }

        # Track to E11y using severity-specific class
        require "e11y/events/rails/log"
        event_class = event_class_for_severity(severity)
        event_class.track(
          message: msg_str,
          caller_location: extract_caller_location
        )
      rescue StandardError => e
        # Silently ignore E11y tracking errors (don't break logging!)
        # In development/test, you might want to log this
        warn "E11y logger tracking failed: #{e.message}" if defined?(::Rails) && ::Rails.env.development?
      end

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

      def build_track_severities_set(severities)
        return nil if severities.nil? || (severities.respond_to?(:empty?) && severities.empty?)

        Set.new(Array(severities).map(&:to_sym))
      end

      def build_compiled_patterns(patterns)
        return [] if patterns.nil? || !patterns.respond_to?(:any?) || !patterns.any?

        Array(patterns).map do |p|
          p.is_a?(Regexp) ? p : Regexp.new(Regexp.escape(p.to_s))
        end.freeze
      end

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
