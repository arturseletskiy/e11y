# frozen_string_literal: true

# Helpers for querying Loki API in integration tests
module LokiHelpers
  # Query Loki for logs matching the given label selector
  #
  # @param loki_url [String] Loki base URL
  # @param label_selector [Hash] Label selector (e.g., { app: "test_app", event_name: "test.event" })
  # @param limit [Integer] Maximum number of results (default: 100)
  # @return [Array<Hash>] Array of log entries
  def query_loki_logs(loki_url, label_selector:, limit: 100) # rubocop:todo Metrics/AbcSize
    require "net/http"
    require "uri"
    require "json"

    uri = URI("#{loki_url}/loki/api/v1/query_range")
    params = {
      query: build_logql_query(label_selector),
      limit: limit,
      start: (Time.now.to_i - 300) * 1_000_000_000, # 5 minutes ago in nanoseconds
      end: Time.now.to_i * 1_000_000_000 # Now in nanoseconds
    }
    uri.query = URI.encode_www_form(params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5

    response = http.get(uri.request_uri)
    return [] unless response.code.to_i == 200

    data = JSON.parse(response.body)
    return [] unless data["status"] == "success"

    # Extract log entries from Loki response
    result = data["data"]&.dig("result") || []
    entries = []
    result.each do |stream|
      stream["values"]&.each do |value|
        timestamp_ns, log_line = value
        entries << {
          timestamp: timestamp_ns.to_i / 1_000_000_000,
          log: JSON.parse(log_line)
        }
      end
    end
    entries
  rescue StandardError => e
    warn "Loki query failed: #{e.class}: #{e.message}"
    warn "Backtrace: #{e.backtrace.first(3).join("\n")}" if ENV["E11Y_DEBUG_LOKI"]
    []
  end

  # Build LogQL query from label selector
  #
  # @param label_selector [Hash] Label selector
  # @return [String] LogQL query string
  def build_logql_query(label_selector)
    conditions = label_selector.map { |k, v| "#{k}=\"#{v}\"" }.join(", ")
    "{#{conditions}}"
  end

  # Normalize event name for Loki query (same normalization as Versioning middleware)
  #
  # @param event_name [String] Event name (e.g., "Events::TestLoki")
  # @return [String] Normalized name (e.g., "test.loki")
  def normalize_event_name_for_loki(event_name)
    return event_name unless event_name

    # Remove "Events::" namespace prefix
    name = event_name.sub(/^Events::/, "")
    # Remove version suffix (V2, V3, etc.)
    name = name.sub(/V\d+$/, "")
    # Convert nested namespaces to dots
    name = name.gsub("::", ".")
    # Convert to snake_case then dots
    name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2') # ABCWord → ABC_Word
        .gsub(/([a-z\d])([A-Z])/, '\1_\2') # wordWord → word_Word
        .downcase
        .tr("_", ".") # Convert underscores to dots
  end

  # Wait for events to appear in Loki (with retries)
  #
  # @param loki_url [String] Loki base URL
  # @param label_selector [Hash] Label selector
  # @param expected_count [Integer] Expected number of events
  # @param timeout [Integer] Timeout in seconds (default: 10)
  # @return [Array<Hash>] Found log entries
  def wait_for_loki_events(loki_url, label_selector:, expected_count: 1, timeout: 10)
    start_time = Time.now
    while Time.now - start_time < timeout
      entries = query_loki_logs(loki_url, label_selector: label_selector)
      return entries if entries.size >= expected_count

      sleep 0.5
    end
    query_loki_logs(loki_url, label_selector: label_selector)
  end
end

RSpec.configure do |config|
  config.include LokiHelpers
end
