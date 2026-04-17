# frozen_string_literal: true

require "e11y/adapters/dev_log/query"
require "e11y/adapters/dev_log"

module E11y
  module Devtools
    module Overlay
      # Plain Ruby controller logic — testable without Rails.
      # Used by the Rails route handlers (see config/routes.rb).
      class Controller
        def initialize(query = nil)
          @query = query || resolve_query
        end

        def events_for(trace_id: nil, limit: 50)
          if trace_id && !trace_id.empty?
            @query.events_by_trace(trace_id)
          else
            @query.stored_events(limit: limit)
          end
        end

        def recent_events(limit: 50)
          clamped = limit.to_i.clamp(1, 500)
          @query.stored_events(limit: clamped)
        end

        def clear_log!
          @query.clear!
        end

        def stats
          @query.stats
        end

        # @return [Array<Hash>] JSON-ready rows, newest interaction first (matches TUI ordering).
        def v1_interactions(source: nil, limit: 50, window_ms: 500)
          src = normalize_v1_source(source)
          lim = limit.to_i.clamp(1, 500)
          wm = window_ms.to_i.clamp(50, 10_000)
          list = @query.interactions(window_ms: wm, limit: lim, source: src)
          list.reverse.map { |row| v1_interaction_hash(row) }
        end

        # @return [Array<Hash>] events for trace, chronological (same as DevLog::Query).
        def v1_trace_events(trace_id)
          return [] if trace_id.nil? || trace_id.to_s.empty?

          @query.events_by_trace(trace_id.to_s)
        end

        # @return [Array<Hash>] newest-first flat list for badge / pulse.
        def v1_recent_events(limit: 100)
          lim = limit.to_i.clamp(1, 500)
          @query.stored_events(limit: lim)
        end

        private

        def normalize_v1_source(source)
          s = source.to_s
          return "web" if s == "web"
          return "job" if s == "job"

          nil
        end

        def v1_interaction_hash(row)
          {
            "started_at" => row.started_at.iso8601(3),
            "trace_ids" => row.trace_ids,
            "has_error" => row.has_error?,
            "source" => row.source,
            "traces_count" => row.traces_count,
            "method" => row.http_method,
            "path" => row.http_path,
            "status" => row.http_status,
            "duration_ms" => row.duration_ms
          }
        end

        def resolve_query
          if defined?(E11y) && E11y.respond_to?(:configuration)
            adapter = E11y.configuration.adapters[:dev_log]
            return adapter if adapter.respond_to?(:stored_events)
          end
          default_path = if defined?(Rails) && Rails.respond_to?(:root)
                           Rails.root.join("log", "e11y_dev.jsonl").to_s
                         else
                           "log/e11y_dev.jsonl"
                         end
          E11y::Adapters::DevLog::Query.new(default_path)
        end
      end
    end
  end
end
