# frozen_string_literal: true

require "faraday"
require "json"
require "zlib"

module E11y
  module Adapters
    # Loki adapter for shipping logs to Grafana Loki.
    #
    # Features:
    # - Automatic batching for efficiency
    # - Optional gzip compression
    # - Configurable labels
    # - Multi-tenant support
    # - Thread-safe buffer
    #
    # @example Basic usage
    #   adapter = E11y::Adapters::Loki.new(
    #     url: "http://loki:3100",
    #     labels: { app: "my_app", env: "production" },
    #     batch_size: 100,
    #     batch_timeout: 5
    #   )
    #
    # @example With Registry
    #   E11y::Adapters::Registry.register(
    #     :loki_logger,
    #     E11y::Adapters::Loki.new(url: ENV["LOKI_URL"])
    #   )
    #
    # @see https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki
    class Loki < Base
      # Default batch size (events)
      DEFAULT_BATCH_SIZE = 100

      # Default batch timeout (seconds)
      DEFAULT_BATCH_TIMEOUT = 5

      # Loki push endpoint
      PUSH_PATH = "/loki/api/v1/push"

      attr_reader :url, :labels, :batch_size, :batch_timeout, :compress, :tenant_id

      # Initialize Loki adapter
      #
      # @param config [Hash] Configuration options
      # @option config [String] :url (required) Loki server URL (e.g., "http://loki:3100")
      # @option config [Hash] :labels ({}) Static labels to attach to all logs
      # @option config [Integer] :batch_size (100) Number of events to batch before sending
      # @option config [Integer] :batch_timeout (5) Max seconds to wait before flushing batch
      # @option config [Boolean] :compress (true) Enable gzip compression
      # @option config [String] :tenant_id (nil) Loki tenant ID (X-Scope-OrgID header)
      def initialize(config = {})
        @url = config[:url]
        @labels = config.fetch(:labels, {})
        @batch_size = config.fetch(:batch_size, DEFAULT_BATCH_SIZE)
        @batch_timeout = config.fetch(:batch_timeout, DEFAULT_BATCH_TIMEOUT)
        @compress = config.fetch(:compress, true)
        @tenant_id = config[:tenant_id]

        @buffer = []
        @buffer_mutex = Mutex.new
        @connection = nil
        @last_flush = Time.now

        super

        build_connection!
      end

      # Write a single event to buffer
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] Success status
      def write(event_data)
        @buffer_mutex.synchronize do
          @buffer << event_data

          flush_if_needed!
        end

        true
      rescue StandardError => e
        warn "E11y Loki adapter error: #{e.message}"
        false
      end

      # Write a batch of events to buffer
      #
      # @param events [Array<Hash>] Array of event payloads
      # @return [Boolean] Success status
      def write_batch(events)
        @buffer_mutex.synchronize do
          @buffer.concat(events)

          flush_if_needed!
        end

        true
      rescue StandardError => e
        warn "E11y Loki adapter batch error: #{e.message}"
        false
      end

      # Close adapter and flush remaining events
      def close
        @buffer_mutex.synchronize do
          flush_buffer! unless @buffer.empty?
        end
      end

      # Check if adapter is healthy
      #
      # @return [Boolean] True if connection is established
      def healthy?
        @connection && @connection.respond_to?(:get)
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        super.merge(
          batching: true,
          compression: @compress,
          async: true,
          streaming: false
        )
      end

      private

      # Validate configuration
      def validate_config!
        raise ArgumentError, "Loki adapter requires :url" unless @url
        raise ArgumentError, "batch_size must be positive" if @batch_size <= 0
        raise ArgumentError, "batch_timeout must be positive" if @batch_timeout <= 0
      end

      # Build Faraday connection
      def build_connection!
        @connection = Faraday.new(url: @url) do |f|
          f.request :json
          f.response :raise_error
          f.adapter Faraday.default_adapter
        end
      end

      # Check if buffer should be flushed
      def flush_if_needed!
        should_flush = @buffer.size >= @batch_size ||
                       (Time.now - @last_flush) >= @batch_timeout

        flush_buffer! if should_flush
      end

      # Flush buffer to Loki
      def flush_buffer!
        return if @buffer.empty?

        events = @buffer.dup
        @buffer.clear
        @last_flush = Time.now

        # Release mutex before I/O
        @buffer_mutex.unlock
        begin
          send_to_loki(events)
        ensure
          @buffer_mutex.lock
        end
      end

      # Send events to Loki
      #
      # @param events [Array<Hash>] Events to send
      def send_to_loki(events)
        payload = format_loki_payload(events)
        body = JSON.generate(payload)

        body = compress_body(body) if @compress

        headers = build_headers

        @connection.post(PUSH_PATH, body, headers)
      rescue Faraday::Error => e
        warn "E11y Loki adapter HTTP error: #{e.message}"
        false
      end

      # Format events as Loki payload
      #
      # @param events [Array<Hash>] Events to format
      # @return [Hash] Loki push API payload
      def format_loki_payload(events)
        # Group events by labels
        streams = events.group_by { |e| extract_labels(e) }.map do |labels, group_events|
          {
            stream: labels,
            values: group_events.map { |e| format_loki_entry(e) }
          }
        end

        { streams: streams }
      end

      # Extract labels from event
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Labels for Loki stream
      def extract_labels(event_data)
        event_labels = {
          event_name: event_data[:event_name].to_s,
          severity: event_data[:severity].to_s
        }

        @labels.merge(event_labels).transform_keys(&:to_s)
      end

      # Format single event as Loki entry
      #
      # @param event_data [Hash] Event data
      # @return [Array] [timestamp_ns, line]
      def format_loki_entry(event_data)
        timestamp_ns = (event_data[:timestamp] || Time.now).to_f * 1_000_000_000
        line = event_data.to_json

        [timestamp_ns.to_i.to_s, line]
      end

      # Compress body with gzip
      #
      # @param body [String] Body to compress
      # @return [String] Compressed body
      def compress_body(body)
        io = StringIO.new
        gz = Zlib::GzipWriter.new(io)
        gz.write(body)
        gz.close
        io.string
      end

      # Build HTTP headers
      #
      # @return [Hash] Headers for Loki request
      def build_headers
        headers = {
          "Content-Type" => "application/json"
        }

        headers["Content-Encoding"] = "gzip" if @compress
        headers["X-Scope-OrgID"] = @tenant_id if @tenant_id

        headers
      end
    end
  end
end
