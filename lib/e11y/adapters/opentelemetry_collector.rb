# frozen_string_literal: true

# OTLP HTTP adapter — requires Faraday
begin
  require "faraday"
rescue LoadError
  raise LoadError, <<~ERROR
    Faraday not available!

    To use E11y::Adapters::OpenTelemetryCollector, add to your Gemfile:

      gem 'faraday'

    Then run: bundle install
  ERROR
end

require "e11y/opentelemetry/semantic_conventions"

module E11y
  module Adapters
    # OpenTelemetry Collector adapter (ADR-007 §3, F1)
    #
    # Sends E11y events to OpenTelemetry Collector via OTLP HTTP.
    # No OpenTelemetry SDK required — uses raw HTTP (Faraday).
    #
    # **Use case:** When you want to send logs to OTel Collector without
    # loading the full OTel SDK (e.g. lightweight apps, or OTelLogs already
    # handles in-process; this adapter sends to external Collector).
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.adapters[:otel_collector] = E11y::Adapters::OpenTelemetryCollector.new(
    #       endpoint: "http://localhost:4318",
    #       service_name: "my-app"
    #     )
    #   end
    #
    # @see ADR-007 §3 OTel Collector Adapter
    class OpenTelemetryCollector < Base
      SEVERITY_MAPPING = {
        debug: 5, info: 9, success: 9, warn: 13, error: 17, fatal: 21
      }.freeze

      def initialize(endpoint: nil, service_name: nil, headers: {}, timeout: 10, max_attributes: 50, **opts)
        super(**opts)
        @endpoint = (endpoint || ENV["OTEL_EXPORTER_OTLP_ENDPOINT"] || "http://localhost:4318").chomp("/")
        @service_name = service_name || E11y.config&.service_name || "e11y"
        @headers = headers
        @timeout = timeout
        @max_attributes = max_attributes
        @connection = build_connection
      end

      def write(event_data)
        payload = build_otlp_payload([event_data])
        response = @connection.post("/v1/logs") do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = payload.to_json
        end
        response.success?
      rescue Faraday::Error => e
        warn "[E11y::OpenTelemetryCollector] HTTP error: #{e.message}"
        false
      end

      def healthy?
        !@connection.nil?
      end

      def capabilities
        { batching: false, compression: false, async: false, streaming: false }
      end

      private

      def build_connection
        Faraday.new(url: @endpoint, request: { timeout: @timeout }) do |f|
          @headers.each { |k, v| f.headers[k.to_s] = v }
          f.adapter Faraday.default_adapter
        end
      end

      def build_otlp_payload(events)
        log_records = events.map { |e| to_otel_log_record(e) }
        {
          resourceLogs: [{
            resource: { attributes: resource_attributes },
            scopeLogs: [{
              scope: { name: "e11y", version: E11y::VERSION },
              logRecords: log_records
            }]
          }]
        }
      end

      def resource_attributes
        [
          { key: "service.name", value: { stringValue: @service_name } },
          { key: "service.version", value: { stringValue: E11y::VERSION } },
          { key: "deployment.environment", value: { stringValue: (E11y.config&.environment || ENV["RAILS_ENV"] || "development") } },
          { key: "host.name", value: { stringValue: hostname } },
          { key: "process.pid", value: { intValue: Process.pid.to_s } }
        ]
      end

      def hostname
        require "socket"
        Socket.gethostname
      rescue StandardError
        ENV["HOSTNAME"] || "unknown"
      end

      def to_otel_log_record(event)
        ts = event[:timestamp] || Time.now.utc
        ts_nano = (ts.to_f * 1_000_000_000).to_i
        {
          timeUnixNano: ts_nano.to_s,
          observedTimeUnixNano: (Time.now.to_f * 1_000_000_000).to_i.to_s,
          severityNumber: SEVERITY_MAPPING[event[:severity]] || 9,
          severityText: (event[:severity] || :info).to_s.upcase,
          body: { stringValue: event[:event_name] },
          attributes: build_log_attributes(event),
          traceId: encode_hex(event[:trace_id], 32),
          spanId: encode_hex(event[:span_id], 16)
        }.compact
      end

      def build_log_attributes(event)
        attrs = []
        attrs << { key: "event.name", value: { stringValue: event[:event_name] } }
        attrs << { key: "event.version", value: { stringValue: event[:v].to_s } } if event[:v]
        attrs << { key: "service.name", value: { stringValue: @service_name } }

        payload = event[:payload] || {}
        payload.each do |key, value|
          break if attrs.size >= @max_attributes

          otel_key = E11y::OpenTelemetry::SemanticConventions.map_key(event[:event_name], key)
          attrs << encode_attr(otel_key, value)
        end
        attrs
      end

      def encode_attr(key, value)
        case value
        when String
          { key: key.to_s, value: { stringValue: value } }
        when Integer
          { key: key.to_s, value: { intValue: value.to_s } }
        when Float
          { key: key.to_s, value: { doubleValue: value } }
        when TrueClass, FalseClass
          { key: key.to_s, value: { boolValue: value } }
        else
          { key: key.to_s, value: { stringValue: value.to_s } }
        end
      end

      def encode_hex(str, expected_len)
        return nil if str.to_s.empty?

        s = str.to_s.gsub(/[^0-9a-fA-F]/, "")
        return nil if s.length != expected_len

        s.downcase
      end
    end
  end
end
