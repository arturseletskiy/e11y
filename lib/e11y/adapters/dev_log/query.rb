# lib/e11y/adapters/dev_log/query.rb
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module E11y
  module Adapters
    class DevLog
      # Read-only query interface for the JSONL dev log.
      #
      # Used by TUI, Browser Overlay, and MCP Server.
      #
      # Performance strategy:
      #   - In-memory cache invalidated by File.mtime
      #   - JSON parser: oj if available, stdlib JSON as fallback
      # rubocop:disable Metrics/ClassLength
      class Query
        # Value object returned by #interactions
        Interaction = Struct.new(:started_at, :trace_ids, :has_error?, :source) do
          def traces_count = trace_ids.size
        end

        ERROR_SEVERITIES = %w[error fatal].freeze

        # Choose fastest available JSON parser
        JSON_LOAD = if defined?(Oj)
                      ->(str) { Oj.load(str) }
                    else
                      ->(str) { ::JSON.parse(str) }
                    end

        def initialize(path)
          @path        = path.to_s
          @cache       = nil
          @cache_mtime = nil
        end

        # Return last +limit+ events, newest-first.
        def stored_events(limit: 1000, severity: nil, source: nil)
          events = all_events
          events = events.select { |e| e["severity"] == severity } if severity
          events = events.select { |e| e.dig("metadata", "source") == source } if source
          events.last(limit).reverse
        end

        # Find event by id (returns nil if not found).
        def find_event(id)
          all_events.find { |e| e["id"] == id }
        end

        # Full-text search in event_name and payload JSON.
        def search(query_str, limit: 500)
          q = query_str.downcase
          all_events.select do |e|
            e["event_name"].to_s.downcase.include?(q) ||
              ::JSON.generate(e["payload"] || {}).downcase.include?(q)
          end.last(limit).reverse
        end

        # All events for a given trace_id in chronological order.
        def events_by_trace(trace_id)
          all_events.select { |e| e["trace_id"] == trace_id }
        end

        # Aggregate stats about the log.
        def stats
          events = all_events
          {
            total_events: events.size,
            file_size: file_size,
            by_severity: events.group_by { |e| e["severity"] }.transform_values(&:count),
            by_event_name: events.group_by { |e| e["event_name"] }.transform_values(&:count),
            oldest_event: events.first&.dig("timestamp"),
            newest_event: events.last&.dig("timestamp")
          }
        end

        # True if log file was modified after +timestamp+.
        def updated_since?(timestamp)
          return false unless ::File.exist?(@path)

          ::File.mtime(@path) > timestamp
        end

        # Remove the log file and invalidate cache.
        def clear!
          ::FileUtils.rm_f(@path)
          invalidate_cache!
        end

        # Group traces into time-window interaction bands.
        # Returns Array<Interaction> sorted chronologically.
        def interactions(window_ms: 500, limit: 50, source: nil)
          events = all_events
          events = events.select { |e| e.dig("metadata", "source") == source } if source

          trace_map = build_trace_map(events)
          return [] if trace_map.empty?

          build_interaction_groups(trace_map, window_ms: window_ms, limit: limit)
        end

        private

        # --- interactions helpers ---

        def build_trace_map(events)
          trace_map = {}
          events.each { |e| merge_trace_entry(trace_map, e) }
          trace_map
        end

        def merge_trace_entry(trace_map, event)
          tid = event["trace_id"]
          return unless tid

          started = parse_started_at(event)
          return unless started

          entry = trace_map[tid] ||= { started_at: started, has_error: false,
                                       source: event.dig("metadata", "source") }
          entry[:has_error] = true if ERROR_SEVERITIES.include?(event["severity"])
          entry[:started_at] = started if started < entry[:started_at]
        end

        def build_interaction_groups(trace_map, window_ms:, limit:)
          sorted = trace_map.sort_by { |_, v| v[:started_at] }
          groups = []
          current = nil

          sorted.each do |trace_id, meta|
            current = append_to_groups(groups, current, trace_id, meta, window_ms)
          end

          groups.last(limit).map { |grp| interaction_struct(grp) }
        end

        def append_to_groups(groups, current, trace_id, meta, window_ms)
          if current.nil? || new_window?(current, meta, window_ms)
            current = { started_at: meta[:started_at], last_started_at: meta[:started_at],
                        trace_ids: [], has_error: false, source: meta[:source] }
            groups << current
          end
          current[:trace_ids] << trace_id
          current[:has_error] ||= meta[:has_error]
          current[:last_started_at] = meta[:started_at]
          current
        end

        def new_window?(current, meta, window_ms)
          (meta[:started_at] - current[:last_started_at]) * 1000 > window_ms
        end

        def interaction_struct(grp)
          Interaction.new(grp[:started_at], grp[:trace_ids], grp[:has_error], grp[:source])
        end

        # --- cache helpers ---

        def all_events
          return @cache if cache_valid?

          @cache       = load_events
          @cache_mtime = current_mtime
          @cache
        end

        def cache_valid?
          return false unless @cache && @cache_mtime
          return false unless ::File.exist?(@path)

          current_mtime == @cache_mtime
        end

        def current_mtime
          ::File.mtime(@path)
        rescue Errno::ENOENT
          nil
        end

        def invalidate_cache!
          @cache       = nil
          @cache_mtime = nil
        end

        def load_events
          return [] unless ::File.exist?(@path)

          events = []
          ::File.foreach(@path) do |line|
            line = line.chomp
            next if line.empty?

            events << JSON_LOAD.call(line)
          rescue ::JSON::ParserError
            next
          end
          events
        end

        def file_size
          ::File.size(@path)
        rescue Errno::ENOENT
          0
        end

        def parse_started_at(event)
          ts = event.dig("metadata", "started_at") || event["timestamp"]
          ::Time.parse(ts)
        rescue ArgumentError, TypeError
          nil
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
