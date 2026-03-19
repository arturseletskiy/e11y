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

        private

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
