# frozen_string_literal: true

# Check if OpenTelemetry SDK is available
begin
  require "opentelemetry/sdk"
  require "opentelemetry/logs"
rescue LoadError
  raise LoadError, <<~ERROR
    OpenTelemetry SDK not available!

    To use E11y::Adapters::OTelLogs, add to your Gemfile:

      gem 'opentelemetry-sdk'
      gem 'opentelemetry-logs'

    Then run: bundle install
  ERROR
end

module E11y
  module Adapters
    # OpenTelemetry Logs Adapter (ADR-007, UC-008)
    #
    # Sends E11y events to OpenTelemetry Logs API.
    # Events are converted to OTel log records with proper severity mapping.
    #
    # **Features:**
    # - Severity mapping (E11y → OTel)
    # - Attributes mapping (E11y payload → OTel attributes)
    # - Baggage PII protection (C08 Resolution)
    # - Cardinality protection for attributes (C04 Resolution)
    # - Optional dependency (requires opentelemetry-sdk gem)
    #
    # **ADR References:**
    # - ADR-007 §4 (OpenTelemetry Integration)
    # - ADR-006 §5 (Baggage PII Protection - C08 Resolution)
    # - ADR-009 §8 (Cardinality Protection - C04 Resolution)
    #
    # **Use Case:** UC-008 (OpenTelemetry Integration)
    #
    # @example Configuration
    #   # Gemfile
    #   gem 'opentelemetry-sdk'
    #   gem 'opentelemetry-logs'
    #
    #   # config/initializers/e11y.rb
    #   E11y.configure do |config|
    #     config.adapters[:otel_logs] = E11y::Adapters::OTelLogs.new(
    #       service_name: 'my-app',
    #       baggage_allowlist: [:trace_id, :span_id, :user_id]
    #     )
    #   end
    #
    # @example Baggage PII Protection (C08)
    #   # Only allowlisted keys are sent to baggage
    #   # PII keys (email, phone, etc.) are automatically dropped
    #
    # @see ADR-007 for OpenTelemetry integration architecture
    # @see UC-008 for use cases
    class OTelLogs < Base
      # E11y severity → OTel severity mapping
      SEVERITY_MAPPING = {
        debug: OpenTelemetry::SDK::Logs::Severity::DEBUG,
        info: OpenTelemetry::SDK::Logs::Severity::INFO,
        success: OpenTelemetry::SDK::Logs::Severity::INFO, # OTel has no "success"
        warn: OpenTelemetry::SDK::Logs::Severity::WARN,
        error: OpenTelemetry::SDK::Logs::Severity::ERROR,
        fatal: OpenTelemetry::SDK::Logs::Severity::FATAL
      }.freeze

      # Default baggage allowlist (safe keys that don't contain PII)
      DEFAULT_BAGGAGE_ALLOWLIST = %i[
        trace_id
        span_id
        request_id
        environment
        service_name
      ].freeze

      # Initialize OTel Logs adapter
      #
      # @param service_name [String] Service name for OTel (default: from config)
      # @param baggage_allowlist [Array<Symbol>] Allowlist of safe baggage keys
      # @param max_attributes [Integer] Max attributes per log (cardinality protection)
      def initialize(service_name: nil, baggage_allowlist: DEFAULT_BAGGAGE_ALLOWLIST, max_attributes: 50, **)
        super(**)
        @service_name = service_name
        @baggage_allowlist = baggage_allowlist
        @max_attributes = max_attributes

        setup_logger_provider
      end

      # Write event to OTel Logs API
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true on success
      def write(event_data)
        log_record = build_log_record(event_data)
        @logger.emit_log_record(log_record)
        true
      rescue StandardError => e
        warn "[E11y::OTelLogs] Failed to write event: #{e.message}"
        false
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] true if OTel SDK available and configured
      def healthy?
        @logger_provider && @logger
      end

      # Adapter capabilities
      #
      # @return [Hash] Capabilities hash
      def capabilities
        {
          batching: false, # OTel SDK handles batching internally
          compression: false,
          async: true, # OTel SDK is async by default
          streaming: false
        }
      end

      private

      # Setup OTel Logger Provider
      def setup_logger_provider
        @logger_provider = OpenTelemetry::SDK::Logs::LoggerProvider.new
        @logger = @logger_provider.logger(
          name: "e11y",
          version: E11y::VERSION
        )
      end

      # Build OTel log record from E11y event
      #
      # @param event_data [Hash] E11y event payload
      # @return [OpenTelemetry::SDK::Logs::LogRecord] OTel log record
      def build_log_record(event_data)
        OpenTelemetry::SDK::Logs::LogRecord.new(
          timestamp: event_data[:timestamp] || Time.now.utc,
          observed_timestamp: Time.now.utc,
          severity_number: map_severity(event_data[:severity]),
          severity_text: event_data[:severity].to_s.upcase,
          body: event_data[:event_name],
          attributes: build_attributes(event_data),
          trace_id: event_data[:trace_id],
          span_id: event_data[:span_id],
          trace_flags: nil
        )
      end

      # Map E11y severity to OTel severity
      #
      # @param severity [Symbol] E11y severity (:debug, :info, etc.)
      # @return [Integer] OTel severity number
      def map_severity(severity)
        SEVERITY_MAPPING[severity] || OpenTelemetry::SDK::Logs::Severity::INFO
      end

      # Build OTel attributes from E11y payload
      #
      # Applies:
      # - Cardinality protection (C04 Resolution)
      # - Baggage PII filtering (C08 Resolution)
      #
      # @param event_data [Hash] E11y event payload
      # @return [Hash] OTel attributes
      def build_attributes(event_data)
        attributes = {}

        # Add event metadata
        attributes["event.name"] = event_data[:event_name]
        attributes["event.version"] = event_data[:v] if event_data[:v]
        attributes["service.name"] = @service_name if @service_name

        # Add payload (with cardinality protection)
        payload = event_data[:payload] || {}
        payload.each do |key, value|
          # C04: Cardinality protection - limit attributes
          break if attributes.size >= @max_attributes

          # C08: Baggage PII protection - only allowlisted keys
          next unless baggage_allowed?(key)

          attributes["event.#{key}"] = value
        end

        attributes
      end

      # Check if key is allowed in baggage (C08 Resolution)
      #
      # @param key [Symbol, String] Attribute key
      # @return [Boolean] true if key is in allowlist
      def baggage_allowed?(key)
        @baggage_allowlist.include?(key.to_sym)
      end
    end
  end
end
