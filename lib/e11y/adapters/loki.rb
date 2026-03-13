# frozen_string_literal: true

# Check if Faraday is available
begin
  require "faraday"
  require "faraday/retry" # Retry middleware
rescue LoadError
  raise LoadError, <<~ERROR
    Faraday not available!

    To use E11y::Adapters::Loki, add to your Gemfile:

      gem 'faraday'
      gem 'faraday-retry'

    Then run: bundle install
  ERROR
end

require "json"
require "zlib"
require_relative "../metrics/cardinality_protection"

module E11y
  module Adapters
    # Loki adapter for shipping logs to Grafana Loki.
    #
    # Features:
    # - Automatic batching for efficiency
    # - Optional gzip compression
    # - Configurable labels
    # - Optional cardinality protection for labels (C04 Resolution, disabled by default)
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
    # @example With Cardinality Protection (C04 Resolution - Enterprise)
    #   # Enable for high-traffic environments to prevent label explosion
    #   adapter = E11y::Adapters::Loki.new(
    #     url: "http://loki:3100",
    #     labels: { app: "my_app", env: "production" },
    #     enable_cardinality_protection: true,  # Disabled by default
    #     max_label_cardinality: 100            # Max unique values per label
    #   )
    #   # Note: High-cardinality labels (user_id, order_id) will be filtered
    #
    # @see https://grafana.com/docs/loki/latest/api/#push-log-entries-to-loki
    # @see ADR-009 §8 (C04 Resolution - Universal Cardinality Protection)
    # rubocop:disable Metrics/ClassLength
    # Loki adapter contains HTTP client, batching, and Loki-specific formatting logic
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
      # @option config [Boolean] :enable_cardinality_protection (false) Enable cardinality protection for labels (C04)
      # @option config [Integer] :max_label_cardinality (100) Max unique values per label when protection enabled
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Adapter initialization requires many instance variable assignments
      def initialize(config = {})
        @url = config[:url]
        @labels = config.fetch(:labels, {})
        @batch_size = config.fetch(:batch_size, DEFAULT_BATCH_SIZE)
        @batch_timeout = config.fetch(:batch_timeout, DEFAULT_BATCH_TIMEOUT)
        @timeout = config.fetch(:timeout, 5)
        @health_check_timeout = [@timeout, 2].min
        @compress = config.fetch(:compress, true)
        @tenant_id = config[:tenant_id]
        @enable_cardinality_protection = config.fetch(:enable_cardinality_protection, false)
        @max_label_cardinality = config.fetch(:max_label_cardinality, 100)

        @buffer = []
        @buffer_mutex = Mutex.new
        @connection = nil
        @last_flush = Time.now

        # C04: Optional cardinality protection (disabled by default for logs)
        if @enable_cardinality_protection
          @cardinality_protection = E11y::Metrics::CardinalityProtection.new(
            max_unique_values: @max_label_cardinality
          )
        end

        super

        build_connection!
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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

      # Loki health check endpoint
      READY_PATH = "/ready"

      # Check if adapter is healthy (Loki server reachable)
      #
      # Performs actual HTTP GET to /ready. Returns false on connection failure,
      # timeout, or non-2xx response.
      #
      # @return [Boolean] True if Loki responds with 2xx
      def healthy?
        return false unless @connection

        response = @connection.get(READY_PATH)
        (200..299).cover?(response.status)
      rescue Faraday::Error, Errno::ECONNREFUSED, Errno::ETIMEDOUT
        false
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

      # Build Faraday connection with retry middleware
      #
      # Uses Faraday's built-in retry middleware for exponential backoff
      # on transient network errors and 5xx responses.
      #
      # Note: Connection pooling is handled at HTTP client level (Net::HTTP persistent).
      # Faraday reuses persistent connections by default. For advanced pooling,
      # configure Faraday adapter (e.g., :net_http_persistent, :typhoeus).
      #
      # @see ADR-004 Section 7.1 (Retry Policy via gem-level middleware)
      # @see ADR-004 Section 6.1 (Connection pooling via HTTP client)
      # HTTP client configuration requires detailed retry and connection settings
      def build_connection!
        @connection = Faraday.new(url: @url) do |f|
          # Retry middleware (exponential backoff: 1s, 2s, 4s)
          f.request :retry,
                    max: 3,
                    interval: 1.0,
                    backoff_factor: 2,
                    interval_randomness: 0.2, # ±20% jitter
                    retry_statuses: [429, 500, 502, 503, 504],
                    methods: [:post],
                    exceptions: [
                      Faraday::TimeoutError,
                      Faraday::ConnectionFailed,
                      Errno::ECONNREFUSED,
                      Errno::ETIMEDOUT
                    ]

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
      # Uses normalized event_name (e.g., "Events::TestLoki" -> "test.loki") for consistent
      # querying via LogQL. Matches Versioning middleware convention.
      #
      # @param event_data [Hash] Event data
      # @return [Hash] Labels for Loki stream
      def extract_labels(event_data)
        event_labels = {
          event_name: normalize_event_name_for_labels(event_data[:event_name].to_s),
          severity: event_data[:severity].to_s
        }

        # Merge static and event labels
        all_labels = @labels.merge(event_labels)

        # C04: Apply cardinality protection if enabled (enterprise use case)
        # Disabled by default - Loki is a log system, labels are for stream filtering only
        all_labels = @cardinality_protection.filter(all_labels, "loki.stream") if @enable_cardinality_protection && @cardinality_protection

        all_labels.transform_keys(&:to_s)
      end

      # Format single event as Loki entry
      #
      # @param event_data [Hash] Event data
      # @return [Array] [timestamp_ns, line]
      def format_loki_entry(event_data)
        # Parse timestamp - can be Time object, ISO8601 string, or nil
        timestamp = event_data[:timestamp]
        timestamp = if timestamp.is_a?(String)
                      Time.parse(timestamp)
                    elsif timestamp.nil?
                      Time.now
                    else
                      timestamp
                    end

        timestamp_ns = timestamp.to_f * 1_000_000_000
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

      # Normalize event name for Loki labels (matches Versioning middleware convention)
      #
      # @param name [String] Event name (e.g., "Events::TestLoki")
      # @return [String] Normalized name (e.g., "test.loki")
      def normalize_event_name_for_labels(name)
        return name if name.nil? || name.empty?

        n = name.sub(/^Events::/, "").sub(/V\d+$/, "")
        n.gsub("::", ".")
           .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
           .gsub(/([a-z\d])([A-Z])/, '\1_\2')
           .downcase
           .tr("_", ".")
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
    # rubocop:enable Metrics/ClassLength
  end
end
