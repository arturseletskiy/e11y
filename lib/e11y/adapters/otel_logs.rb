# frozen_string_literal: true

require "ostruct"

# Check if OpenTelemetry SDK is available
begin
  require "opentelemetry/sdk"
  require "opentelemetry/logs"
  require "opentelemetry-logs-sdk" # Provides OpenTelemetry::SDK::Logs::LoggerProvider
rescue LoadError
  raise LoadError, <<~ERROR
    OpenTelemetry SDK not available!

    To use E11y::Adapters::OTelLogs, add to your Gemfile:

      gem 'opentelemetry-sdk'
      gem 'opentelemetry-logs-api'
      gem 'opentelemetry-logs-sdk'

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
      # E11y severity → OTel severity_number mapping
      # See: https://opentelemetry.io/docs/specs/otel/logs/data-model/#field-severitynumber
      # Severity numbers: TRACE=1, DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21
      SEVERITY_MAPPING = {
        debug: 5,  # DEBUG
        info: 9,   # INFO
        success: 9, # INFO (OTel has no "success" level)
        warn: 13,  # WARN
        error: 17, # ERROR
        fatal: 21  # FATAL
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
      # @param endpoint [String, nil] OTLP endpoint (e.g. http://localhost:4318/v1/logs).
      #   When set, logs are exported to OTel Collector. Default: in-process only.
      def initialize(service_name: nil, baggage_allowlist: DEFAULT_BAGGAGE_ALLOWLIST, max_attributes: 50, endpoint: nil, **)
        super(**)
        @service_name = service_name
        @baggage_allowlist = baggage_allowlist
        @max_attributes = max_attributes
        @endpoint = endpoint

        setup_logger_provider
      end

      # Write event to OTel Logs API
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true on success
      def write(event_data)
        params = build_log_record_params(event_data)
        @logger.on_emit(**params)
        true
      rescue StandardError => e
        warn "[E11y::OTelLogs] Failed to write event: #{e.message}"
        false
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] true if OTel SDK available and configured
      def healthy?
        !@logger_provider.nil? && !@logger.nil?
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

        # Add OTLP exporter when endpoint configured (sends to OTel Collector)
        if @endpoint
          require "opentelemetry-exporter-otlp-logs"
          exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(endpoint: @endpoint)
          processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)
          @logger_provider.add_log_record_processor(processor)
        end

        @logger = @logger_provider.logger(
          name: "e11y",
          version: E11y::VERSION
        )
      rescue LoadError => e
        warn "[E11y::OTelLogs] OTLP export requested but opentelemetry-exporter-otlp-logs not available: #{e.message}"
        @logger_provider ||= OpenTelemetry::SDK::Logs::LoggerProvider.new
        @logger = @logger_provider.logger(name: "e11y", version: E11y::VERSION)
      end

      # Build params for Logger#on_emit from E11y event
      #
      # @param event_data [Hash] E11y event payload
      # @return [Hash] Keyword args for on_emit
      def build_log_record_params(event_data)
        {
          timestamp: event_data[:timestamp] || Time.now.utc,
          observed_timestamp: Time.now.utc,
          severity_number: map_severity(event_data[:severity]),
          severity_text: event_data[:severity].to_s.upcase,
          body: event_data[:event_name],
          attributes: build_attributes(event_data),
          trace_id: event_data[:trace_id],
          span_id: event_data[:span_id],
          trace_flags: nil
        }
      end

      # Build log record struct for testing (same data as build_log_record_params)
      #
      # @param event_data [Hash] E11y event payload
      # @return [OpenStruct] Struct with attributes for test assertions
      def build_log_record(event_data)
        params = build_log_record_params(event_data)
        OpenStruct.new(params)
      end

      # Map E11y severity to OTel severity
      #
      # @param severity [Symbol] E11y severity (:debug, :info, etc.)
      # @return [Integer] OTel severity number
      def map_severity(severity)
        SEVERITY_MAPPING[severity] || 9 # Default to INFO
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
