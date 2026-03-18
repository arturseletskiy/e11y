# frozen_string_literal: true

module E11y
  module OpenTelemetry
    # Semantic conventions mapper for OTel attributes (ADR-007 §4, F4).
    #
    # Maps E11y payload keys to OpenTelemetry semantic convention attribute names.
    # When event_name matches a convention type (http, database, etc.), known keys
    # are mapped to semantic names (e.g. method → http.method).
    #
    # @see https://opentelemetry.io/docs/specs/semconv/
    class SemanticConventions
      # Key mappings by convention type
      # https://opentelemetry.io/docs/specs/semconv/http/
      # https://opentelemetry.io/docs/specs/semconv/database/
      # https://opentelemetry.io/docs/specs/semconv/exceptions/
      CONVENTIONS = {
        http: {
          "method" => "http.method",
          "route" => "http.route",
          "path" => "http.target",
          "status_code" => "http.status_code",
          "status" => "http.status_code",
          "duration_ms" => "http.server.duration",
          "request_size" => "http.request.body.size",
          "response_size" => "http.response.body.size",
          "user_agent" => "http.user_agent",
          "client_ip" => "http.client_ip",
          "scheme" => "http.scheme",
          "host" => "http.host",
          "server_name" => "http.server_name"
        },
        database: {
          "query" => "db.statement",
          "statement" => "db.statement",
          "duration_ms" => "db.operation.duration",
          "rows_affected" => "db.operation.rows_affected",
          "connection_id" => "db.connection.id",
          "database_name" => "db.name",
          "table_name" => "db.sql.table",
          "operation" => "db.operation"
        },
        rpc: {
          "service" => "rpc.service",
          "method" => "rpc.method",
          "system" => "rpc.system",
          "status_code" => "rpc.grpc.status_code"
        },
        messaging: {
          "queue_name" => "messaging.destination.name",
          "message_id" => "messaging.message.id",
          "conversation_id" => "messaging.message.conversation_id",
          "payload_size" => "messaging.message.payload_size_bytes",
          "operation" => "messaging.operation"
        },
        exception: {
          "error_type" => "exception.type",
          "error_message" => "exception.message",
          "error_class" => "exception.type",
          "stacktrace" => "exception.stacktrace"
        }
      }.freeze

      # Map payload keys to OTel semantic attribute names.
      #
      # @param event_name [String] Event name (used to detect convention type)
      # @param payload [Hash] Event payload
      # @return [Hash] Mapped payload with semantic keys where applicable
      def self.map(event_name, payload)
        convention_type = detect_convention_type(event_name)
        return payload.transform_keys { |k| "event.#{k}" } unless convention_type

        conventions = CONVENTIONS[convention_type]
        payload.each_with_object({}) do |(key, value), mapped|
          otel_key = conventions[key.to_s] || "event.#{key}"
          mapped[otel_key] = value
        end
      end

      # Map a single key to OTel semantic attribute name.
      #
      # @param event_name [String] Event name (used to detect convention type)
      # @param key [String, Symbol] Payload key
      # @return [String] OTel attribute key
      def self.map_key(event_name, key)
        convention_type = detect_convention_type(event_name)
        return "event.#{key}" unless convention_type

        conventions = CONVENTIONS[convention_type]
        conventions[key.to_s] || "event.#{key}"
      end

      # Detect convention type from event name
      #
      # @param event_name [String]
      # @return [Symbol, nil]
      def self.detect_convention_type(event_name)
        name = event_name.to_s
        return :http if name.match?(/http|request|response/i)
        return :database if name.match?(/database|query|sql|postgres|mysql/i)
        return :rpc if name.match?(/rpc|grpc/i)
        return :messaging if name.match?(/message|queue|kafka|rabbitmq|sidekiq|job/i)
        return :exception if name.match?(/error|exception|failure/i)

        nil
      end
    end
  end
end
