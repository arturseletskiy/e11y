# frozen_string_literal: true

require "json"
require "securerandom"

module E11y
  module Adapters
    # Development-only adapter that stores events in a local JSONL file
    # and exposes a rich read API for TUI, Browser Overlay, and MCP Server.
    #
    # Auto-registered by Railtie in development/test environments.
    # Do not use in production.
    #
    # @example Manual setup
    #   adapter = E11y::Adapters::DevLog.new(
    #     path: Rails.root.join("log", "e11y_dev.jsonl"),
    #     max_size: 50.megabytes,
    #     keep_rotated: 5
    #   )
    class DevLog < Base
      # @param path           [String, Pathname]
      # @param max_size       [Integer]  Rotation threshold in bytes (default 50 MB)
      # @param max_lines      [Integer]  Rotation threshold in line count (default 10_000)
      # @param keep_rotated   [Integer]  Number of .N.gz files to retain (default 5)
      # @param enable_watcher [Boolean]  Reserved for future file-watcher integration
      def initialize(path: "log/e11y_dev.jsonl",
                     max_size: FileStore::DEFAULT_MAX_SIZE,
                     max_lines: FileStore::DEFAULT_MAX_LINES,
                     keep_rotated: FileStore::DEFAULT_KEEP_ROTATED,
                     enable_watcher: false)
        super({})
        @store          = FileStore.new(path: path, max_size: max_size,
                                        max_lines: max_lines, keep_rotated: keep_rotated)
        @query          = Query.new(@store.path)
        @enable_watcher = enable_watcher
      end

      # Write a single event to the JSONL file.
      #
      # @param event_data [Hash] Event from the E11y pipeline
      # @return [Boolean] true on success, false on error
      def write(event_data)
        @store.append(serialize(event_data))
        true
      rescue StandardError => e
        warn "[E11y::DevLog] write failed: #{e.message}"
        false
      end

      # --- Read API (delegated to Query) ---

      # @see Query#stored_events
      def stored_events(limit: 1000, severity: nil, source: nil)
        @query.stored_events(limit: limit, severity: severity, source: source)
      end

      # @see Query#find_event
      def find_event(id) = @query.find_event(id)

      # @see Query#search
      def search(query_str, limit: 500) = @query.search(query_str, limit: limit)

      # @see Query#events_by_name
      def events_by_name(name, limit: 500)
        @query.stored_events(limit: limit).select { |e| e["event_name"] == name }
      end

      # @see Query#events_by_severity
      def events_by_severity(sev, limit: 500)
        @query.stored_events(limit: limit, severity: sev)
      end

      # @see Query#events_by_trace
      def events_by_trace(trace_id) = @query.events_by_trace(trace_id)

      # @see Query#interactions
      def interactions(window_ms: 500, limit: 50, source: nil)
        @query.interactions(window_ms: window_ms, limit: limit, source: source)
      end

      # @see Query#stats
      def stats = @query.stats

      # @see Query#updated_since?
      def updated_since?(timestamp) = @query.updated_since?(timestamp)

      # @see Query#clear!
      def clear! = @query.clear!

      # Advertise dev_log and readable capabilities.
      def capabilities
        super.merge(dev_log: true, readable: true)
      end

      private

      def serialize(event_data)
        data = event_data.is_a?(::Hash) ? event_data.transform_keys(&:to_s) : {}
        enrich_ids!(data)
        enrich_metadata!(data)
        normalize_json_event_identity!(data)
        ::JSON.generate(data)
      end

      def enrich_ids!(data)
        data["id"]        ||= ::SecureRandom.uuid
        data["timestamp"] ||= ::Time.now.utc.iso8601(3)
      end

      def enrich_metadata!(data)
        source = ::Thread.current[:e11y_source] || "web"
        meta   = (data["metadata"] || {}).dup
        meta["source"]     ||= source
        meta["started_at"] ||= data["timestamp"]
        data["metadata"] = meta
      end

      # Avoid +#<Class:0x…>+ in JSON; keep top-level +event_name+ when only nested carries it.
      def normalize_json_event_identity!(data)
        coerce_event_class_for_json!(data)
        promote_payload_event_name!(data)
      end

      def coerce_event_class_for_json!(data)
        ec = data["event_class"]
        return if ec.nil?

        return unless ec.is_a?(::Module)

        name = ec.name
        if name && !name.empty?
          data["event_class"] = name
        else
          data.delete("event_class")
        end
      end

      def promote_payload_event_name!(data)
        top = data["event_name"]
        return if top.is_a?(::String) && !top.strip.empty?

        pl = data["payload"]
        return unless pl.is_a?(::Hash)

        nested = pl["event_name"] || pl[:event_name]
        nested = nested&.to_s&.strip
        return if nested.nil? || nested.empty?

        data["event_name"] = nested
      end
    end
  end
end
